import { Global, Injectable, Module } from '@nestjs/common';
import { EventEmitter } from 'node:events';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

export type EntityName = 'shoppingList' | 'shoppingItem' | 'taskSeries' | 'taskOccurrence' | 'checklistItem' | 'document' | 'family';

/** Журнал изменений: единственный источник курсора для /sync/pull и событий WebSocket. */
@Injectable()
export class ChangesService {
  readonly events = new EventEmitter();
  constructor(private readonly prisma: PrismaService) {}

  async record(familyId: string, entity: EntityName, entityIds: string | string[], tx?: Prisma.TransactionClient): Promise<string | null> {
    const ids = Array.isArray(entityIds) ? entityIds : [entityIds];
    if (!ids.length) return null;
    const db = tx ?? this.prisma;
    await db.change.createMany({ data: ids.map((entityId) => ({ familyId, entity, entityId })) });
    const last = await db.change.findFirst({ where: { familyId }, orderBy: { seq: 'desc' }, select: { seq: true } });
    const cursor = String(last?.seq ?? 0);
    if (!tx) this.events.emit('changed', { familyId, cursor });
    return cursor;
  }

  /** Для вызовов внутри транзакции: уведомить подписчиков после коммита. */
  announce(familyId: string, cursor: string | null) {
    if (cursor) this.events.emit('changed', { familyId, cursor });
  }
}

@Global()
@Module({ providers: [ChangesService], exports: [ChangesService] })
export class ChangesModule {}
