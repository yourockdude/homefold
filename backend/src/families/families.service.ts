import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ChangesService } from '../changes/changes.service';
import { PlanService } from '../plan/plan.service';
import { Storage } from '../storage/storage.service';
import { RealtimeService } from '../notifications/realtime.service';
import { Ctx, FamilyCtx } from '../common/context';
import { Err } from '../common/errors';

@Injectable()
export class FamiliesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly changes: ChangesService,
    private readonly plan: PlanService,
    private readonly storage: Storage,
    private readonly realtime: RealtimeService,
  ) {}

  async create(ctx: Ctx, name: string, displayName: string) {
    if (ctx.familyId) throw Err.conflict('ALREADY_IN_FAMILY', 'Вы уже состоите в семье');
    const family = await this.prisma.$transaction(async (tx) => {
      const f = await tx.family.create({ data: { name, createdById: ctx.userId } });
      await tx.familyMember.create({ data: { familyId: f.id, userId: ctx.userId, role: 'admin', displayName, color: 0 } });
      await tx.notificationSettings.upsert({ where: { userId: ctx.userId }, update: {}, create: { userId: ctx.userId } });
      return f;
    });
    await this.changes.record(family.id, 'family', family.id);
    return this.get({ ...ctx, familyId: family.id, role: 'admin', displayName });
  }

  async get(ctx: FamilyCtx) {
    const family = await this.prisma.family.findUniqueOrThrow({ where: { id: ctx.familyId }, include: { members: { orderBy: { joinedAt: 'asc' } } } });
    return {
      id: family.id,
      name: family.name,
      createdAt: family.createdAt,
      myRole: ctx.role,
      members: family.members.map((m) => ({ userId: m.userId, displayName: m.displayName, role: m.role, color: m.color, joinedAt: m.joinedAt })),
      plan: await this.plan.get(family.id),
    };
  }

  async rename(ctx: FamilyCtx, name: string) {
    await this.prisma.family.update({ where: { id: ctx.familyId }, data: { name } });
    await this.changes.record(ctx.familyId, 'family', ctx.familyId);
    return this.get(ctx);
  }

  private async adminCount(familyId: string) {
    return this.prisma.familyMember.count({ where: { familyId, role: 'admin' } });
  }

  async updateMember(ctx: FamilyCtx, userId: string, patch: { displayName?: string; role?: 'admin' | 'member'; color?: number }) {
    const target = await this.prisma.familyMember.findFirst({ where: { familyId: ctx.familyId, userId } });
    if (!target) throw Err.notFound('Участник');
    const isSelf = userId === ctx.userId;
    if ((patch.role !== undefined || !isSelf) && ctx.role !== 'admin') throw Err.forbidden('Менять роли и чужие профили может только администратор');
    if (patch.role === 'member' && target.role === 'admin' && (await this.adminCount(ctx.familyId)) <= 1) {
      throw Err.conflict('LAST_ADMIN', 'Нельзя снять роль с последнего администратора. Сначала назначьте другого');
    }
    await this.prisma.familyMember.update({ where: { id: target.id }, data: patch });
    await this.changes.record(ctx.familyId, 'family', ctx.familyId);
    return this.get({ ...ctx, role: isSelf && patch.role ? patch.role : ctx.role });
  }

  async removeMember(ctx: FamilyCtx, userId: string) {
    if (userId === ctx.userId) throw Err.validation('Чтобы выйти из семьи, используйте «Выйти из семьи»');
    const target = await this.prisma.familyMember.findFirst({ where: { familyId: ctx.familyId, userId } });
    if (!target) throw Err.notFound('Участник');
    await this.detach(ctx.familyId, userId);
  }

  /** Выход из семьи. Единственный админ при наличии других участников обязан передать роль. */
  async leave(ctx: FamilyCtx) {
    await this.assertCanLeave(ctx);
    const members = await this.prisma.familyMember.count({ where: { familyId: ctx.familyId } });
    if (members === 1) await this.deleteFamily(ctx.familyId);
    else await this.detach(ctx.familyId, ctx.userId);
  }

  async deleteAccount(ctx: Ctx) {
    if (ctx.familyId) {
      const fctx = ctx as FamilyCtx;
      await this.assertCanLeave(fctx);
      const members = await this.prisma.familyMember.count({ where: { familyId: fctx.familyId } });
      if (members === 1) await this.deleteFamily(fctx.familyId);
      else await this.detach(fctx.familyId, ctx.userId);
    }
    // Анонимизируем строку пользователя: на неё ссылаются авторы записей семьи.
    await this.prisma.$transaction([
      this.prisma.session.updateMany({ where: { userId: ctx.userId }, data: { revokedAt: new Date() } }),
      this.prisma.deviceToken.deleteMany({ where: { userId: ctx.userId } }),
      this.prisma.notificationSettings.deleteMany({ where: { userId: ctx.userId } }),
      this.prisma.user.update({ where: { id: ctx.userId }, data: { email: `deleted-${ctx.userId}@deleted.invalid`, deletedAt: new Date() } }),
    ]);
    this.realtime.disconnectUser(ctx.userId);
  }

  private async assertCanLeave(ctx: FamilyCtx) {
    if (ctx.role !== 'admin') return;
    const [admins, members] = await Promise.all([this.adminCount(ctx.familyId), this.prisma.familyMember.count({ where: { familyId: ctx.familyId } })]);
    if (admins <= 1 && members > 1) {
      throw Err.conflict('LAST_ADMIN', 'Вы единственный администратор. Передайте роль другому участнику, прежде чем выйти');
    }
  }

  /** Убирает участника: чистит назначения и его приватные документы. */
  private async detach(familyId: string, userId: string) {
    const now = new Date();
    const [items, occs, privateDocs, sharedDocs] = await Promise.all([
      this.prisma.shoppingItem.findMany({ where: { familyId, assigneeId: userId, deletedAt: null }, select: { id: true } }),
      this.prisma.taskOccurrence.findMany({ where: { familyId, assigneeId: userId, deletedAt: null }, select: { id: true } }),
      this.prisma.document.findMany({ where: { familyId, authorId: userId, access: 'author_only', deletedAt: null }, select: { id: true, objectKey: true } }),
      this.prisma.documentPermission.findMany({ where: { userId, document: { familyId } }, select: { documentId: true } }),
    ]);
    await this.prisma.$transaction([
      this.prisma.shoppingItem.updateMany({ where: { id: { in: items.map((i) => i.id) } }, data: { assigneeId: null, version: { increment: 1 } } }),
      this.prisma.taskOccurrence.updateMany({ where: { id: { in: occs.map((i) => i.id) } }, data: { assigneeId: null, version: { increment: 1 } } }),
      this.prisma.taskSeries.updateMany({ where: { familyId, assigneeId: userId }, data: { assigneeId: null, version: { increment: 1 } } }),
      this.prisma.document.updateMany({ where: { id: { in: privateDocs.map((d) => d.id) } }, data: { deletedAt: now, version: { increment: 1 } } }),
      this.prisma.documentPermission.deleteMany({ where: { userId, document: { familyId } } }),
      this.prisma.familyMember.deleteMany({ where: { familyId, userId } }),
    ]);
    await Promise.all(privateDocs.map((d) => this.storage.delete(d.objectKey).catch(() => undefined)));
    await this.changes.record(familyId, 'shoppingItem', items.map((i) => i.id));
    await this.changes.record(familyId, 'taskOccurrence', occs.map((i) => i.id));
    await this.changes.record(familyId, 'document', [...privateDocs.map((d) => d.id), ...sharedDocs.map((d) => d.documentId)]);
    await this.changes.record(familyId, 'family', familyId);
    this.realtime.disconnectUser(userId);
  }

  private async deleteFamily(familyId: string) {
    const docs = await this.prisma.document.findMany({ where: { familyId }, select: { objectKey: true } });
    await Promise.all(docs.map((d) => this.storage.delete(d.objectKey).catch(() => undefined)));
    await this.prisma.$transaction([
      this.prisma.change.deleteMany({ where: { familyId } }),
      this.prisma.syncOperation.deleteMany({ where: { familyId } }),
      this.prisma.shoppingList.deleteMany({ where: { familyId } }),
      this.prisma.taskSeries.deleteMany({ where: { familyId } }),
      this.prisma.taskOccurrence.deleteMany({ where: { familyId } }),
      this.prisma.document.deleteMany({ where: { familyId } }),
      this.prisma.family.delete({ where: { id: familyId } }),
    ]);
  }
}
