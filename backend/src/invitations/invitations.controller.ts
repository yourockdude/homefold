import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { IsString, MaxLength, MinLength } from 'class-validator';
import { Transform } from 'class-transformer';
import { AdminOnly, AllowNoFamily, CurrentCtx, Ctx, FamilyCtx, Public } from '../common/context';
import { perMinute } from '../common/throttle';
import { InvitationsService } from './invitations.service';

class AcceptDto {
  @ApiProperty() @IsString() @MinLength(10) @MaxLength(100) token: string;
  @ApiProperty() @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value)) @IsString() @MinLength(1, { message: 'Введите ваше имя' }) @MaxLength(40)
  displayName: string;
}

@ApiTags('invitations')
@Controller('invitations')
export class InvitationsController {
  constructor(private readonly invitations: InvitationsService) {}

  @ApiBearerAuth() @AdminOnly() @Post()
  create(@CurrentCtx() ctx: Ctx) {
    return this.invitations.create(ctx as FamilyCtx);
  }

  @ApiBearerAuth() @AdminOnly() @Get()
  list(@CurrentCtx() ctx: Ctx) {
    return this.invitations.list(ctx as FamilyCtx);
  }

  @ApiBearerAuth() @AdminOnly() @Delete(':id') @HttpCode(204)
  revoke(@CurrentCtx() ctx: Ctx, @Param('id', ParseUUIDPipe) id: string) {
    return this.invitations.revoke(ctx as FamilyCtx, id);
  }

  @Public() @Throttle({ default: { limit: perMinute(20), ttl: 60_000 } }) @Get('preview')
  preview(@Query('token') token: string) {
    return this.invitations.preview(token ?? '');
  }

  @ApiBearerAuth() @AllowNoFamily() @Post('accept') @HttpCode(200)
  accept(@CurrentCtx() ctx: Ctx, @Body() dto: AcceptDto) {
    return this.invitations.accept(ctx, dto.token, dto.displayName);
  }
}
