import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

process.env.MAIL_TRANSPORT = 'memory';
process.env.DATABASE_URL ??= 'postgresql://ryadom:ryadom@localhost:1/none';

async function main() {
  const { AppModule } = await import('../src/app.module');
  const { buildOpenApi, configureApp } = await import('../src/setup');
  const app = await NestFactory.create(AppModule, { logger: false, abortOnError: false });
  configureApp(app);
  // Без listen и без подключения к БД: Prisma подключается лениво в onModuleInit, поэтому только строим документ.
  writeFileSync(join(__dirname, '..', 'openapi.json'), JSON.stringify(buildOpenApi(app), null, 2));
  process.exit(0);
}
void main();
