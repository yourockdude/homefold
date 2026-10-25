import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { Err } from './errors';

/** Валидация произвольного payload (для sync push) теми же DTO, что и у REST. */
export async function validatePayload<T extends object>(cls: new () => T, payload: unknown): Promise<T> {
  if (typeof payload !== 'object' || payload === null) throw Err.validation('Некорректные данные');
  const inst = plainToInstance(cls, payload, { enableImplicitConversion: false });
  const errors = await validate(inst, { whitelist: true });
  if (errors.length) {
    throw Err.validation('Некорректные данные', errors.map((e) => ({ field: e.property, messages: Object.values(e.constraints ?? {}) })));
  }
  return inst;
}

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
export const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
