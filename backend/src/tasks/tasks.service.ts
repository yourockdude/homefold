import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { randomUUID } from 'node:crypto';
import { ChecklistItem, Prisma, TaskOccurrence, TaskSeries } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ChangesService } from '../changes/changes.service';
import { PlanService } from '../plan/plan.service';
import { PushService } from '../notifications/push.service';
import { FamilyCtx } from '../common/context';
import { Err } from '../common/errors';
import { assertMember, defined, guardExisting, requireText, UpsertResult } from '../common/entity';
import { addDays, isValidDate, occurrenceDates, todayUtc } from '../common/dates';
import { ChecklistDto, OccurrenceDto, SeriesDto } from './tasks.dto';

export const MATERIALIZE_DAYS = 60;

const SHARED_FIELDS = ['title', 'assigneeId', 'time', 'timezone', 'place', 'note', 'reminderMinutes'] as const;

@Injectable()
export class TasksService {
  private readonly logger = new Logger(TasksService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly changes: ChangesService,
    private readonly plan: PlanService,
    private readonly push: PushService,
  ) {}

  // ───────────── Отдельные выполнения (и разовые дела) ─────────────

  async upsertOccurrence(ctx: FamilyCtx, id: string, dto: OccurrenceDto, baseVersion?: number): Promise<UpsertResult<TaskOccurrence>> {
    const existing = guardExisting(await this.prisma.taskOccurrence.findUnique({ where: { id } }), ctx.familyId);
    if (dto.assigneeId) await assertMember(this.prisma, ctx.familyId, dto.assigneeId);
    if (dto.date && !isValidDate(dto.date)) throw Err.validation('Некорректная дата');

    const fields = defined({
      title: dto.title === undefined ? undefined : requireText(dto.title, 'Название'),
      assigneeId: dto.assigneeId,
      date: dto.date,
      time: dto.time,
      timezone: dto.timezone,
      place: dto.place === undefined ? undefined : dto.place?.trim() || null,
      note: dto.note === undefined ? undefined : dto.note?.trim() || null,
      reminderMinutes: dto.reminderMinutes,
    });
    const statusPatch =
      dto.status === undefined || existing?.status === dto.status
        ? {}
        : dto.status === 'done'
          ? { status: 'done' as const, completedById: ctx.userId, completedAt: new Date() }
          : { status: 'open' as const, completedById: null, completedAt: null };

    let record: TaskOccurrence;
    if (existing) {
      // Правка выполнения серии касается только его: помечаем, чтобы правка серии его не перезаписала.
      const personal = existing.seriesId && Object.keys(fields).length > 0;
      record = await this.prisma.taskOccurrence.update({
        where: { id },
        data: { ...fields, ...statusPatch, ...(personal ? { overridden: true } : {}), version: { increment: 1 } },
      });
    } else {
      requireText(dto.title, 'Название');
      if (!dto.date) throw Err.validation('Укажите дату', [{ field: 'date', messages: ['Дата обязательна'] }]);
      record = await this.prisma.taskOccurrence.create({ data: { id, familyId: ctx.familyId, authorId: ctx.userId, ...fields, ...statusPatch } as any });
    }
    await this.changes.record(ctx.familyId, 'taskOccurrence', id);
    if (dto.assigneeId && dto.assigneeId !== existing?.assigneeId && dto.assigneeId !== ctx.userId) {
      void this.push.notify(dto.assigneeId, 'task', 'Вам назначено дело', record.title, id);
    }
    return { record, created: !existing, conflict: !!existing && baseVersion !== undefined && baseVersion < existing.version };
  }

  async removeOccurrence(ctx: FamilyCtx, id: string) {
    const occ = await this.prisma.taskOccurrence.findUnique({ where: { id } });
    if (!occ || occ.familyId !== ctx.familyId) throw Err.notFound('Дело');
    if (occ.deletedAt) return occ;
    const now = new Date();
    const items = await this.prisma.checklistItem.findMany({ where: { occurrenceId: id, deletedAt: null }, select: { id: true } });
    const [record] = await this.prisma.$transaction([
      // overridden=true: удалённое пользователем выполнение не «оживает» при пересборке серии.
      this.prisma.taskOccurrence.update({ where: { id }, data: { deletedAt: now, overridden: true, version: { increment: 1 } } }),
      this.prisma.checklistItem.updateMany({ where: { occurrenceId: id, deletedAt: null }, data: { deletedAt: now, version: { increment: 1 } } }),
    ]);
    await this.changes.record(ctx.familyId, 'checklistItem', items.map((i) => i.id));
    await this.changes.record(ctx.familyId, 'taskOccurrence', id);
    return record;
  }

