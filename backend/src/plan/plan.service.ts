import { Global, Injectable, Module } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { Err } from '../common/errors';

const MB = 1024 * 1024;
export const MAX_FILE_BYTES = 25 * MB;

export interface PlanLimits {
  members: number;
  activeLists: number | null;
  documents: number | null;
  totalBytes: number;
  historyDays: number | null;
  recurringTasks: boolean;
}

export const FREE_LIMITS: PlanLimits = { members: 3, activeLists: 1, documents: 10, totalBytes: 100 * MB, historyDays: 30, recurringTasks: false };
export const PLUS_LIMITS: PlanLimits = { members: 8, activeLists: null, documents: null, totalBytes: 10 * 1024 * MB, historyDays: null, recurringTasks: true };

export interface PlanInfo {
  premium: boolean;
  limits: PlanLimits;
  maxFileBytes: number;
  subscription: { productId: string; status: string; expiresAt: string; autoRenew: boolean } | null;
}

@Injectable()
export class PlanService {
  constructor(private readonly prisma: PrismaService) {}

  async get(familyId: string): Promise<PlanInfo> {
    const sub = await this.prisma.subscription.findUnique({ where: { familyId } });
    // Premium выдаётся только по серверной записи; доступ сохраняется до конца оплаченного периода,
    // даже если автопродление отменено.
    const premium = !!sub && (sub.status === 'active' || sub.status === 'grace') && sub.expiresAt.getTime() > Date.now();
    return {
      premium,
      limits: premium ? PLUS_LIMITS : FREE_LIMITS,
      maxFileBytes: MAX_FILE_BYTES,
      subscription: sub ? { productId: sub.productId, status: premium ? sub.status : sub.status === 'active' || sub.status === 'grace' ? 'expired' : sub.status, expiresAt: sub.expiresAt.toISOString(), autoRenew: sub.autoRenew } : null,
    };
  }

  async requireRecurring(familyId: string) {
    if (!(await this.get(familyId)).limits.recurringTasks) {
      throw Err.premium('recurring_tasks', 'Повторяющиеся дела доступны в тарифе HomeFold Plus');
    }
  }
}

@Global()
@Module({ providers: [PlanService], exports: [PlanService] })
export class PlanModule {}
