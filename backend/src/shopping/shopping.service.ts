import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ChangesService } from '../changes/changes.service';
import { PlanService } from '../plan/plan.service';
import { PushService } from '../notifications/push.service';
import { FamilyCtx } from '../common/context';
import { Err } from '../common/errors';
import { assertMember, defined, guardExisting, requireText, UpsertResult } from '../common/entity';
import { decodeCursor, encodeCursor } from '../common/pagination';
import { ItemDto, ListDto } from './shopping.dto';
import { ShoppingItem, ShoppingList } from '@prisma/client';

@Injectable()
export class ShoppingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly changes: ChangesService,
    private readonly plan: PlanService,
    private readonly push: PushService,
  ) {}

  private async assertCanHaveActiveList(familyId: string) {
    const plan = await this.plan.get(familyId);
    if (plan.limits.activeLists === null) return;
    const active = await this.prisma.shoppingList.count({ where: { familyId, status: 'active', deletedAt: null } });
    if (active >= plan.limits.activeLists) {
      throw Err.premium('multiple_lists', 'В бесплатном тарифе один активный список. Подключите «рядом Плюс» для нескольких списков');
    }
  }

  async upsertList(ctx: FamilyCtx, id: string, dto: ListDto, baseVersion?: number): Promise<UpsertResult<ShoppingList>> {
    const existing = guardExisting(await this.prisma.shoppingList.findUnique({ where: { id } }), ctx.familyId);
    const status = dto.status;
    if (!existing || (existing.status === 'archived' && status === 'active')) await this.assertCanHaveActiveList(ctx.familyId);
    const archivedAt = status === 'archived' ? new Date() : status === 'active' ? null : undefined;
    let record: ShoppingList;
    if (existing) {
      record = await this.prisma.shoppingList.update({
        where: { id },
        data: { ...defined({ name: dto.name === undefined ? undefined : requireText(dto.name, 'Название'), status, archivedAt }), version: { increment: 1 } },
      });
    } else {
      record = await this.prisma.shoppingList.create({
        data: { id, familyId: ctx.familyId, authorId: ctx.userId, name: dto.name?.trim() || 'Покупки', status: status ?? 'active', archivedAt: archivedAt ?? null },
      });
    }
    await this.changes.record(ctx.familyId, 'shoppingList', id);
    return { record, created: !existing, conflict: !!existing && baseVersion !== undefined && baseVersion < existing.version };
  }

  async removeList(ctx: FamilyCtx, id: string) {
    const list = await this.prisma.shoppingList.findUnique({ where: { id } });
    if (!list || list.familyId !== ctx.familyId) throw Err.notFound('Список');
    if (list.deletedAt) return list;
    const items = await this.prisma.shoppingItem.findMany({ where: { listId: id, deletedAt: null }, select: { id: true } });
    const now = new Date();
    const [record] = await this.prisma.$transaction([
      this.prisma.shoppingList.update({ where: { id }, data: { deletedAt: now, version: { increment: 1 } } }),
      this.prisma.shoppingItem.updateMany({ where: { listId: id, deletedAt: null }, data: { deletedAt: now, version: { increment: 1 } } }),
    ]);
    await this.changes.record(ctx.familyId, 'shoppingItem', items.map((i) => i.id));
    await this.changes.record(ctx.familyId, 'shoppingList', id);
    return record;
  }

  /** «Начать новый список»: завершённые уходят в историю, создаётся новый. Повтор с тем же id безопасен. */
  async startNewList(ctx: FamilyCtx, newId: string, name?: string) {
    const again = await this.prisma.shoppingList.findUnique({ where: { id: newId } });
    if (again) {
      if (again.familyId !== ctx.familyId) throw Err.notFound('Список');
      return { archivedIds: [] as string[], list: again };
    }
    const active = await this.prisma.shoppingList.findMany({ where: { familyId: ctx.familyId, status: 'active', deletedAt: null }, select: { id: true } });
    const now = new Date();
    const [, list] = await this.prisma.$transaction([
      this.prisma.shoppingList.updateMany({ where: { id: { in: active.map((a) => a.id) } }, data: { status: 'archived', archivedAt: now, version: { increment: 1 } } }),
      this.prisma.shoppingList.create({ data: { id: newId, familyId: ctx.familyId, authorId: ctx.userId, name: name?.trim() || 'Покупки' } }),
    ]);
    await this.changes.record(ctx.familyId, 'shoppingList', [...active.map((a) => a.id), newId]);
    return { archivedIds: active.map((a) => a.id), list };
  }

  async upsertItem(ctx: FamilyCtx, id: string, dto: ItemDto, baseVersion?: number): Promise<UpsertResult<ShoppingItem>> {
    const existing = guardExisting(await this.prisma.shoppingItem.findUnique({ where: { id } }), ctx.familyId);
    if (dto.assigneeId) await assertMember(this.prisma, ctx.familyId, dto.assigneeId);
    const purchasedPatch =
      dto.purchased === undefined || (existing && existing.purchased === dto.purchased)
        ? {}
        : dto.purchased
          ? { purchased: true, purchasedById: ctx.userId, purchasedAt: new Date() }
          : { purchased: false, purchasedById: null, purchasedAt: null };
    const fields = defined({
      name: dto.name === undefined ? undefined : requireText(dto.name, 'Название'),
      quantity: dto.quantity,
      unit: dto.unit || undefined,
      category: dto.category || undefined,
      assigneeId: dto.assigneeId,
      note: dto.note === undefined ? undefined : dto.note?.trim() || null,
    });
    let record: ShoppingItem;
    if (existing) {
      if (dto.listId && dto.listId !== existing.listId) throw Err.validation('Товар нельзя переносить между списками');
      record = await this.prisma.shoppingItem.update({ where: { id }, data: { ...fields, ...purchasedPatch, version: { increment: 1 } } });
    } else {
      if (!dto.listId) throw Err.validation('Не указан список', [{ field: 'listId', messages: ['listId обязателен'] }]);
      const list = await this.prisma.shoppingList.findUnique({ where: { id: dto.listId } });
      if (!list || list.familyId !== ctx.familyId || list.deletedAt) throw Err.notFound('Список');
      requireText(dto.name, 'Название');
      record = await this.prisma.shoppingItem.create({
        data: { id, familyId: ctx.familyId, authorId: ctx.userId, listId: dto.listId, ...fields, ...purchasedPatch } as any,
      });
    }
    await this.changes.record(ctx.familyId, 'shoppingItem', id);
    if (dto.assigneeId && dto.assigneeId !== existing?.assigneeId && dto.assigneeId !== ctx.userId) {
      void this.push.notify(dto.assigneeId, 'shopping', 'Покупка для вас', record.name, id);
    }
    return { record, created: !existing, conflict: !!existing && baseVersion !== undefined && baseVersion < existing.version };
  }

  async removeItem(ctx: FamilyCtx, id: string) {
    const item = await this.prisma.shoppingItem.findUnique({ where: { id } });
    if (!item || item.familyId !== ctx.familyId) throw Err.notFound('Товар');
    if (item.deletedAt) return item;
    const record = await this.prisma.shoppingItem.update({ where: { id }, data: { deletedAt: new Date(), version: { increment: 1 } } });
    await this.changes.record(ctx.familyId, 'shoppingItem', id);
    return record;
  }

  async getList(ctx: FamilyCtx, id: string) {
    const list = await this.prisma.shoppingList.findUnique({ where: { id }, include: { items: { where: { deletedAt: null }, orderBy: { createdAt: 'asc' } } } });
    if (!list || list.familyId !== ctx.familyId || list.deletedAt) throw Err.notFound('Список');
    return list;
  }

  async lists(ctx: FamilyCtx, status: 'active' | 'archived' = 'active', cursor?: string, limit = 50) {
    const plan = await this.plan.get(ctx.familyId);
    const cut = decodeCursor(cursor);
    const historyCutoff = status === 'archived' && plan.limits.historyDays ? new Date(Date.now() - plan.limits.historyDays * 86400_000) : null;
    const where = {
      familyId: ctx.familyId,
      status,
      deletedAt: null,
      ...(historyCutoff ? { archivedAt: { gte: historyCutoff } } : {}),
      ...(cut ? { OR: [{ createdAt: { lt: cut.createdAt } }, { createdAt: cut.createdAt, id: { lt: cut.id } }] } : {}),
    };
    const rows = await this.prisma.shoppingList.findMany({
      where,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
      include: { items: { where: { deletedAt: null }, orderBy: { createdAt: 'asc' } } },
    });
    const items = rows.slice(0, limit);
    const hiddenByPlan = historyCutoff
      ? await this.prisma.shoppingList.count({ where: { familyId: ctx.familyId, status: 'archived', deletedAt: null, archivedAt: { lt: historyCutoff } } })
      : 0;
    return {
      items,
      nextCursor: rows.length > limit ? encodeCursor(items[items.length - 1].createdAt, items[items.length - 1].id) : null,
      historyLimitDays: historyCutoff ? plan.limits.historyDays : null,
      hiddenByPlan,
    };
  }
}
