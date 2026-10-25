import { execSync } from 'node:child_process';
import { join } from 'node:path';
import { createEmbeddedPostgres } from './pg-loader';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';

/** Генерирует SQL-миграцию из schema.prisma без Docker: npx ts-node scripts/make-migration.ts <name> */
async function main() {
  const name = process.argv[2] ?? 'init';
  const pg = await createEmbeddedPostgres({ databaseDir: mkdtempSync(join(tmpdir(), 'mig-')), port: 54329, persistent: false });
  await pg.initialise();
  await pg.start();
  await pg.createDatabase('mig');
  try {
    execSync(`npx prisma migrate dev --name ${name} --skip-seed`, { stdio: 'inherit', env: { ...process.env, DATABASE_URL: 'postgresql://ryadom:ryadom@localhost:54329/mig' } });
  } finally {
    await pg.stop();
  }
}
void main();
