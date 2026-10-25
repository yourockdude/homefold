import { execSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { startEmbeddedDb } from '../scripts/embedded-db';

/** Тестовая PKI «как у Apple»: root → intermediate → leaf (ES256). Нужна, чтобы проверять JWS без настоящих ключей Apple. */
function makePki(dir: string) {
  const sh = (cmd: string) => execSync(cmd, { cwd: dir, stdio: 'pipe' });
  sh('openssl ecparam -name prime256v1 -genkey -noout -out root.key');
  sh('openssl req -new -x509 -key root.key -subj "/CN=Test Root CA" -days 30 -out root.pem');
  for (const [name, ca] of [['inter', 'root'], ['leaf', 'inter']] as const) {
    sh(`openssl ecparam -name prime256v1 -genkey -noout -out ${name}.key`);
    sh(`openssl req -new -key ${name}.key -subj "/CN=Test ${name}" -out ${name}.csr`);
    sh(`openssl x509 -req -in ${name}.csr -CA ${ca}.pem -CAkey ${ca}.key -CAcreateserial -days 30 -out ${name}.pem`);
  }
  sh('openssl pkcs8 -topk8 -nocrypt -in leaf.key -out leaf.p8');
  // Чужой корень: цепочка, не ведущая к доверенному корню.
  sh('openssl ecparam -name prime256v1 -genkey -noout -out evil.key');
  sh('openssl req -new -x509 -key evil.key -subj "/CN=Evil Root" -days 30 -out evil.pem');
  sh('openssl req -new -key leaf.key -subj "/CN=Test leaf" -out evilleaf.csr');
  sh('openssl x509 -req -in evilleaf.csr -CA evil.pem -CAkey evil.key -CAcreateserial -days 30 -out evilleaf.pem');
}

export default async function globalSetup() {
  const db = await startEmbeddedDb({ port: 54330, database: 'ryadom_test', persistent: false });
  (globalThis as any).__PG__ = db;
  const pki = mkdtempSync(join(tmpdir(), 'ryadom-pki-'));
  makePki(pki);
  const storage = mkdtempSync(join(tmpdir(), 'ryadom-storage-'));
  writeFileSync(join(storage, '.keep'), '');
  mkdirSync(storage, { recursive: true });
  Object.assign(process.env, {
    NODE_ENV: 'test',
    DATABASE_URL: db.url,
    MAIL_TRANSPORT: 'memory',
    BILLING_MODE: 'sandbox-mock',
    STORAGE_DRIVER: 'local',
    STORAGE_LOCAL_DIR: storage, // абсолютный путь: join(cwd, abs) даст cwd+abs — см. LocalStorage
    THROTTLE_LIMIT: '1000000',
    THROTTLE_RELAXED: 'true',
    APPLE_ROOT_CA_PATHS: join(pki, 'root.pem'),
    APPLE_BUNDLE_ID: 'com.example.ryadom',
    APPLE_PRODUCT_IDS: 'plus.monthly,plus.yearly',
    TEST_PKI_DIR: pki,
  });
}
