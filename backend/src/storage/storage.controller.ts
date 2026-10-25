import { Controller, Get, Param, Put, Req, Res } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Request, Response } from 'express';
import { Public } from '../common/context';
import { AppError } from '../common/errors';
import { LocalStorage, Storage } from './storage.service';
import { MAX_FILE_BYTES } from '../plan/plan.service';

/** Только для STORAGE_DRIVER=local. В production файлы идут напрямую в S3 по presigned URL. */
@ApiExcludeController()
@Public()
@Controller('storage')
export class StorageController {
  constructor(private readonly storage: Storage) {}

  private local(): LocalStorage {
    if (!(this.storage instanceof LocalStorage)) throw new AppError(404, 'NOT_FOUND', 'Не найдено');
    return this.storage;
  }

  @Put('upload/:token')
  async upload(@Param('token') token: string, @Req() req: Request, @Res() res: Response) {
    const local = this.local();
    let claims;
    try {
      claims = await local.verifyToken(token, 'put');
    } catch {
      throw new AppError(403, 'LINK_EXPIRED', 'Ссылка для загрузки истекла');
    }
    const body = req.body;
    if (!Buffer.isBuffer(body) || body.length === 0) throw new AppError(400, 'EMPTY_BODY', 'Пустой файл');
    if (body.length > MAX_FILE_BYTES) throw new AppError(413, 'PAYLOAD_TOO_LARGE', 'Файл больше 25 МБ');
    await local.write(claims.key, body);
    res.status(200).end();
  }

  @Get('download/:token')
  async download(@Param('token') token: string, @Res() res: Response) {
    const local = this.local();
    let claims;
    try {
      claims = await local.verifyToken(token, 'get');
    } catch {
      throw new AppError(403, 'LINK_EXPIRED', 'Ссылка истекла');
    }
    const data = await local.read(claims.key).catch(() => null);
    if (!data) throw new AppError(404, 'NOT_FOUND', 'Файл не найден');
    res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(claims.fn ?? 'file')}`);
    res.setHeader('Cache-Control', 'private, no-store');
    res.send(data);
  }
}
