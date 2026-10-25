# «рядом» — архитектура и допущения

## Состав
```
Ryadom/
├── ios/                # Xcode workspace + SPM-пакет RyadomPackage (вся логика и UI)
├── backend/            # NestJS + Prisma + PostgreSQL, S3 (MinIO), Mailpit
├── docker-compose.yml  # postgres, minio, mailpit, api
└── docs/
```

## iOS (iOS 18+, Swift 6, SwiftUI, MV без ViewModel)
Модули внутри `RyadomPackage` (папки таргета `RyadomFeature`):
- `DesignSystem/` — Tokens (цвета, отступы, радиусы, шрифты), общие компоненты (кнопки, карточки, аватары, чипы, таб-бар).
- `Models/` — SwiftData `@Model`: локальная БД — источник данных для UI. Поля синхронизации: `id (UUID, клиентский)`, `familyId`, `authorId`, `createdAt`, `updatedAt`, `version`, `deletedAt`, `syncState (synced|pending|failed)`.
- `Networking/` — `APIClient` (URLSession, async/await), единый формат ошибок, токены в Keychain.
- `Sync/` — `OutboxOperation` (персистентная очередь), `SyncEngine` (actor): push операций с экспоненциальным backoff → pull по курсору; `RealtimeClient` (WebSocket — только сигнал «есть изменения»).
- `Services/` — AuthService, FamilyService, NotificationScheduler, BiometricGate, SubscriptionService (StoreKit 2), DocumentFileStore (Data Protection).
- `Features/` — Auth, Family, Overview, Shopping, Tasks, Documents, Settings, Paywall.

Данные текут так: действие → запись в SwiftData + `OutboxOperation` → SyncEngine → сервер → ответ (серверная версия/метка) → обновление записи.

## Backend (NestJS, TypeScript)
Модули: auth, families, invitations, shopping, tasks, documents, sync, notifications (APNs + WebSocket gateway), billing (App Store Server API), health.
- Prisma + миграции; секреты только из env; OpenAPI на `/docs`.
- Единый формат ошибок `{ error: { code, message, details? } }`; пагинация курсором.
- Авторизация: короткоживущий JWT access (15 мин) + ротируемый refresh (хранится хешем).
- Доступ: гард проверяет членство в семье, затем права на объект (документы — через `DocumentPermission`).

## Синхронизация
- `POST /sync/push` — пачка операций `{opId, entity, entityId, type: upsert|delete, baseVersion, payload}`; `opId` уникален (таблица `SyncOperation`) → повтор возвращает сохранённый результат (идемпотентность).
- `GET /sync/pull?cursor=` — изменения семьи, видимые пользователю, с маркерами удаления; курсор — монотонный серверный `seq` (bigint, общий по семье).
- Конфликты: last-accepted-write-wins по полям записи; при `baseVersion < version` сервер применяет операцию и возвращает актуальную запись; удаление приоритетнее правки (tombstone не воскрешается upsert-ом). Ограничение: нет пополевого merge.
- Отзыв доступа: сервер отдаёт tombstone-`DocumentAccessRevoked`; клиент удаляет локальную копию при следующем pull. Операция из очереди не может вернуть доступ — права проверяются сервером заново.
- WebSocket `/ws` — события `{type:"changed", cursor}`; клиент в ответ делает pull. После реконнекта всегда pull.

## Допущения
1. Одна семья на пользователя (v1).
2. Серверное шифрование на стороне инфраструктуры (SSE S3, шифрование диска Postgres); не end-to-end.
3. Повторяющиеся дела: `TaskSeries` (шаблон + правило) + материализованные `TaskOccurrence` на окно вперёд (60 дней), продлеваются при pull/по cron. Правка occurrence меняет только его; правка серии — отдельный endpoint.
4. Premium — только по серверной записи `Subscription` на семью. В dev без ключей Apple — режим `BILLING_MODE=sandbox-mock` (выключен в production на уровне валидации env).
5. Dev-коды входа: Mailpit по SMTP; production не включает dev-эндпоинты (проверка `NODE_ENV`).
6. Тесты backend — Jest + `embedded-postgres` (Docker не нужен).
7. Интеграции, требующие ваших ключей: APNs (.p8), App Store Connect (Issuer/Key), реальный SMTP, прод S3, Apple Developer аккаунт для запуска на устройстве и StoreKit в production.

## Этапы
1. Вход и семья → 2. Покупки → 3. Дела → 4. Документы → 5. Синхронизация (сквозная, закладывается с этапа 1) → 6. Подписки → 7. Визуальная проверка.
