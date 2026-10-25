import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentCtx, Ctx, FamilyCtx } from '../common/context';
import { ShoppingService } from './shopping.service';
import { ItemDto, ListDto, ListsQuery, NewListDto } from './shopping.dto';

@ApiTags('shopping')
@ApiBearerAuth()
@Controller('shopping')
export class ShoppingController {
  constructor(private readonly shopping: ShoppingService) {}

  @Get('lists')
  lists(@CurrentCtx() ctx: Ctx, @Query() q: ListsQuery) {
    return this.shopping.lists(ctx as FamilyCtx, q.status, q.cursor, q.limit);
  }

  @Get('lists/:id')
  list(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    return this.shopping.getList(ctx as FamilyCtx, id);
  }

  @Put('lists/:id')
  async putList(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ListDto) {
    return (await this.shopping.upsertList(ctx as FamilyCtx, id, dto)).record;
  }

  @Delete('lists/:id') @HttpCode(204)
  async deleteList(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    await this.shopping.removeList(ctx as FamilyCtx, id);
  }

  @Post('lists/new') @HttpCode(200)
  startNew(@CurrentCtx() ctx: Ctx, @Body() dto: NewListDto) {
    return this.shopping.startNewList(ctx as FamilyCtx, dto.id, dto.name);
  }

  @Put('items/:id')
  async putItem(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ItemDto) {
    return (await this.shopping.upsertItem(ctx as FamilyCtx, id, dto)).record;
  }

  @Delete('items/:id') @HttpCode(204)
  async deleteItem(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    await this.shopping.removeItem(ctx as FamilyCtx, id);
  }
}
