import { Body, Controller, Delete, Get, HttpCode, Param, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { IsBoolean, IsIn, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { CurrentCtx, Ctx } from '../common/context';
import { PrismaService } from '../prisma/prisma.service';

class DeviceDto {
  @ApiProperty() @IsString() @MinLength(16) @MaxLength(200) @Matches(/^[0-9a-fA-F]+$/, { message: 'Токен APNs — hex-строка' })
  token: string;
  @ApiPropertyOptional({ enum: ['sandbox', 'production'] }) @IsOptional() @IsIn(['sandbox', 'production'])
  environment?: string;
}

class SettingsDto {
  @ApiPropertyOptional() @IsOptional() @IsBoolean() taskReminders?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() shoppingPush?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() quietHoursEnabled?: boolean;
  @ApiPropertyOptional({ example: '22:00' }) @IsOptional() @Matches(/^([01]\d|2[0-3]):[0-5]\d$/, { message: 'Формат HH:mm' }) quietStart?: string;
  @ApiPropertyOptional({ example: '08:00' }) @IsOptional() @Matches(/^([01]\d|2[0-3]):[0-5]\d$/, { message: 'Формат HH:mm' }) quietEnd?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(64) timezone?: string;
  @ApiPropertyOptional({ description: 'Face ID для документов; хранится для синхронизации настройки, защита действует на устройстве' }) @IsOptional() @IsBoolean()
  documentsProtection?: boolean;
}

@ApiTags('notifications')
@ApiBearerAuth()
@Controller()
export class NotificationsController {
  constructor(private readonly prisma: PrismaService) {}

  @Put('devices') @HttpCode(204)
  async registerDevice(@CurrentCtx() ctx: Ctx, @Body() dto: DeviceDto) {
    const token = dto.token.toLowerCase();
    // Токен принадлежит одному пользователю: при смене аккаунта на устройстве перепривязываем.
    await this.prisma.deviceToken.upsert({
      where: { token },
      update: { userId: ctx.userId, environment: dto.environment ?? 'production' },
      create: { token, userId: ctx.userId, environment: dto.environment ?? 'production' },
    });
  }

  @Delete('devices/:token') @HttpCode(204)
  async removeDevice(@CurrentCtx() ctx: Ctx, @Param('token') token: string) {
    await this.prisma.deviceToken.deleteMany({ where: { token: token.toLowerCase(), userId: ctx.userId } });
  }

  @Get('settings')
  async getSettings(@CurrentCtx() ctx: Ctx) {
    const s = await this.prisma.notificationSettings.upsert({ where: { userId: ctx.userId }, update: {}, create: { userId: ctx.userId } });
    const { userId: _u, ...rest } = s;
    return rest;
  }

  @Put('settings')
  async putSettings(@CurrentCtx() ctx: Ctx, @Body() dto: SettingsDto) {
    const s = await this.prisma.notificationSettings.upsert({ where: { userId: ctx.userId }, update: dto, create: { userId: ctx.userId, ...dto } });
    const { userId: _u, ...rest } = s;
    return rest;
  }
}
