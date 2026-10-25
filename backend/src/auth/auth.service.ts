import { Injectable, Logger } from '@nestjs/common';
import { createHash, randomBytes, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import { SignJWT } from 'jose';
import { PrismaService } from '../prisma/prisma.service';
import { AppError } from '../common/errors';
import { loadConfig } from '../common/config';
import { Mailer } from './mailer';

export const CODE_TTL_MS = 10 * 60_000;
export const RESEND_COOLDOWN_SEC = 60;
export const MAX_CODES_PER_HOUR = 5;
export const MAX_VERIFY_ATTEMPTS = 5;

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  constructor(private readonly prisma: PrismaService, private readonly mailer: Mailer) {}

  private codeHash(email: string, code: string) {
    return sha256(`${loadConfig().otpPepper}:${email}:${code}`);
  }

  async requestCode(email: string) {
    const now = Date.now();
    const recent = await this.prisma.loginCode.findMany({ where: { email, createdAt: { gt: new Date(now - 3600_000) } }, orderBy: { createdAt: 'desc' } });
    if (recent[0]) {
      const wait = Math.ceil((recent[0].createdAt.getTime() + RESEND_COOLDOWN_SEC * 1000 - now) / 1000);
      if (wait > 0) throw new AppError(429, 'RESEND_TOO_SOON', `Повторная отправка через ${wait} с`, { retryAfterSeconds: wait });
    }
    if (recent.length >= MAX_CODES_PER_HOUR) {
      throw new AppError(429, 'TOO_MANY_CODES', 'Слишком много запросов кода. Попробуйте через час', { retryAfterSeconds: 3600 });
    }
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    await this.prisma.loginCode.create({ data: { email, codeHash: this.codeHash(email, code), expiresAt: new Date(now + CODE_TTL_MS) } });
    try {
      await this.mailer.sendLoginCode(email, code);
    } catch (e) {
      this.logger.error(`Не удалось отправить письмо: ${(e as Error).message}`);
      throw new AppError(503, 'MAIL_UNAVAILABLE', 'Не удалось отправить письмо. Попробуйте позже');
    }
    // Ответ одинаков для существующих и новых email — не раскрываем наличие аккаунта.
    return { expiresInSeconds: CODE_TTL_MS / 1000, resendAfterSeconds: RESEND_COOLDOWN_SEC };
  }

  async verifyCode(email: string, code: string, deviceName?: string) {
    const row = await this.prisma.loginCode.findFirst({ where: { email, consumedAt: null }, orderBy: { createdAt: 'desc' } });
    if (!row) throw new AppError(401, 'CODE_INVALID', 'Неверный код');
    if (row.expiresAt.getTime() < Date.now()) throw new AppError(401, 'CODE_EXPIRED', 'Срок действия кода истёк. Запросите новый');
    if (row.attempts >= MAX_VERIFY_ATTEMPTS) throw new AppError(429, 'CODE_ATTEMPTS_EXCEEDED', 'Слишком много попыток. Запросите новый код');

    const ok = timingSafeEqual(Buffer.from(this.codeHash(email, code)), Buffer.from(row.codeHash));
    if (!ok) {
      const upd = await this.prisma.loginCode.update({ where: { id: row.id }, data: { attempts: { increment: 1 } } });
      throw new AppError(401, 'CODE_INVALID', 'Неверный код', { attemptsLeft: Math.max(0, MAX_VERIFY_ATTEMPTS - upd.attempts) });
    }
    // Атомарное «потребление»: параллельный повтор того же кода не пройдёт.
    const consumed = await this.prisma.loginCode.updateMany({ where: { id: row.id, consumedAt: null }, data: { consumedAt: new Date() } });
    if (consumed.count === 0) throw new AppError(401, 'CODE_INVALID', 'Неверный код');

    const user = await this.prisma.user.upsert({ where: { email }, update: {}, create: { email } });
    if (user.deletedAt) throw new AppError(403, 'ACCOUNT_DELETED', 'Аккаунт удалён');
    return this.issueSession(user.id, deviceName);
  }

  private async mintAccess(userId: string, sessionId: string) {
    const cfg = loadConfig();
    return new SignJWT({ sid: sessionId })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(userId)
      .setIssuer('ryadom')
      .setIssuedAt()
      .setExpirationTime(`${cfg.accessTtlSec}s`)
      .sign(new TextEncoder().encode(cfg.jwtSecret));
  }

  private async issueSession(userId: string, deviceName?: string) {
    const cfg = loadConfig();
    const id = randomUUID();
    const refresh = `${id}.${randomBytes(32).toString('base64url')}`;
    await this.prisma.session.create({
      data: { id, userId, refreshHash: sha256(refresh), deviceName, expiresAt: new Date(Date.now() + cfg.refreshTtlDays * 86400_000) },
    });
    return this.tokens(userId, id, refresh);
  }

  private async tokens(userId: string, sessionId: string, refreshToken: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { id: true, email: true } });
    return { accessToken: await this.mintAccess(userId, sessionId), refreshToken, expiresInSeconds: loadConfig().accessTtlSec, user };
  }

  /** Ротация refresh-токена. Повторное предъявление старого токена = компрометация: сессия отзывается. */
  async refresh(refreshToken: string) {
    const bad = () => new AppError(401, 'REFRESH_INVALID', 'Сессия истекла. Войдите снова');
    const sid = refreshToken.split('.')[0];
    if (!/^[0-9a-f-]{36}$/i.test(sid)) throw bad();
    const session = await this.prisma.session.findUnique({ where: { id: sid } });
    if (!session || session.revokedAt || session.expiresAt < new Date()) throw bad();
    const hash = sha256(refreshToken);
    if (hash === session.prevHash) {
      await this.prisma.session.update({ where: { id: sid }, data: { revokedAt: new Date() } });
      throw bad();
    }
    if (hash !== session.refreshHash) throw bad();
    const next = `${sid}.${randomBytes(32).toString('base64url')}`;
    const rotated = await this.prisma.session.updateMany({ where: { id: sid, refreshHash: hash }, data: { prevHash: hash, refreshHash: sha256(next) } });
    if (rotated.count === 0) throw bad();
    return this.tokens(session.userId, sid, next);
  }

  async logout(sessionId: string) {
    await this.prisma.session.updateMany({ where: { id: sessionId, revokedAt: null }, data: { revokedAt: new Date() } });
  }
}
