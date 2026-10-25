import { join } from 'node:path';
import { startEmbeddedDb } from './embedded-db';

async function main() {
  const db = await startEmbeddedDb({ dir: join(__dirname, '..', '.pgdata'), port: 5432, database: 'ryadom', persistent: true });
  console.log(`PostgreSQL запущен: ${db.url}\nCtrl+C — остановить.`);
  const stop = async () => {
    await db.stop();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}
void main();
