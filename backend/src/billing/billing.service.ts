import { Injectable, Logger } from '@nestjs/common';
import { Prisma, SubStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ChangesService } from '../changes/changes.service';
import { PlanService } from '../plan/plan.service';
import { TasksService } from '../tasks/tasks.service';
import { FamilyCtx } from '../common/context';
import { AppError, Err } from '../common/errors';
import { loadConfig } from '../common/config';
import { AppleJws } from './apple-jws';
import { AppStoreApi } from './app-store-api';

interface TxInfo {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  bundleId?: string;
  expiresDate?: number;
  revocationDate?: number;
  environment?: string;
  signedDate?: number;
}

interface ApplyOpts {
  autoRenew?: boolean;
  forceStatus?: SubStatus;
  expiresAt?: Date;
  signedDate?: number;
}

@Injectable()
export class BillingService {
  private readonly logger = new Logger(BillingService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly changes: ChangesService,
    private readonly plan: PlanService,
    private readonly tasks: TasksService,
    private readonly jws: AppleJws,
    private readonly api: AppStoreApi,
  ) {}

  status(ctx: FamilyCtx) {
    return this.plan.get(ctx.familyId);
  }

  /** Серверная проверка подписанной транзакции StoreKit 2. Флаг «я Premium» от клиента не принимается вообще. */
  async verify(ctx: FamilyCtx, signedTransaction: string) {
    await this.applyFromClient(ctx, signedTransaction);
    return this.plan.get(ctx.familyId);
  }

  /** Восстановление: клиент присылает актуальные транзакции (Transaction.currentEntitlements). Идемпотентно. */
  async restore(ctx: FamilyCtx, signedTransactions: string[]) {
    const skipped: string[] = [];
    let applied = 0;
    let lastBound: AppError | null = null;
    for (const jws of signedTransactions) {
      try {
        await this.applyFromClient(ctx, jws);
        applied++;
      } catch (e) {
        if (e instanceof AppError && e.code === 'SUBSCRIPTION_BOUND_TO_OTHER_FAMILY') {
          lastBound = e;
          skipped.push(e.code);
        } else throw e;
      }
    }
    if (!applied && lastBound) throw lastBound;
    return { ...(await this.plan.get(ctx.familyId)), restored: applied, skipped: skipped.length };
  }

  private async applyFromClient(ctx: FamilyCtx, signed: string) {
    let info = this.jws.verify<TxInfo>(signed);
    if (this.api.configured) info = (await this.api.getTransaction(info.transactionId, info.environment ?? "Production")) as unknown as TxInfo;
    this.assertOurs(info);
    return this.apply(ctx.familyId, ctx.userId, info, {});
  }

  private assertOurs(info: TxInfo) {
    const b = loadConfig().billing;
    if (info.bundleId && info.bundleId !== b.bundleId) throw Err.validation('Покупка относится к другому приложению');
    if (!b.productIds.includes(info.productId)) throw Err.validation('Неизвестный тариф');
  }

  /** Привязывает покупку к семье и пересчитывает статус. Повторная обработка той же транзакции безопасна. */
  async apply(familyId: string, userId: string | null, info: TxInfo, opts: ApplyOpts) {
    const bound = await this.prisma.subscription.findUnique({ where: { originalTransactionId: info.originalTransactionId } });
    if (bound && bound.familyId !== familyId) {
      throw Err.conflict('SUBSCRIPTION_BOUND_TO_OTHER_FAMILY', 'Эта покупка уже привязана к другой семье');
    }
    const familySub = bound ?? (await this.prisma.subscription.findUnique({ where: { familyId } }));
    const signedDate = opts.signedDate ?? info.signedDate ?? Date.now();
    if (!bound && familySub && (familySub.status === 'active' || familySub.status === 'grace') && familySub.expiresAt > new Date()) {
      throw Err.conflict('FAMILY_ALREADY_SUBSCRIBED', 'У этой семьи уже есть активная подписка');
    }
    if (bound?.lastSignedAt && signedDate < bound.lastSignedAt.getTime()) return bound; // устаревшее событие

    const expiresAt = opts.expiresAt ?? new Date(info.expiresDate ?? 0);
    const status: SubStatus =
      opts.forceStatus ?? (info.revocationDate ? 'revoked' : expiresAt.getTime() > Date.now() ? 'active' : 'expired');
    const data = {
      originalTransactionId: info.originalTransactionId,
      productId: info.productId,
      status,
      expiresAt,
      autoRenew: opts.autoRenew ?? bound?.autoRenew ?? true,
      environment: info.environment ?? 'Production',
      lastSignedAt: new Date(signedDate),
      ...(userId ? { purchasedById: userId } : {}),
    };
    const sub = familySub
      ? await this.prisma.subscription.update({ where: { id: familySub.id }, data })
      : await this.prisma.subscription.create({ data: { familyId, ...data } as Prisma.SubscriptionUncheckedCreateInput });
    await this.changes.record(familyId, 'family', familyId);
    // Premium вернулся/выдан — возобновляем повторяющиеся дела (данные не удалялись при окончании).
    if (status === 'active' || status === 'grace') await this.tasks.materializeAll(familyId).catch((e) => this.logger.warn(e.message));
    return sub;
  }

