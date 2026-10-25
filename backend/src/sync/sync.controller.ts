import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentCtx, Ctx, FamilyCtx } from '../common/context';
import { PullQuery, PushDto } from './sync.dto';
import { SyncService } from './sync.service';

@ApiTags('sync')
@ApiBearerAuth()
@Controller('sync')
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  /** Пачка операций из очереди клиента. Повтор с тем же opId возвращает прежний результат. */
  @Post('push') @HttpCode(200)
  push(@CurrentCtx() ctx: Ctx, @Body() dto: PushDto) {
    return this.sync.push(ctx as FamilyCtx, dto.operations);
  }

  /** Изменения семьи после курсора (включая tombstone). Вызывать и после реконнекта WebSocket. */
  @Get('pull')
  pull(@CurrentCtx() ctx: Ctx, @Query() q: PullQuery) {
    return this.sync.pull(ctx as FamilyCtx, q.cursor, q.limit);
  }
}
