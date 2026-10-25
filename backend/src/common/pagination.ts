import { IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class PageQuery {
  @IsOptional() @IsString() cursor?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(200) limit?: number;
}

export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

/** Курсорная пагинация по (createdAt, id) — курсор непрозрачный base64. */
export function encodeCursor(createdAt: Date, id: string): string {
  return Buffer.from(`${createdAt.toISOString()}|${id}`).toString('base64url');
}
export function decodeCursor(cursor?: string): { createdAt: Date; id: string } | null {
  if (!cursor) return null;
  try {
    const [d, id] = Buffer.from(cursor, 'base64url').toString().split('|');
    const createdAt = new Date(d);
    return Number.isNaN(createdAt.getTime()) || !id ? null : { createdAt, id };
  } catch {
    return null;
  }
}
