import { Body, Controller, Get, HttpCode, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { ArrayMaxSize, IsArray, IsBoolean, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { CurrentCtx, Ctx, FamilyCtx, Public } from '../common/context';
import { BillingService } from './billing.service';

class VerifyDto {
  @ApiProperty({ description: 'JWS подписанной транзакции StoreKit 2 (Transaction.jsonRepresentation)' }) @IsString() @MaxLength(20000)
  signedTransaction: string;
}
class RestoreDto {
  @ApiProperty({ type: [String] }) @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @MaxLength(20000, { each: true })
  signedTransactions: string[];
}
class AppleNotificationDto {
  @ApiProperty() @IsString() @MaxLength(100000) signedPayload: string;
}
class MockPurchaseDto {
  @ApiPropertyOptional() @IsOptional() @IsString() productId?: string;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(1) @Max(400) days?: number;
}
class MockExpireDto {
  @ApiPropertyOptional({ description: 'true — только отключить автопродление' }) @IsOptional() @IsBoolean() autoRenewOff?: boolean;
}

@ApiTags('billing')
@Controller('billing')
export class BillingController {
  constructor(private readonly billing: BillingService) {}

  @ApiBearerAuth() @Get('status')
  status(@CurrentCtx() ctx: Ctx) {
    return this.billing.status(ctx as FamilyCtx);
  }

  @ApiBearerAuth() @Post('verify') @HttpCode(200)
  verify(@CurrentCtx() ctx: Ctx, @Body() dto: VerifyDto) {
    return this.billing.verify(ctx as FamilyCtx, dto.signedTransaction);
  }

  @ApiBearerAuth() @Post('restore') @HttpCode(200)
  restore(@CurrentCtx() ctx: Ctx, @Body() dto: RestoreDto) {
    return this.billing.restore(ctx as FamilyCtx, dto.signedTransactions);
  }

  /** Вебхук App Store Server Notifications V2. Аутентификация — подпись Apple (JWS), не токен пользователя. */
  @Public() @Post('apple-notifications') @HttpCode(200)
  apple(@Body() dto: AppleNotificationDto) {
    return this.billing.handleAppleNotification(dto.signedPayload);
  }

  /** Только BILLING_MODE=sandbox-mock вне production; иначе 404. */
  @ApiBearerAuth() @Post('dev/mock-purchase') @HttpCode(200)
  mockPurchase(@CurrentCtx() ctx: Ctx, @Body() dto: MockPurchaseDto) {
    return this.billing.mockPurchase(ctx as FamilyCtx, dto.productId, dto.days);
  }

  @ApiBearerAuth() @Post('dev/mock-expire') @HttpCode(200)
  mockExpire(@CurrentCtx() ctx: Ctx, @Body() dto: MockExpireDto) {
    return this.billing.mockExpire(ctx as FamilyCtx, dto.autoRenewOff);
  }
}
