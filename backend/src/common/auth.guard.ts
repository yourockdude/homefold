import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { jwtVerify } from 'jose';
import { PrismaService } from '../prisma/prisma.service';
import { AppError, Err } from './errors';
import { ADMIN_ONLY, ALLOW_NO_FAMILY, Ctx, IS_PUBLIC } from './context';
import { loadConfig } from './config';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly reflector: Reflector, private readonly prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, targets)) return true;

    const req = context.switchToHttp().getRequest();
    const header: string | undefined = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) throw new AppError(401, 'UNAUTHORIZED', 'Требуется вход');
    const ctx = await authenticate(this.prisma, header.slice(7));
    req.ctx = ctx;

    if (!this.reflector.getAllAndOverride<boolean>(ALLOW_NO_FAMILY, targets) && !ctx.familyId) {
      throw new AppError(403, 'NO_FAMILY', 'Сначала создайте семью или примите приглашение');
    }
    if (this.reflector.getAllAndOverride<boolean>(ADMIN_ONLY, targets) && ctx.role !== 'admin') {
      throw Err.forbidden('Действие доступно только администратору семьи');
    }
    return true;
  }
}

/** Проверяет access-токен, сессию и актуальное членство в семье (из БД, не из токена). */
export async function authenticate(prisma: PrismaService, token: string): Promise<Ctx> {
  const cfg = loadConfig();
  let sub: string | undefined;
  let sid: string | undefined;
  try {
    const { payload } = await jwtVerify(token, new TextEncoder().encode(cfg.jwtSecret), { issuer: 'ryadom', algorithms: ['HS256'] });
    sub = payload.sub;
    sid = payload.sid as string;
  } catch {
    throw new AppError(401, 'TOKEN_INVALID', 'Сессия истекла. Войдите снова');
  }
  const session = await prisma.session.findUnique({ where: { id: sid }, include: { user: { include: { membership: true } } } });
  if (!session || session.revokedAt || session.expiresAt < new Date() || session.userId !== sub || session.user.deletedAt) {
    throw new AppError(401, 'TOKEN_INVALID', 'Сессия истекла. Войдите снова');
  }
  const m = session.user.membership;
  return { userId: session.userId, sessionId: session.id, familyId: m?.familyId ?? null, role: m?.role ?? null, displayName: m?.displayName ?? null };
}