  // ───────────── Чек-лист ─────────────

  async upsertChecklist(ctx: FamilyCtx, id: string, dto: ChecklistDto, baseVersion?: number): Promise<UpsertResult<ChecklistItem>> {
    const existing = guardExisting(await this.prisma.checklistItem.findUnique({ where: { id } }), ctx.familyId);
    let record: ChecklistItem;
    if (existing) {
      if (dto.occurrenceId && dto.occurrenceId !== existing.occurrenceId) throw Err.validation('Пункт нельзя переносить между делами');
      record = await this.prisma.checklistItem.update({
        where: { id },
        data: { ...defined({ title: dto.title === undefined ? undefined : requireText(dto.title, 'Название пункта'), done: dto.done, position: dto.position }), version: { increment: 1 } },
      });
    } else {
      if (!dto.occurrenceId) throw Err.validation('Не указано дело', [{ field: 'occurrenceId', messages: ['occurrenceId обязателен'] }]);
      const occ = await this.prisma.taskOccurrence.findUnique({ where: { id: dto.occurrenceId } });
      if (!occ || occ.familyId !== ctx.familyId || occ.deletedAt) throw Err.notFound('Дело');
      record = await this.prisma.checklistItem.create({
        data: { id, familyId: ctx.familyId, authorId: ctx.userId, occurrenceId: dto.occurrenceId, title: requireText(dto.title, 'Название пункта'), done: dto.done ?? false, position: dto.position ?? 0 },
      });
    }
    await this.changes.record(ctx.familyId, 'checklistItem', id);
    return { record, created: !existing, conflict: !!existing && baseVersion !== undefined && baseVersion < existing.version };
  }

  async removeChecklist(ctx: FamilyCtx, id: string) {
    const item = await this.prisma.checklistItem.findUnique({ where: { id } });
    if (!item || item.familyId !== ctx.familyId) throw Err.notFound('Пункт');
    if (item.deletedAt) return item;
    const record = await this.prisma.checklistItem.update({ where: { id }, data: { deletedAt: new Date(), version: { increment: 1 } } });
    await this.changes.record(ctx.familyId, 'checklistItem', id);
    return record;
  }

  // ───────────── Серии (шаблон) ─────────────

  /** Явное изменение серии: затрагивает будущие невыполненные и не правленные вручную выполнения. */
  async upsertSeries(ctx: FamilyCtx, id: string, dto: SeriesDto, baseVersion?: number): Promise<UpsertResult<TaskSeries>> {
    const existing = guardExisting(await this.prisma.taskSeries.findUnique({ where: { id } }), ctx.familyId);
    await this.plan.requireRecurring(ctx.familyId);
    if (dto.assigneeId) await assertMember(this.prisma, ctx.familyId, dto.assigneeId);
    if (dto.startDate && !isValidDate(dto.startDate)) throw Err.validation('Некорректная дата');
    const fields = defined({
      title: dto.title === undefined ? undefined : requireText(dto.title, 'Название'),
      assigneeId: dto.assigneeId,
      startDate: dto.startDate,
      time: dto.time,
      timezone: dto.timezone,
      place: dto.place === undefined ? undefined : dto.place?.trim() || null,
      note: dto.note === undefined ? undefined : dto.note?.trim() || null,
      repeat: dto.repeat,
      reminderMinutes: dto.reminderMinutes,
      checklist: dto.checklist?.map((t) => t.trim()).filter(Boolean),
    });
    let record: TaskSeries;
    if (existing) {
      record = await this.prisma.taskSeries.update({ where: { id }, data: { ...fields, version: { increment: 1 } } as Prisma.TaskSeriesUpdateInput });
    } else {
      requireText(dto.title, 'Название');
      if (!dto.startDate) throw Err.validation('Укажите дату начала', [{ field: 'startDate', messages: ['Дата начала обязательна'] }]);
      record = await this.prisma.taskSeries.create({ data: { id, familyId: ctx.familyId, authorId: ctx.userId, repeat: 'daily', ...fields } as Prisma.TaskSeriesUncheckedCreateInput });
    }
    await this.changes.record(ctx.familyId, 'taskSeries', id);
    await this.materialize(record.id);
    if (dto.assigneeId && dto.assigneeId !== existing?.assigneeId && dto.assigneeId !== ctx.userId) {
      void this.push.notify(dto.assigneeId, 'task', 'Вам назначено повторяющееся дело', record.title, id);
    }
    return { record, created: !existing, conflict: !!existing && baseVersion !== undefined && baseVersion < existing.version };
  }

