import { PrismaService } from '../prisma/prisma.service';
import { Err } from './errors';

export interface UpsertResult<T> {
  record: T;
  created: boolean;
  /** baseVersion клиента был старее серверной версии: запись принята по правилу last-accepted-write-wins. */
  conflict: boolean;
}

export interface SyncBase {
  id: string;
  familyId: string;
  version: number;
  deletedAt: Date | null;
}

/** Чужая семья неотличима от «не найдено»; удалённая запись не воскресает правкой. */
export function guardExisting<T extends SyncBase>(existing: T | null, familyId: string): T | null {
  if (!existing) return null;
  if (existing.familyId !== familyId) throw Err.notFound();
  if (existing.deletedAt) throw Err.conflict('ENTITY_DELETED', 'Запись уже удалена');
  return existing;
}

export async function assertMember(prisma: PrismaService, familyId: string, userId: string | null | undefined) {
  if (!userId) return;
  const m = await prisma.familyMember.findFirst({ where: { familyId, userId }, select: { id: true } });
  if (!m) throw Err.validation('Ответственный должен быть участником семьи');
}

export function requireText(v: string | null | undefined, label: string): string {
  const t = v?.trim();
  if (!t) throw Err.validation(`${label} обязательно`, [{ field: label, messages: [`${label} обязательно`] }]);
  return t;
}

/** Убирает undefined, чтобы Prisma не затирала поля. */
export function defined<T extends object>(o: T): Partial<T> {
  return Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined)) as Partial<T>;
}
