import { Injectable } from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';
import { ChangesService } from '../changes/changes.service';
import { PlanService } from '../plan/plan.service';
import { Ctx, FamilyCtx } from '../common/context';
import { AppError, Err } from '../common/errors';
import { loadConfig } from '../common/config';

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');
export const INVITE_TTL_DAYS = 7;

@Injectable()
export class InvitationsService {
  constructor(private readonly prisma: PrismaService, private readonly changes: ChangesService, private readonly plan: PlanService) {}

  private async assertRoom(familyId: string) {
    const [plan, members, pending] = await Promise.all([
      this.plan.get(familyId),
      this.prisma.familyMember.count({ where: { familyId } }),
      this.prisma.invitation.count({ where: { familyId, revokedAt: null, usedAt: null, expiresAt: { gt: new Date() } } }),
    ]);
    return { plan, members, pending };
  }

  async create(ctx: FamilyCtx) {
    const { plan, members, pending } = await this.assertRoom(ctx.familyId);
    if (members + pending >= plan.limits.members) {
      throw Err.premium('members', plan.premium ? `В семье может быть не более ${plan.limits.members} участников` : `В бесплатном тарифе — до ${plan.limits.members} участников. Подключите «рядом Плюс»`);
    }
    const token = randomBytes(24).toString('base64url');
    const inv = await this.prisma.invitation.create({
      data: { familyId: ctx.familyId, invitedById: ctx.userId, tokenHash: sha256(token), expiresAt: new Date(Date.now() + INVITE_TTL_DAYS * 86400_000) },
    });
    // Токен показывается один раз — в БД хранится только хеш.
    return { id: inv.id, token, url: `${loadConfig().inviteBaseUrl}/${token}`, expiresAt: inv.expiresAt };
  }

  async list(ctx: FamilyCtx) {
    const rows = await this.prisma.invitation.findMany({
      where: { familyId: ctx.familyId, revokedAt: null, usedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });
    return { items: rows.map((r) => ({ id: r.id, expiresAt: r.expiresAt, createdAt: r.createdAt, invitedById: r.invitedById })) };
  }

  async revoke(ctx: FamilyCtx, id: string) {
    const r = await this.prisma.invitation.updateMany({ where: { id, familyId: ctx.familyId, revokedAt: null }, data: { revokedAt: new Date() } });
    if (r.count === 0) throw Err.notFound('Приглашение');
  }

  private async findValid(token: string) {
    const inv = await this.prisma.invitation.findUnique({ where: { tokenHash: sha256(token) }, include: { family: true } });
    if (!inv || inv.revokedAt || inv.usedAt || inv.expiresAt < new Date()) {
      throw new AppError(410, 'INVITATION_INVALID', 'Приглашение недействительно: срок истёк или оно отозвано');
    }
    return inv;
  }

  /** Публичный предпросмотр: только название семьи и имя пригласившего. */
  async preview(token: string) {
    const inv = await this.findValid(token);
    const inviter = await this.prisma.familyMember.findFirst({ where: { familyId: inv.familyId, userId: inv.invitedById } });
    return { familyName: inv.family.name, invitedBy: inviter?.displayName ?? 'Участник семьи', expiresAt: inv.expiresAt };
  }

  async accept(ctx: Ctx, token: string, displayName: string) {
    if (ctx.familyId) throw Err.conflict('ALREADY_IN_FAMILY', 'Вы уже состоите в семье. Сначала выйдите из неё');
    const inv = await this.findValid(token);
    const { plan, members } = await this.assertRoom(inv.familyId);
    if (members >= plan.limits.members) throw Err.premium('members', 'В этой семье нет свободных мест');

    const colorsUsed = await this.prisma.familyMember.findMany({ where: { familyId: inv.familyId }, select: { color: true } });
    const color = [...Array(8).keys()].find((c) => !colorsUsed.some((u) => u.color === c)) ?? members % 8;
    await this.prisma.$transaction(async (tx) => {
      // Одноразовость: условный update защищает от гонки двух принятий.
      const used = await tx.invitation.updateMany({ where: { id: inv.id, usedAt: null, revokedAt: null }, data: { usedAt: new Date(), usedById: ctx.userId } });
      if (used.count === 0) throw new AppError(410, 'INVITATION_INVALID', 'Приглашение уже использовано или отозвано');
      await tx.familyMember.create({ data: { familyId: inv.familyId, userId: ctx.userId, role: 'member', displayName, color } });
      await tx.notificationSettings.upsert({ where: { userId: ctx.userId }, update: {}, create: { userId: ctx.userId } });
    });
    await this.changes.record(inv.familyId, 'family', inv.familyId);
    return { familyId: inv.familyId };
  }
}
