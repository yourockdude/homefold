import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { AllowNoFamily, CurrentCtx, Ctx, Public } from '../common/context';
import { perMinute } from '../common/throttle';
import { AuthService } from './auth.service';
import { RefreshDto, RequestCodeDto, VerifyCodeDto } from './auth.dto';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public() @Throttle({ default: { limit: perMinute(10), ttl: 60_000 } })
  @Post('request-code') @HttpCode(200)
  requestCode(@Body() dto: RequestCodeDto) {
    return this.auth.requestCode(dto.email);
  }

  @Public() @Throttle({ default: { limit: perMinute(20), ttl: 60_000 } })
  @Post('verify') @HttpCode(200)
  verify(@Body() dto: VerifyCodeDto) {
    return this.auth.verifyCode(dto.email, dto.code, dto.deviceName);
  }

  @Public() @Post('refresh') @HttpCode(200)
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @ApiBearerAuth() @AllowNoFamily() @Post('logout') @HttpCode(204)
  async logout(@CurrentCtx() ctx: Ctx) {
    await this.auth.logout(ctx.sessionId);
  }
}
