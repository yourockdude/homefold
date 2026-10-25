import { ArgumentsHost, Catch, ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import type { Response } from 'express';

export class AppError extends HttpException {
  constructor(status: number, public readonly code: string, message: string, public readonly details?: unknown) {
    super({ code, message, details }, status);
  }
}

export const Err = {
  notFound: (what = 'Объект') => new AppError(404, 'NOT_FOUND', `${what} не найден`),
  forbidden: (message = 'Недостаточно прав') => new AppError(403, 'FORBIDDEN', message),
  validation: (message: string, details?: unknown) => new AppError(400, 'VALIDATION_ERROR', message, details),
  conflict: (code: string, message: string, details?: unknown) => new AppError(409, code, message, details),
  premium: (feature: string, message: string) => new AppError(402, 'PREMIUM_REQUIRED', message, { feature }),
};

/** Единый формат: { error: { code, message, details? } }. */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('HTTP');

  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();
    let status = 500;
    let code = 'INTERNAL_ERROR';
    let message = 'Внутренняя ошибка сервера';
    let details: unknown;

    if (exception instanceof AppError) {
      status = exception.getStatus();
      code = exception.code;
      message = exception.message;
      details = exception.details;
    } else if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse() as any;
      if (status === 429) {
        code = 'RATE_LIMITED';
        message = 'Слишком много запросов. Попробуйте позже';
      } else if (status === 404) {
        code = 'NOT_FOUND';
        message = 'Не найдено';
      } else if (status === 401) {
        code = 'UNAUTHORIZED';
        message = 'Требуется вход';
      } else if (status === 413) {
        code = 'PAYLOAD_TOO_LARGE';
        message = 'Слишком большой запрос';
      } else {
        code = 'BAD_REQUEST';
        message = typeof body === 'string' ? body : Array.isArray(body?.message) ? 'Некорректные данные' : (body?.message ?? 'Некорректный запрос');
        details = Array.isArray(body?.message) ? body.message : undefined;
      }
    } else {
      // В лог — только тип и сообщение, без тела запроса, токенов и кодов.
      this.logger.error(`Необработанная ошибка: ${(exception as Error)?.name}: ${(exception as Error)?.message}`);
    }
    res.status(status).json({ error: { code, message, ...(details !== undefined ? { details } : {}) } });
  }
}
