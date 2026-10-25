import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentCtx, Ctx, FamilyCtx } from '../common/context';
import { TasksService } from './tasks.service';
import { ChecklistDto, OccurrenceDto, PostponeDto, SeriesDto, TasksQuery } from './tasks.dto';

@ApiTags('tasks')
@ApiBearerAuth()
@Controller('tasks')
export class TasksController {
  constructor(private readonly tasks: TasksService) {}

  @Get()
  list(@CurrentCtx() ctx: Ctx, @Query() q: TasksQuery) {
    return this.tasks.listOccurrences(ctx as FamilyCtx, q);
  }

  @Get('occurrences/:id')
  get(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    return this.tasks.getOccurrence(ctx as FamilyCtx, id);
  }

  /** Создание разового дела или правка ТОЛЬКО этого выполнения. */
  @Put('occurrences/:id')
  async put(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string, @Body() dto: OccurrenceDto) {
    return (await this.tasks.upsertOccurrence(ctx as FamilyCtx, id, dto)).record;
  }

  @Post('occurrences/:id/complete') @HttpCode(200)
  async complete(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    return (await this.tasks.upsertOccurrence(ctx as FamilyCtx, id, { status: 'done' })).record;
  }

  @Post('occurrences/:id/reopen') @HttpCode(200)
  async reopen(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    return (await this.tasks.upsertOccurrence(ctx as FamilyCtx, id, { status: 'open' })).record;
  }

  @Post('occurrences/:id/postpone') @HttpCode(200)
  async postpone(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string, @Body() dto: PostponeDto) {
    return (await this.tasks.upsertOccurrence(ctx as FamilyCtx, id, { date: dto.date, time: dto.time })).record;
  }

  @Delete('occurrences/:id') @HttpCode(204)
  async remove(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    await this.tasks.removeOccurrence(ctx as FamilyCtx, id);
  }

  @Put('checklist/:id')
  async putChecklist(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ChecklistDto) {
    return (await this.tasks.upsertChecklist(ctx as FamilyCtx, id, dto)).record;
  }

  @Delete('checklist/:id') @HttpCode(204)
  async removeChecklist(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    await this.tasks.removeChecklist(ctx as FamilyCtx, id);
  }

  @Get('series')
  series(@CurrentCtx() ctx: Ctx) {
    return this.tasks.listSeries(ctx as FamilyCtx);
  }

  /** Явное изменение всей серии (Premium). Не затрагивает выполненные и правленные вручную выполнения. */
  @Put('series/:id')
  async putSeries(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SeriesDto) {
    return (await this.tasks.upsertSeries(ctx as FamilyCtx, id, dto)).record;
  }

  @Delete('series/:id') @HttpCode(204)
  async removeSeries(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    await this.tasks.removeSeries(ctx as FamilyCtx, id);
  }
}
