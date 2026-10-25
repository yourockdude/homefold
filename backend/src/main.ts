import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { assertProductionSafe, loadConfig } from './common/config';
import { buildOpenApi, configureApp } from './setup';

async function bootstrap() {
  const cfg = loadConfig();
  assertProductionSafe(cfg);
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { logger: cfg.isProd ? ['error', 'warn', 'log'] : ['error', 'warn', 'log'] });
  app.set('trust proxy', 1);
  app.enableShutdownHooks();
  configureApp(app);
  SwaggerModule.setup('docs', app, buildOpenApi(app));
  await app.listen(cfg.port);
}
void bootstrap();
