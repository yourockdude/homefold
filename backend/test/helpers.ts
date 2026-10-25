import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { SignJWT, importPKCS8 } from 'jose';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/setup';
import { MemoryMailer, Mailer } from '../src/auth/mailer';
import { PrismaService } from '../src/prisma/prisma.service';

export async function makeApp(): Promise<INestApplication> {
  const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
  const app = mod.createNestApplication();
  configureApp(app);
  await app.init();
  return app;
}

export const uid = () => randomUUID();
export const email = (prefix = 'u') => `${prefix}-${randomUUID().slice(0, 8)}@test.example`;

export class Client {
  constructor(public app: INestApplication, public email: string, public accessToken: string, public refreshToken: string, public userId: string) {}
  private req(method: 'get' | 'post' | 'put' | 'patch' | 'delete', path: string) {
    return request(this.app.getHttpServer())[method](path).set('Authorization', `Bearer ${this.accessToken}`);
  }
  get = (path: string) => this.req('get', path);
  post = (path: string, body?: object) => this.req('post', path).send(body ?? {});
  put = (path: string, body?: object) => this.req('put', path).send(body ?? {});
  patch = (path: string, body?: object) => this.req('patch', path).send(body ?? {});
  del = (path: string) => this.req('delete', path);
}

export async function signIn(app: INestApplication, mail = email()): Promise<Client> {
  const http = request(app.getHttpServer());
  await http.post('/auth/request-code').send({ email: mail }).expect(200);
  const code = (app.get(Mailer) as MemoryMailer).codes.get(mail)!;
  const res = await request(app.getHttpServer()).post('/auth/verify').send({ email: mail, code }).expect(200);
  return new Client(app, mail, res.body.accessToken, res.body.refreshToken, res.body.user.id);
}

/** Пользователь + своя семья (админ). */
export async function signInWithFamily(app: INestApplication, name = 'Тестовы', displayName = 'Анна'): Promise<Client> {
  const c = await signIn(app);
  await c.post('/families', { name, displayName }).expect(201);
  return c;
}

/** Админ приглашает нового пользователя, тот принимает. */
export async function addMember(admin: Client, displayName = 'Михаил'): Promise<Client> {
  const inv = await admin.post('/invitations').expect(201);
  const member = await signIn(admin.app);
  await member.post('/invitations/accept', { token: inv.body.token, displayName }).expect(200);
  return member;
}

export async function makePremium(c: Client) {
  await c.post('/billing/dev/mock-purchase', {}).expect(200);
}

export const prisma = (app: INestApplication) => app.get(PrismaService);

// ───────── Тестовые JWS «как у Apple» ─────────

const pkiDir = () => process.env.TEST_PKI_DIR!;
const pem2b64 = (file: string) => readFileSync(join(pkiDir(), file), 'utf8').replace(/-----[A-Z ]+-----|\s/g, '');

export async function signAppleJws(payload: Record<string, unknown>, opts: { chain?: 'good' | 'evil' } = {}) {
  const key = await importPKCS8(readFileSync(join(pkiDir(), 'leaf.p8'), 'utf8'), 'ES256');
  const x5c = opts.chain === 'evil' ? [pem2b64('evilleaf.pem'), pem2b64('evil.pem')] : [pem2b64('leaf.pem'), pem2b64('inter.pem'), pem2b64('root.pem')];
  // Корень в x5c Apple присутствует; доверие определяется набором APPLE_ROOT_CA_PATHS на сервере.
  return new SignJWT(payload as any).setProtectedHeader({ alg: 'ES256', x5c }).sign(key);
}

export function txPayload(over: Record<string, unknown> = {}) {
  const now = Date.now();
  return {
    transactionId: `tx-${randomUUID()}`,
    originalTransactionId: `orig-${randomUUID()}`,
    productId: 'plus.monthly',
    bundleId: 'com.example.ryadom',
    environment: 'Sandbox',
    expiresDate: now + 30 * 86400_000,
    signedDate: now,
    ...over,
  };
}

export async function notification(type: string, tx: Record<string, unknown>, extra: Record<string, unknown> = {}, renewal?: Record<string, unknown>) {
  return signAppleJws({
    notificationType: type,
    notificationUUID: randomUUID(),
    signedDate: Date.now(),
    data: {
      bundleId: 'com.example.ryadom',
      environment: 'Sandbox',
      signedTransactionInfo: await signAppleJws(tx),
      ...(renewal ? { signedRenewalInfo: await signAppleJws(renewal) } : {}),
    },
    ...extra,
  });
}

export const PDF = Buffer.from('%PDF-1.4\n% demo file\n');
export const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32)]);

/** Загрузка файла по presigned URL (локальное хранилище) так же, как это делает клиент. */
export function uploadTo(app: INestApplication, upload: { url: string; headers: Record<string, string> }, data: Buffer) {
  const path = new URL(upload.url).pathname;
  return request(app.getHttpServer()).put(path).set(upload.headers).send(data);
}

/** Создаёт документ, загружает файл и подтверждает. Возвращает документ. */
export async function createReadyDoc(c: Client, over: Record<string, unknown> = {}, data: Buffer = PDF) {
  const id = uid();
  const res = await c.post('/documents', {
    id, title: 'Полис ДМС · Соня', fileName: 'polis.pdf', mimeType: 'application/pdf', sizeBytes: data.length, ...over,
  }).expect(201);
  await uploadTo(c.app, res.body.upload, data).expect(200);
  const conf = await c.post(`/documents/${id}/confirm`).expect(200);
  return conf.body as { id: string };
}
