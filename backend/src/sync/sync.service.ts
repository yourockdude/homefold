import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ShoppingService } from '../shopping/shopping.service';
import { TasksService } from '../tasks/tasks.service';
import { DocumentsService, isVisibleTo, toDocumentDto } from '../documents/documents.service';
import { FamilyCtx } from '../common/context';
import { AppError } from '../common/errors';
import { validatePayload } from '../common/validate';
import { ItemDto, ListDto } from '../shopping/shopping.dto';
import { ChecklistDto, OccurrenceDto, SeriesDto } from '../tasks/tasks.dto';
import { UpdateDocumentDto } from '../documents/documents.dto';
import { OperationDto, SyncEntity } from './sync.dto';

export interface OpResult {
  opId: string;
  status: 'applied' | 'rejected';
  /** Правка основана на устаревшей версии; применена по правилу last-accepted-write-wins. */
  conflict: boolean;
  /** Актуальная серверная запись (для удалённых — с deletedAt). */
  record: unknown;
  error?: { code: string; message: string };
}

const MAX_PULL = 500;

@Injectable()
export class SyncService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly shopping: ShoppingService,
    private readonly tasks: TasksService,
    private readonly docs: DocumentsService,
  ) {}

  // ───────────── push ─────────────

  async push(ctx: FamilyCtx, operations: OperationDto[]): Promise<{ results: OpResult[] }> {
    const results: OpResult[] = [];
    for (const op of operations) results.push(await this.applyOnce(ctx, op));
    return { results };
  }

  private async applyOnce(ctx: FamilyCtx, op: OperationDto): Promise<OpResult> {
    const prev = await this.prisma.syncOperation.findUnique({ where: { opId: op.opId } });
    if (prev) {
      if (prev.familyId !== ctx.familyId || prev.userId !== ctx.userId) {
        return { opId: op.opId, status: 'rejected', conflict: false, record: null, error: { code: 'OP_ID_TAKEN', message: 'Идентификатор операции уже использован' } };
      }
      return prev.result as unknown as OpResult; // повтор → тот же ответ, без повторного применения
    }
    let result: OpResult;
    try {
      result = await this.apply(ctx, op);
    } catch (e) {
      if (!(e instanceof AppError)) throw e;
      result = {
        opId: op.opId, status: 'rejected', conflict: false,
        record: e.code === 'ENTITY_DELETED' ? await this.current(ctx, op.entity, op.entityId) : null,
        error: { code: e.code, message: e.message },
      };
    }
    await this.prisma.syncOperation
      .create({ data: { opId: op.opId, userId: ctx.userId, familyId: ctx.familyId, result: result as unknown as Prisma.InputJsonValue } })
      .catch((e) => {
        if (e?.code !== 'P2002') throw e; // параллельный дубль — игнорируем
      });
    return result;
  }

  private async apply(ctx: FamilyCtx, op: OperationDto): Promise<OpResult> {
    const { entity, entityId: id, baseVersion } = op;
    if (op.type === 'delete') {
      // Удаление идемпотентно и приоритетнее любых правок.
      switch (entity) {
        case 'shoppingList': await this.shopping.removeList(ctx, id); break;
        case 'shoppingItem': await this.shopping.removeItem(ctx, id); break;
        case 'taskSeries': await this.tasks.removeSeries(ctx, id); break;
        case 'taskOccurrence': await this.tasks.removeOccurrence(ctx, id); break;
        case 'checklistItem': await this.tasks.removeChecklist(ctx, id); break;
        case 'document': await this.docs.remove(ctx, id); break;
      }
      return { opId: op.opId, status: 'applied', conflict: false, record: await this.current(ctx, entity, id) };
    }
    let out: { record: unknown; conflict: boolean };
    switch (entity) {
      case 'shoppingList': out = await this.shopping.upsertList(ctx, id, await validatePayload(ListDto, op.payload ?? {}), baseVersion); break;
      case 'shoppingItem': out = await this.shopping.upsertItem(ctx, id, await validatePayload(ItemDto, op.payload ?? {}), baseVersion); break;
      case 'taskSeries': out = await this.tasks.upsertSeries(ctx, id, await validatePayload(SeriesDto, op.payload ?? {}), baseVersion); break;
      case 'taskOccurrence': out = await this.tasks.upsertOccurrence(ctx, id, await validatePayload(OccurrenceDto, op.payload ?? {}), baseVersion); break;
      case 'checklistItem': out = await this.tasks.upsertChecklist(ctx, id, await validatePayload(ChecklistDto, op.payload ?? {}), baseVersion); break;
      case 'document': out = await this.docs.update(ctx, id, await validatePayload(UpdateDocumentDto, op.payload ?? {}), baseVersion); break;
    }
    return { opId: op.opId, status: 'applied', conflict: out.conflict, record: out.record };
  }

  /** Текущая серверная запись (в т.ч. tombstone) — только если она принадлежит семье и видна пользователю. */
  private async current(ctx: FamilyCtx, entity: SyncEntity, id: string): Promise<unknown> {
    const recs = await this.loadRecords(ctx, entity, [id]);
    const r = recs.get(id);
    return r && 'hidden' in r ? null : (r ?? null);
  }

  // ───────────── pull ─────────────

  async pull(ctx: FamilyCtx, cursor = '0', limit = 200) {
    const take = Math.min(limit, MAX_PULL);
    const rows = await this.prisma.change.findMany({ where: { familyId: ctx.familyId, seq: { gt: BigInt(cursor) } }, orderBy: { seq: 'asc' }, take: take + 1 });
    const page = rows.slice(0, take);
    const hasMore = rows.length > take;
    const nextCursor = page.length ? String(page[page.length - 1].seq) : cursor;

    // Последнее изменение каждой записи на странице; порядок — по seq.
    const last = new Map<string, { entity: string; id: string; seq: bigint }>();
    for (const r of page) {
      last.delete(`${r.entity}:${r.entityId}`);
      last.set(`${r.entity}:${r.entityId}`, { entity: r.entity, id: r.entityId, seq: r.seq });
    }
    const byEntity = new Map<string, string[]>();
    for (const l of last.values()) byEntity.set(l.entity, [...(byEntity.get(l.entity) ?? []), l.id]);
    const loaded = new Map<string, Map<string, any>>();
    for (const [entity, ids] of byEntity) {
      if (entity !== 'family') loaded.set(entity, await this.loadRecords(ctx, entity as SyncEntity, ids));
    }

    const changes = [...last.values()].map(({ entity, id }) => {
      if (entity === 'family') return { entity, id, deleted: false, record: null };
      const rec = loaded.get(entity)?.get(id);
      if (!rec) return { entity, id, deleted: true, record: null }; // запись физически удалена (очистка загрузки и т.п.)
      if ('hidden' in rec) return { entity, id, deleted: true, revoked: true, record: null }; // доступ закрыт — локальную копию удалить
      return { entity, id, deleted: !!rec.deletedAt, record: rec };
    });
    return { changes, cursor: nextCursor, hasMore, serverTime: new Date().toISOString() };
  }

  /** Загружает записи семьи; документы без доступа заменяются маркером { hidden: true }. */
  private async loadRecords(ctx: FamilyCtx, entity: SyncEntity, ids: string[]): Promise<Map<string, any>> {
    const where = { id: { in: ids }, familyId: ctx.familyId };
    let rows: any[];
    switch (entity) {
      case 'shoppingList': rows = await this.prisma.shoppingList.findMany({ where }); break;
      case 'shoppingItem': rows = await this.prisma.shoppingItem.findMany({ where }); break;
      case 'taskSeries': rows = await this.prisma.taskSeries.findMany({ where }); break;
      case 'taskOccurrence': rows = await this.prisma.taskOccurrence.findMany({ where }); break;
      case 'checklistItem': rows = await this.prisma.checklistItem.findMany({ where }); break;
      case 'document':
        rows = (await this.prisma.document.findMany({ where, include: { permissions: true } })).map((d) =>
          isVisibleTo(d, ctx.userId) || (d.deletedAt && d.authorId === ctx.userId) ? toDocumentDto(d) : { id: d.id, hidden: true },
        );
        break;
      default: rows = [];
    }
    return new Map(rows.map((r) => [r.id, r]));
  }
}
