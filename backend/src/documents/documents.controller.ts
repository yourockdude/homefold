import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentCtx, Ctx, FamilyCtx } from '../common/context';
import { DocumentsService } from './documents.service';
import { CreateDocumentDto, DocumentsQuery, UpdateDocumentDto } from './documents.dto';

@ApiTags('documents')
@ApiBearerAuth()
@Controller('documents')
export class DocumentsController {
  constructor(private readonly docs: DocumentsService) {}

  @Get()
  list(@CurrentCtx() ctx: Ctx, @Query() q: DocumentsQuery) {
    return this.docs.list(ctx as FamilyCtx, q);
  }

  @Get('usage')
  usage(@CurrentCtx() ctx: Ctx) {
    return this.docs.usage(ctx as FamilyCtx);
  }

  /** Шаг 1: метаданные + короткоживущая ссылка на прямую загрузку в приватное хранилище. Идемпотентно по id. */
  @Post()
  create(@CurrentCtx() ctx: Ctx, @Body() dto: CreateDocumentDto) {
    return this.docs.create(ctx as FamilyCtx, dto);
  }

  @Get(':id')
  get(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    return this.docs.get(ctx as FamilyCtx, id);
  }

  @Post(':id/upload-url') @HttpCode(200)
  uploadUrl(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    return this.docs.uploadUrl(ctx as FamilyCtx, id);
  }

  /** Шаг 3: сервер проверяет размер, тип и завершённость загрузки. */
  @Post(':id/confirm') @HttpCode(200)
  confirm(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    return this.docs.confirm(ctx as FamilyCtx, id);
  }

  @Get(':id/download-url')
  downloadUrl(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    return this.docs.downloadUrl(ctx as FamilyCtx, id);
  }

  @Patch(':id')
  async update(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateDocumentDto) {
    return (await this.docs.update(ctx as FamilyCtx, id, dto)).record;
  }

  @Delete(':id') @HttpCode(204)
  async remove(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    await this.docs.remove(ctx as FamilyCtx, id);
  }
}
