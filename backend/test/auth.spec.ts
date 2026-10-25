import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Mailer, MemoryMailer } from '../src/auth/mailer';
import { email, makeApp, prisma, signIn } from './helpers';

describe('Вход по email и коду', () => {
  let app: INestApplication;
  beforeAll(async () => (app = await makeApp()));
  afterAll(() => app.close());
  const http = () => request(app.getHttpServer());
  const code = (mail: string) => (app.get(Mailer) as MemoryMailer).codes.get(mail)!;

  it('успешный вход выдаёт токены; /me без семьи возвращает family: null', async () => {
    const c = await signIn(app);
    const me = await c.get('/me').expect(200);
    expect(me.body.family).toBeNull();
    expect(c.refreshToken).toBeTruthy();
  });

  it('некорректный email → 400 в едином формате ошибок', async () => {
    const res = await http().post('/auth/request-code').send({ email: 'не-email' }).expect(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(res.body.error.message).toBeTruthy();
  });

  it('неверный код → 401 CODE_INVALID с числом оставшихся попыток', async () => {
    const mail = email();
    await http().post('/auth/request-code').send({ email: mail }).expect(200);
    const res = await http().post('/auth/verify').send({ email: mail, code: code(mail) === '000000' ? '111111' : '000000' }).expect(401);
    expect(res.body.error.code).toBe('CODE_INVALID');
    expect(res.body.error.details.attemptsLeft).toBe(4);
  });

  it('после 5 неверных попыток верный код уже не принимается', async () => {
    const mail = email();
    await http().post('/auth/request-code').send({ email: mail }).expect(200);
    const good = code(mail);
    const wrong = good === '123456' ? '654321' : '123456';
    for (let i = 0; i < 5; i++) await http().post('/auth/verify').send({ email: mail, code: wrong }).expect(401);
    const res = await http().post('/auth/verify').send({ email: mail, code: good }).expect(429);
    expect(res.body.error.code).toBe('CODE_ATTEMPTS_EXCEEDED');
  });

  it('просроченный код → CODE_EXPIRED', async () => {
    const mail = email();
    await http().post('/auth/request-code').send({ email: mail }).expect(200);
    await prisma(app).loginCode.updateMany({ where: { email: mail }, data: { expiresAt: new Date(Date.now() - 1000) } });
    const res = await http().post('/auth/verify').send({ email: mail, code: code(mail) }).expect(401);
    expect(res.body.error.code).toBe('CODE_EXPIRED');
  });

  it('код одноразовый', async () => {
    const mail = email();
    await http().post('/auth/request-code').send({ email: mail }).expect(200);
    const c = code(mail);
    await http().post('/auth/verify').send({ email: mail, code: c }).expect(200);
    await http().post('/auth/verify').send({ email: mail, code: c }).expect(401);
  });

  it('повторная отправка раньше таймера → 429 с retryAfterSeconds; код в БД хранится только хешем', async () => {
    const mail = email();
    await http().post('/auth/request-code').send({ email: mail }).expect(200);
    const res = await http().post('/auth/request-code').send({ email: mail }).expect(429);
    expect(res.body.error.code).toBe('RESEND_TOO_SOON');
    expect(res.body.error.details.retryAfterSeconds).toBeGreaterThan(0);
    const row = await prisma(app).loginCode.findFirst({ where: { email: mail } });
    expect(row!.codeHash).not.toContain(code(mail));
  });

  it('не больше 5 кодов в час на email', async () => {
    const mail = email();
    for (let i = 0; i < 5; i++) {
      await http().post('/auth/request-code').send({ email: mail }).expect(200);
      await prisma(app).loginCode.updateMany({ where: { email: mail }, data: { createdAt: new Date(Date.now() - 120_000 + i) } });
    }
    const res = await http().post('/auth/request-code').send({ email: mail }).expect(429);
    expect(res.body.error.code).toBe('TOO_MANY_CODES');
  });

  it('refresh ротирует токен; повтор старого refresh отзывает сессию', async () => {
    const c = await signIn(app);
    const r1 = await http().post('/auth/refresh').send({ refreshToken: c.refreshToken }).expect(200);
    expect(r1.body.refreshToken).not.toBe(c.refreshToken);
    await http().post('/auth/refresh').send({ refreshToken: c.refreshToken }).expect(401); // кража → сессия отозвана
    await http().post('/auth/refresh').send({ refreshToken: r1.body.refreshToken }).expect(401);
    await http().get('/me').set('Authorization', `Bearer ${r1.body.accessToken}`).expect(401);
  });

  it('выход отзывает сессию', async () => {
    const c = await signIn(app);
    await c.post('/auth/logout').expect(204);
    await c.get('/me').expect(401);
    await http().post('/auth/refresh').send({ refreshToken: c.refreshToken }).expect(401);
  });

  it('без токена и с мусорным токеном → 401', async () => {
    await http().get('/me').expect(401);
    await http().get('/me').set('Authorization', 'Bearer abc.def.ghi').expect(401);
  });

  it('health доступен без токена', async () => {
    const res = await http().get('/health').expect(200);
    expect(res.body.status).toBe('ok');
  });
});
