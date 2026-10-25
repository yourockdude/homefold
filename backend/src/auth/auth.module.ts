import { Module } from '@nestjs/common';
import { loadConfig } from '../common/config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { Mailer, MemoryMailer, SmtpMailer } from './mailer';

@Module({
  controllers: [AuthController],
  providers: [AuthService, { provide: Mailer, useClass: loadConfig().mail.transport === 'memory' ? MemoryMailer : SmtpMailer }],
  exports: [Mailer],
})
export class AuthModule {}
