import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { assertProductionSafe, loadConfig } from '../src/common/config';
import { addMember, makeApp, notification, signAppleJws, signInWithFamily, txPayload, uid } from './helpers';

describe('Подписка HomeFold Plus', () => {
  let app: INestApplication;
  beforeAll(async () => (app = await makeApp()));
  afterAll(() => app.close());
  const http = () => request(app.getHttpServer());

  it('по умолчанию тариф бесплатный: лимиты free', async () => {
    const c = await signInWithFamily(app);
    const s = await c.get('/billing/status').expect(200);
    expect(s.body).toMatchObject({ premium: false, subscription: null });
    expect(s.body.limits).toMatchObject({ members: 3, activeLists: 1, documents: 10, historyDays: 30, recurringTasks: false });
    expect(s.body.limits.totalBytes).toBe(100 * 1024 * 1024);
    expect(s.body.maxFileBytes).toBe(25 * 1024 * 1024);
  });

  it('проверка покупки: валидная подписанная транзакция открывает Premium всей семье', async () => {
    const admin = await signInWithFamily(app);
    const member = await addMember(admin);
    const signed = await signAppleJws(txPayload());
    const res = await admin.post('/billing/verify', { signedTransaction: signed }).expect(200);
    expect(res.body).toMatchObject({ premium: true, subscription: { status: 'active', productId: 'plus.monthly' } });
    expect(res.body.limits).toMatchObject({ members: 8, recurringTasks: true, activeLists: null, documents: null });
    // участник получает Premium без своей покупки
    expect((await member.get('/billing/status').expect(200)).body.premium).toBe(true);
  });

  it('клиентский флаг Premium игнорируется', async () => {
    const c = await signInWithFamily(app);
    await c.post('/billing/verify', { signedTransaction: 'x.y.z', premium: true }).expect(400);
    await c.put(`/shopping/lists/${uid()}`, { name: 'a', premium: true, isPremium: true }).expect(200);
    await c.put(`/shopping/lists/${uid()}`, { name: 'b', premium: true }).expect(402);
    await c.patch(`/families/me`, { name: 'Семья', plan: 'plus' }).expect(200);
    expect((await c.get('/billing/status').expect(200)).body.premium).toBe(false);
  });

  it('подделки отклоняются: изменённая нагрузка, чужая цепочка, чужой bundleId и товар', async () => {
    const c = await signInWithFamily(app);
    const good = await signAppleJws(txPayload());
    const [h, , s] = good.split('.');
    const forged = `${h}.${Buffer.from(JSON.stringify(txPayload({ expiresDate: Date.now() + 9e10 }))).toString('base64url')}.${s}`;
    expect((await c.post('/billing/verify', { signedTransaction: forged }).expect(400)).body.error.code).toBe('INVALID_SIGNATURE');
    const evil = await signAppleJws(txPayload(), { chain: 'evil' });
    expect((await c.post('/billing/verify', { signedTransaction: evil }).expect(400)).body.error.code).toBe('INVALID_SIGNATURE');
    await c.post('/billing/verify', { signedTransaction: await signAppleJws(txPayload({ bundleId: 'com.other.app' })) }).expect(400);
    await c.post('/billing/verify', { signedTransaction: await signAppleJws(txPayload({ productId: 'hack.free' })) }).expect(400);
    expect((await c.get('/billing/status').expect(200)).body.premium).toBe(false);
  });

  it('повторная проверка той же транзакции идемпотентна', async () => {
    const c = await signInWithFamily(app);
    const signed = await signAppleJws(txPayload());
    await c.post('/billing/verify', { signedTransaction: signed }).expect(200);
    await c.post('/billing/verify', { signedTransaction: signed }).expect(200);
    const { PrismaService } = await import('../src/prisma/prisma.service');
    const fam = (await c.get('/families/me').expect(200)).body;
    expect(await app.get(PrismaService).subscription.count({ where: { familyId: fam.id } })).toBe(1);
  });

  it('одна покупка привязывается к одной семье', async () => {
    const a = await signInWithFamily(app);
    const b = await signInWithFamily(app);
    const tx = txPayload();
    await a.post('/billing/verify', { signedTransaction: await signAppleJws(tx) }).expect(200);
    const res = await b.post('/billing/verify', { signedTransaction: await signAppleJws({ ...tx, transactionId: 'renewal-1' }) }).expect(409);
    expect(res.body.error.code).toBe('SUBSCRIPTION_BOUND_TO_OTHER_FAMILY');
    expect((await b.get('/billing/status').expect(200)).body.premium).toBe(false);
    const restore = await b.post('/billing/restore', { signedTransactions: [await signAppleJws(tx)] }).expect(409);
    expect(restore.body.error.code).toBe('SUBSCRIPTION_BOUND_TO_OTHER_FAMILY');
  });

  it('семья с активной подпиской не принимает вторую чужую покупку', async () => {
    const c = await signInWithFamily(app);
    await c.post('/billing/verify', { signedTransaction: await signAppleJws(txPayload()) }).expect(200);
    const res = await c.post('/billing/verify', { signedTransaction: await signAppleJws(txPayload()) }).expect(409);
    expect(res.body.error.code).toBe('FAMILY_ALREADY_SUBSCRIBED');
  });

  it('восстановление покупок: возвращает Premium новой семье-владельцу, повтор безопасен', async () => {
    const c = await signInWithFamily(app);
    const tx = txPayload();
    const r1 = await c.post('/billing/restore', { signedTransactions: [await signAppleJws(tx)] }).expect(200);
    expect(r1.body).toMatchObject({ premium: true, restored: 1 });
    const r2 = await c.post('/billing/restore', { signedTransactions: [await signAppleJws(tx)] }).expect(200);
    expect(r2.body).toMatchObject({ premium: true });
    const empty = await signInWithFamily(app);
    expect((await empty.post('/billing/restore', { signedTransactions: [] }).expect(200)).body).toMatchObject({ premium: false, restored: 0 });
  });

  describe('уведомления App Store (V2)', () => {
    it('DID_RENEW продлевает; повтор уведомления (тот же UUID) не применяется дважды', async () => {
      const c = await signInWithFamily(app);
      const tx = txPayload({ expiresDate: Date.now() + 1000 });
      await c.post('/billing/verify', { signedTransaction: await signAppleJws(tx) }).expect(200);
      const renewed = { ...tx, transactionId: 'r2', expiresDate: Date.now() + 30 * 86400_000, signedDate: Date.now() + 10 };
      const n = await notification('DID_RENEW', renewed);
      expect((await http().post('/billing/apple-notifications').send({ signedPayload: n }).expect(200)).body.status).toBe('processed');
      expect((await http().post('/billing/apple-notifications').send({ signedPayload: n }).expect(200)).body.status).toBe('duplicate');
      const st = (await c.get('/billing/status').expect(200)).body;
      expect(st.premium).toBe(true);
      expect(new Date(st.subscription.expiresAt).getTime()).toBeGreaterThan(Date.now() + 29 * 86400_000);
    });

    it('отмена автопродления не прекращает доступ до конца периода', async () => {
      const c = await signInWithFamily(app);
      const tx = txPayload();
      await c.post('/billing/verify', { signedTransaction: await signAppleJws(tx) }).expect(200);
      const n = await notification('DID_CHANGE_RENEWAL_STATUS', { ...tx, signedDate: Date.now() + 5 }, { subtype: 'AUTO_RENEW_DISABLED' }, { autoRenewStatus: 0 });
      await http().post('/billing/apple-notifications').send({ signedPayload: n }).expect(200);
      const st = (await c.get('/billing/status').expect(200)).body;
      expect(st).toMatchObject({ premium: true, subscription: { autoRenew: false, status: 'active' } });
    });

    it('EXPIRED закрывает Premium; REFUND — тоже; устаревшее по signedDate событие игнорируется', async () => {
      const c = await signInWithFamily(app);
      const tx = txPayload();
      await c.post('/billing/verify', { signedTransaction: await signAppleJws(tx) }).expect(200);
      const t = Date.now();
      await http().post('/billing/apple-notifications').send({ signedPayload: await notification('EXPIRED', { ...tx, expiresDate: t - 1000, signedDate: t + 100 }, { signedDate: t + 100 }) }).expect(200);
      expect((await c.get('/billing/status').expect(200)).body).toMatchObject({ premium: false, subscription: { status: 'expired' } });
      // «опоздавшее» DID_RENEW с более ранней датой подписи не оживляет подписку
      await http().post('/billing/apple-notifications').send({ signedPayload: await notification('DID_RENEW', { ...tx, signedDate: t }, { signedDate: t }) }).expect(200);
      expect((await c.get('/billing/status').expect(200)).body.premium).toBe(false);
      // новое продление после окончания — работает
      await http().post('/billing/apple-notifications').send({ signedPayload: await notification('SUBSCRIBED', { ...tx, expiresDate: t + 86400_000, signedDate: t + 200 }, { signedDate: t + 200 }) }).expect(200);
      expect((await c.get('/billing/status').expect(200)).body.premium).toBe(true);
      await http().post('/billing/apple-notifications').send({ signedPayload: await notification('REFUND', { ...tx, revocationDate: t, signedDate: t + 300 }, { signedDate: t + 300 }) }).expect(200);
      expect((await c.get('/billing/status').expect(200)).body).toMatchObject({ premium: false, subscription: { status: 'revoked' } });
    });

    it('льготный период (GRACE_PERIOD) сохраняет Premium', async () => {
      const c = await signInWithFamily(app);
      const tx = txPayload({ expiresDate: Date.now() - 1000 });
      await c.post('/billing/verify', { signedTransaction: await signAppleJws(tx) }).expect(200);
      expect((await c.get('/billing/status').expect(200)).body.premium).toBe(false);
      const grace = Date.now() + 5 * 86400_000;
      await http().post('/billing/apple-notifications').send({ signedPayload: await notification('DID_FAIL_TO_RENEW', { ...tx, signedDate: Date.now() + 50 }, { subtype: 'GRACE_PERIOD', signedDate: Date.now() + 50 }, { gracePeriodExpiresDate: grace, autoRenewStatus: 1 }) }).expect(200);
      expect((await c.get('/billing/status').expect(200)).body).toMatchObject({ premium: true, subscription: { status: 'grace' } });
    });

    it('вебхук отвергает неподписанные и поддельные уведомления; уведомление о неизвестной покупке не падает', async () => {
      await http().post('/billing/apple-notifications').send({ signedPayload: 'a.b.c' }).expect(400);
      await http().post('/billing/apple-notifications').send({ signedPayload: await signAppleJws({ notificationType: 'EXPIRED', notificationUUID: uid() }, { chain: 'evil' }) }).expect(400);
      const unknown = await notification('DID_RENEW', txPayload());
      expect((await http().post('/billing/apple-notifications').send({ signedPayload: unknown }).expect(200)).body.status).toBe('ignored');
    });
  });

  describe('окончание подписки', () => {
    it('участники не исключаются, данные остаются, новые приглашения сверх лимита блокируются', async () => {
      const admin = await signInWithFamily(app);
      await admin.post('/billing/dev/mock-purchase', {}).expect(200);
      for (const n of ['Б', 'В', 'Г']) await addMember(admin, n); // 4 участника — больше бесплатных 3
      await admin.post('/billing/dev/mock-expire', {}).expect(200);
      const fam = (await admin.get('/families/me').expect(200)).body;
      expect(fam.members).toHaveLength(4);
      expect(fam.plan.premium).toBe(false);
      expect((await admin.post('/invitations').expect(402)).body.error.details.feature).toBe('members');
    });
  });

  describe('dev-режим не доступен в production', () => {
    it('mock-эндпоинты отвечают 404 при NODE_ENV=production', async () => {
      const c = await signInWithFamily(app);
      const prev = process.env.NODE_ENV;
      process.env.NODE_ENV = 'production';
      try {
        await c.post('/billing/dev/mock-purchase', {}).expect(404);
      } finally {
        process.env.NODE_ENV = prev;
      }
    });

    it('сервер отказывается стартовать в production с mock-биллингом, memory-почтой, локальным хранилищем и слабыми секретами', () => {
      const bad = loadConfig({ NODE_ENV: 'production', BILLING_MODE: 'sandbox-mock', MAIL_TRANSPORT: 'memory', STORAGE_DRIVER: 'local' } as any);
      expect(() => assertProductionSafe(bad)).toThrow(/sandbox-mock[\s\S]*memory[\s\S]*local[\s\S]*JWT_SECRET/);
      const ok = loadConfig({
        NODE_ENV: 'production', BILLING_MODE: 'apple', MAIL_TRANSPORT: 'smtp', STORAGE_DRIVER: 's3',
        JWT_SECRET: 'x'.repeat(48), OTP_PEPPER: 'pepper-value', PUBLIC_BASE_URL: 'https://api.ryadom.app',
      } as any);
      expect(() => assertProductionSafe(ok)).not.toThrow();
    });
  });
});
