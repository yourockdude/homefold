import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AdminOnly, AllowNoFamily, CurrentCtx, Ctx, FamilyCtx } from '../common/context';
import { FamiliesService } from './families.service';
import { CreateFamilyDto, UpdateFamilyDto, UpdateMemberDto } from './families.dto';

@ApiTags('families')
@ApiBearerAuth()
@Controller()
export class FamiliesController {
  constructor(private readonly families: FamiliesService) {}

  @Get('me')
  @AllowNoFamily()
  async me(@CurrentCtx() ctx: Ctx) {
    return {
      user: { id: ctx.userId },
      family: ctx.familyId ? await this.families.get(ctx as FamilyCtx) : null,
    };
  }

  @Post('families') @AllowNoFamily()
  create(@CurrentCtx() ctx: Ctx, @Body() dto: CreateFamilyDto) {
    return this.families.create(ctx, dto.name, dto.displayName);
  }

  @Get('families/me')
  get(@CurrentCtx() ctx: Ctx) {
    return this.families.get(ctx as FamilyCtx);
  }

  @Patch('families/me') @AdminOnly()
  rename(@CurrentCtx() ctx: Ctx, @Body() dto: UpdateFamilyDto) {
    return this.families.rename(ctx as FamilyCtx, dto.name);
  }

  @Patch('families/me/members/:userId')
  updateMember(@CurrentCtx() ctx: Ctx, @Param('userId', ParseUUIDPipe) userId: string, @Body() dto: UpdateMemberDto) {
    return this.families.updateMember(ctx as FamilyCtx, userId, dto);
  }

  @Delete('families/me/members/:userId') @AdminOnly() @HttpCode(204)
  removeMember(@CurrentCtx() ctx: Ctx, @Param('userId', ParseUUIDPipe) userId: string) {
    return this.families.removeMember(ctx as FamilyCtx, userId);
  }

  @Post('families/me/leave') @HttpCode(204)
  leave(@CurrentCtx() ctx: Ctx) {
    return this.families.leave(ctx as FamilyCtx);
  }

  @Delete('account') @AllowNoFamily() @HttpCode(204)
  deleteAccount(@CurrentCtx() ctx: Ctx) {
    return this.families.deleteAccount(ctx);
  }
}