  async removeSeries(ctx: FamilyCtx, id: string) {
    const series = await this.prisma.taskSeries.findUnique({ where: { id } });
    if (!series || series.familyId !== ctx.familyId) throw Err.notFound('Серия');
    if (series.deletedAt) return series;
    const from = addDays(todayUtc(), -1);
    const future = await this.prisma.taskOccurrence.findMany({ where: { seriesId: id, deletedAt: null, status: 'open', date: { gte: from } }, select: { id: true } });
    const now = new Date();
    const [record] = await this.prisma.$transaction([
      this.prisma.taskSeries.update({ where: { id }, data: { deletedAt: now, version: { increment: 1 } } }),
      // Выполненные и прошлые остаются — это история.
      this.prisma.taskOccurrence.updateMany({ where: { id: { in: future.map((f) => f.id) } }, data: { deletedAt: now, overridden: true, version: { increment: 1 } } }),
    ]);
    await this.changes.record(ctx.familyId, 'taskOccurrence', future.map((f) => f.id));
    await this.changes.record(ctx.familyId, 'taskSeries', id);
    return record;
  }

  /**
   * Приводит материализованные выполнения серии в соответствие с шаблоном на окно MATERIALIZE_DAYS вперёд.
   * Для семей без Premium повторения приостановлены: ничего не создаётся и не удаляется.
   */
  async materialize(seriesId: string): Promise<number> {
    const series = await this.prisma.taskSeries.findUnique({ where: { id: seriesId } });
    if (!series || series.deletedAt) return 0;
    if (!(await this.plan.get(series.familyId)).limits.recurringTasks) return 0;

    const today = addDays(todayUtc(), -1); // запас на часовые пояса западнее UTC
    const to = addDays(todayUtc(), MATERIALIZE_DAYS);
    const desired = new Set(occurrenceDates(series.repeat, series.startDate, today, to));
    const existing = await this.prisma.taskOccurrence.findMany({ where: { seriesId }, include: { checklist: { select: { id: true } } } });
    const byDate = new Map(existing.map((o) => [o.originalDate, o]));
    const touched: string[] = [];
    const template = (series.checklist as string[]) ?? [];
    const shared = {
      title: series.title,
      assigneeId: series.assigneeId,
      time: series.time,
      timezone: series.timezone,
      place: series.place,
      note: series.note,
      reminderMinutes: series.reminderMinutes,
    };

    for (const d of desired) {
      const ex = byDate.get(d);
      if (!ex) {
        const occId = randomUUID();
        await this.prisma.taskOccurrence.create({
          data: {
            id: occId, familyId: series.familyId, authorId: series.authorId, seriesId, originalDate: d, date: d, ...shared,
            checklist: { create: template.map((title, position) => ({ id: randomUUID(), familyId: series.familyId, authorId: series.authorId, title, position })) },
          },
        });
        touched.push(occId);
      } else if (!ex.overridden && ex.status === 'open') {
        const same = !ex.deletedAt && SHARED_FIELDS.every((f) => ex[f] === shared[f]);
        if (same) continue;
        await this.prisma.taskOccurrence.update({ where: { id: ex.id }, data: { ...shared, date: d, deletedAt: null, version: { increment: 1 } } });
        touched.push(ex.id);
      }
    }
    for (const ex of existing) {
      const stale = ex.originalDate && !desired.has(ex.originalDate) && ex.originalDate >= today;
      if (stale && !ex.deletedAt && !ex.overridden && ex.status === 'open') {
        await this.prisma.taskOccurrence.update({ where: { id: ex.id }, data: { deletedAt: new Date(), version: { increment: 1 } } });
        touched.push(ex.id);
      }
    }
    if (touched.length) {
      await this.changes.record(series.familyId, 'taskOccurrence', touched);
      const newItems = await this.prisma.checklistItem.findMany({ where: { occurrenceId: { in: touched } }, select: { id: true } });
      await this.changes.record(series.familyId, 'checklistItem', newItems.map((i) => i.id));
    }
    return touched.length;
  }

