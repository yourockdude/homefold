import { createEmbeddedPostgres } from './pg-loader';
import { execSync } from 'node:child_process';
import { existsSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export interface EmbeddedDb {
  url: string;
  stop: () => Promise<void>;
}

/** Поднимает локальный PostgreSQL без Docker (только для dev/тестов) и применяет миграции. */
export async function startEmbeddedDb(opts: { dir?: string; port: number; database: string; persistent: boolean }): Promise<EmbeddedDb> {
  const dir = opts.dir ?? mkdtempSync(join(tmpdir(), 'ryadom-pg-'));
  const fresh = !existsSync(join(dir, 'PG_VERSION'));
  const pg = await createEmbeddedPostgres({ databaseDir: dir, port: opts.port, persistent: opts.persistent });
  if (fresh) await pg.initialise();
  await pg.start();
  try {
    await pg.createDatabase(opts.database);
  } catch {
    // база уже существует
  }
  const url = `postgresql://ryadom:ryadom@localhost:${opts.port}/${opts.database}`;
  execSync('npx prisma migrate deploy', { env: { ...process.env, DATABASE_URL: url }, stdio: 'pipe', cwd: join(__dirname, '..') });
  return { url, stop: () => pg.stop() };
}
