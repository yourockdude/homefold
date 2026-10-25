export type BillingMode = 'apple' | 'sandbox-mock';

export interface AppConfig {
  nodeEnv: string;
  isProd: boolean;
  port: number;
  publicBaseUrl: string;
  inviteBaseUrl: string;
  jwtSecret: string;
  otpPepper: string;
  accessTtlSec: number;
  refreshTtlDays: number;
  throttleLimit: number;
  mail: { transport: 'smtp' | 'memory'; host: string; port: number; from: string; user?: string; pass?: string; secure: boolean };
  storage: {
    driver: 'local' | 's3';
    localDir: string;
    s3: { bucket: string; region: string; endpoint?: string; publicEndpoint?: string; accessKeyId?: string; secretAccessKey?: string; forcePathStyle: boolean };
  };
  billing: {
    mode: BillingMode;
    bundleId: string;
    productIds: string[];
    rootCaPaths: string[];
    iapKeyId?: string;
    iapIssuerId?: string;
    iapKey?: string;
  };
  apns: { keyId?: string; teamId?: string; key?: string; topic?: string; production: boolean };
}

const list = (v: string | undefined, d: string) => (v ?? d).split(',').map((s) => s.trim()).filter(Boolean);

/** Конфигурация читается из env при каждом обращении — это упрощает тесты. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const nodeEnv = env.NODE_ENV ?? 'development';
  const isProd = nodeEnv === 'production';
  const cfg: AppConfig = {
    nodeEnv,
    isProd,
    port: Number(env.PORT ?? 3000),
    publicBaseUrl: env.PUBLIC_BASE_URL ?? 'http://localhost:3000',
    inviteBaseUrl: env.INVITE_BASE_URL ?? 'https://ryadom.app/join',
    jwtSecret: env.JWT_SECRET ?? 'dev-only-secret-change-me-dev-only-secret',
    otpPepper: env.OTP_PEPPER ?? 'dev-only-pepper',
    accessTtlSec: Number(env.ACCESS_TTL_SEC ?? 900),
    refreshTtlDays: Number(env.REFRESH_TTL_DAYS ?? 60),
    throttleLimit: Number(env.THROTTLE_LIMIT ?? 120),
    mail: {
      transport: (env.MAIL_TRANSPORT as 'smtp' | 'memory') ?? 'smtp',
      host: env.SMTP_HOST ?? 'localhost',
      port: Number(env.SMTP_PORT ?? 1025),
      from: env.MAIL_FROM ?? 'рядом <no-reply@ryadom.app>',
      user: env.SMTP_USER || undefined,
      pass: env.SMTP_PASS || undefined,
      secure: env.SMTP_SECURE === 'true',
    },
    storage: {
      driver: (env.STORAGE_DRIVER as 'local' | 's3') ?? 'local',
      localDir: env.STORAGE_LOCAL_DIR ?? '.storage',
      s3: {
        bucket: env.S3_BUCKET ?? 'ryadom-documents',
        region: env.S3_REGION ?? 'us-east-1',
        endpoint: env.S3_ENDPOINT || undefined,
        publicEndpoint: env.S3_PUBLIC_ENDPOINT || undefined,
        accessKeyId: env.S3_ACCESS_KEY_ID || undefined,
        secretAccessKey: env.S3_SECRET_ACCESS_KEY || undefined,
        forcePathStyle: env.S3_FORCE_PATH_STYLE === 'true',
      },
    },
    billing: {
      mode: (env.BILLING_MODE as BillingMode) ?? 'apple',
      bundleId: env.APPLE_BUNDLE_ID ?? 'com.yuriyurchenko.ryadom',
      productIds: list(env.APPLE_PRODUCT_IDS, 'app.ryadom.plus.monthly,app.ryadom.plus.yearly'),
      rootCaPaths: list(env.APPLE_ROOT_CA_PATHS, 'certs/AppleRootCA-G3.pem'),
      iapKeyId: env.APPLE_IAP_KEY_ID || undefined,
      iapIssuerId: env.APPLE_IAP_ISSUER_ID || undefined,
      iapKey: env.APPLE_IAP_PRIVATE_KEY || undefined,
    },
    apns: {
      keyId: env.APNS_KEY_ID || undefined,
      teamId: env.APNS_TEAM_ID || undefined,
      key: env.APNS_PRIVATE_KEY || undefined,
      topic: env.APNS_TOPIC || undefined,
      production: env.APNS_PRODUCTION === 'true',
    },
  };
  return cfg;
}

/** В production запрещены dev-режимы: mock-биллинг, memory-почта, локальное хранилище, слабые секреты. */
export function assertProductionSafe(cfg: AppConfig): void {
  if (!cfg.isProd) return;
  const problems: string[] = [];
  if (cfg.billing.mode === 'sandbox-mock') problems.push('BILLING_MODE=sandbox-mock запрещён в production');
  if (cfg.mail.transport === 'memory') problems.push('MAIL_TRANSPORT=memory запрещён в production');
  if (cfg.storage.driver === 'local') problems.push('STORAGE_DRIVER=local запрещён в production');
  if (cfg.jwtSecret.length < 32 || cfg.jwtSecret.startsWith('dev-only')) problems.push('JWT_SECRET должен быть случайной строкой ≥32 символов');
  if (cfg.otpPepper.startsWith('dev-only')) problems.push('OTP_PEPPER не задан');
  if (!cfg.publicBaseUrl.startsWith('https://')) problems.push('PUBLIC_BASE_URL должен быть https://');
  if (problems.length) throw new Error(`Небезопасная конфигурация production:\n- ${problems.join('\n- ')}`);
}

export const CONFIG = 'APP_CONFIG';