  /** App Store Server Notifications V2. Идемпотентно по notificationUUID. */
  async handleAppleNotification(signedPayload: string) {
    const n = this.jws.verify<any>(signedPayload);
    if (!n.notificationUUID) throw Err.validation('Нет notificationUUID');
    if (await this.prisma.appleNotification.findUnique({ where: { uuid: n.notificationUUID } })) return { status: 'duplicate' };

    const data = n.data ?? {};
    if (data.bundleId && data.bundleId !== loadConfig().billing.bundleId) return { status: 'ignored' };
    let handled = false;
    if (data.signedTransactionInfo) {
      const tx = this.jws.verify<TxInfo>(data.signedTransactionInfo);
      const renewal = data.signedRenewalInfo ? this.jws.verify<any>(data.signedRenewalInfo) : null;
      const sub = await this.prisma.subscription.findUnique({ where: { originalTransactionId: tx.originalTransactionId } });
      if (sub) {
        const opts: ApplyOpts = { signedDate: n.signedDate ?? tx.signedDate };
        if (renewal && renewal.autoRenewStatus !== undefined) opts.autoRenew = renewal.autoRenewStatus === 1;
        switch (n.notificationType) {
          case 'REFUND':
          case 'REVOKE':
            opts.forceStatus = 'revoked';
            break;
          case 'EXPIRED':
          case 'GRACE_PERIOD_EXPIRED':
            opts.forceStatus = 'expired';
            break;
          case 'DID_FAIL_TO_RENEW':
            if (n.subtype === 'GRACE_PERIOD') {
              opts.forceStatus = 'grace';
              if (renewal?.gracePeriodExpiresDate) opts.expiresAt = new Date(renewal.gracePeriodExpiresDate);
            }
            break;
        }
        await this.apply(sub.familyId, null, tx, opts);
        handled = true;
      }
      // Неизвестная транзакция: покупка ещё не привязана к семье. Состояние подтянется при verify/restore из приложения.
    }
    await this.prisma.appleNotification.create({ data: { uuid: n.notificationUUID, type: n.notificationType ?? 'UNKNOWN' } }).catch((e) => {
      if (e?.code !== 'P2002') throw e;
    });
    return { status: handled ? 'processed' : 'ignored' };
  }

  // ───────────── dev-режим (BILLING_MODE=sandbox-mock) ─────────────

  private assertMock() {
    const cfg = loadConfig();
    if (cfg.billing.mode !== 'sandbox-mock' || cfg.isProd) throw new AppError(404, 'NOT_FOUND', 'Не найдено');
  }

  async mockPurchase(ctx: FamilyCtx, productId?: string, days = 30) {
    this.assertMock();
    const id = `mock-${ctx.familyId}`;
    await this.apply(ctx.familyId, ctx.userId, {
      transactionId: `${id}-${Date.now()}`, originalTransactionId: id,
      productId: productId ?? loadConfig().billing.productIds[0], environment: 'Sandbox',
      expiresDate: Date.now() + days * 86400_000, signedDate: Date.now(),
    }, { autoRenew: true });
    return this.plan.get(ctx.familyId);
  }

  async mockExpire(ctx: FamilyCtx, autoRenewOff = false) {
    this.assertMock();
    const sub = await this.prisma.subscription.findUnique({ where: { familyId: ctx.familyId } });
    if (!sub) throw Err.notFound('Подписка');
    await this.prisma.subscription.update({
      where: { id: sub.id },
      data: autoRenewOff ? { autoRenew: false } : { status: 'expired', expiresAt: new Date(Date.now() - 1000), autoRenew: false },
    });
    await this.changes.record(ctx.familyId, 'family', ctx.familyId);
    return this.plan.get(ctx.familyId);
  }
}
