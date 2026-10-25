import { INestApplication, ValidationError, ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import * as express from 'express';
import { AllExceptionsFilter, Err } from './common/errors';

/** Общая настройка приложения для main.ts, тестов и выгрузки OpenAPI. */
export function configureApp(app: INestApplication) {
  app.useGlobalFilters(new AllExceptionsFilter());
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      exceptionFactory: (errors: ValidationError[]) =>
        Err.validation(
          errors.flatMap((e) => Object.values(e.constraints ?? {}))[0] ?? 'Некорректные данные',
          errors.map((e) => ({ field: e.property, messages: Object.values(e.constraints ?? {}) })),
        ),
    }),
  );
  // Локальное хранилище принимает «сырые» байты файла.
  app.use('/storage/upload', express.raw({ type: () => true, limit: '26mb' }));
}

export function buildOpenApi(app: INestApplication) {
  const config = new DocumentBuilder()
    .setTitle('HomeFold API')
    .setDescription('Backend семейного приложения HomeFold. Ошибки: { "error": { "code", "message", "details?" } }.')
    .setVersion('0.1.0')
    .addBearerAuth()
    .build();
  return SwaggerModule.createDocument(app, config);
}
