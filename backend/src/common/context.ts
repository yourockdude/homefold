import { createParamDecorator, ExecutionContext, SetMetadata } from '@nestjs/common';

export interface Ctx {
  userId: string;
  sessionId: string;
  familyId: string | null;
  role: 'admin' | 'member' | null;
  displayName: string | null;
}

/** Family-scoped контекст: familyId гарантированно есть. */
export interface FamilyCtx extends Ctx {
  familyId: string;
  role: 'admin' | 'member';
}

export const IS_PUBLIC = 'isPublic';
export const ALLOW_NO_FAMILY = 'allowNoFamily';
export const ADMIN_ONLY = 'adminOnly';

export const Public = () => SetMetadata(IS_PUBLIC, true);
/** Эндпоинт доступен авторизованному пользователю без семьи. */
export const AllowNoFamily = () => SetMetadata(ALLOW_NO_FAMILY, true);
export const AdminOnly = () => SetMetadata(ADMIN_ONLY, true);

export const CurrentCtx = createParamDecorator((_d: unknown, ec: ExecutionContext): Ctx => ec.switchToHttp().getRequest().ctx);