  /** Ежедневное продление окна (и при возврате Premium). */
  @Cron('0 3 * * *')
  async materializeAll(familyId?: string) {
    const series = await this.prisma.taskSeries.findMany({ where: { deletedAt: null, ...(familyId ? { familyId } : {}) }, select: { id: true } });
    for (const s of series) {
      try {
        await this.materialize(s.id);
      } catch (e) {
        this.logger.warn(`Материализация серии не удалась: ${(e as Error).message}`);
      }
    }
  }

  // ───────────── Чтение ─────────────

  async listOccurrences(ctx: FamilyCtx, q: { from?: string; to?: string; assigneeId?: string; status?: 'open' | 'done'; today?: string; cursor?: string; limit?: number }) {
    const plan = await this.plan.get(ctx.familyId);
    const today = q.today ?? todayUtc();
    const limit = q.limit ?? 100;
    const histFrom = plan.limits.historyDays ? addDays(todayUtc(), -plan.limits.historyDays) : null;
    const from = histFrom && (!q.from || q.from < histFrom) ? histFrom : q.from;
    let cur: { date: string; id: string } | null = null;
    if (q.cursor) {
      const [date, id] = Buffer.from(q.cursor, 'base64url').toString().split('|');
      if (date && id) cur = { date, id };
    }
    const where: Prisma.TaskOccurrenceWhereInput = {
      familyId: ctx.familyId,
      deletedAt: null,
      ...(from || q.to ? { date: { ...(from ? { gte: from } : {}), ...(q.to ? { lte: q.to } : {}) } } : {}),
      ...(q.assigneeId ? { assigneeId: q.assigneeId } : {}),
      ...(q.status ? { status: q.status } : {}),
      ...(cur ? { OR: [{ date: { gt: cur.date } }, { date: cur.date, id: { gt: cur.id } }] } : {}),
    };
    const rows = await this.prisma.taskOccurrence.findMany({
      where,
      orderBy: [{ date: 'asc' }, { id: 'asc' }],
      take: limit + 1,
      include: { checklist: { where: { deletedAt: null }, orderBy: { position: 'asc' } } },
    });
    const items = rows.slice(0, limit).map((o) => ({ ...o, overdue: o.status === 'open' && o.date < today }));
    const last = items[items.length - 1];
    const hiddenByPlan = histFrom ? await this.prisma.taskOccurrence.count({ where: { familyId: ctx.familyId, deletedAt: null, date: { lt: histFrom } } }) : 0;
    return {
      items,
      nextCursor: rows.length > limit && last ? Buffer.from(`${last.date}|${last.id}`).toString('base64url') : null,
      historyLimitDays: histFrom ? plan.limits.historyDays : null,
      hiddenByPlan,
    };
  }

  async getOccurrence(ctx: FamilyCtx, id: string) {
    const occ = await this.prisma.taskOccurrence.findUnique({ where: { id }, include: { checklist: { where: { deletedAt: null }, orderBy: { position: 'asc' } } } });
    if (!occ || occ.familyId !== ctx.familyId || occ.deletedAt) throw Err.notFound('Дело');
    return occ;
  }

  async listSeries(ctx: FamilyCtx) {
    return { items: await this.prisma.taskSeries.findMany({ where: { familyId: ctx.familyId, deletedAt: null }, orderBy: { createdAt: 'asc' } }) };
  }
}
