# API HomeFold — контракт для iOS

Полная схема: `backend/openapi.json` (OpenAPI 3), живая документация — `GET /docs`.
Базовый URL в dev: `http://localhost:3000`. В production — только HTTPS.

## Общие правила
- Авторизация: `Authorization: Bearer <accessToken>` (JWT, 15 мин). Обновление — `POST /auth/refresh` (refresh ротируется; повторное использование старого отзывает сессию).
- Ошибки — всегда `{ "error": { "code": "...", "message": "по-русски", "details"?: ... } }`. Ключевые коды:
  `VALIDATION_ERROR 400`, `UNAUTHORIZED/TOKEN_INVALID 401`, `NO_FAMILY/FORBIDDEN 403`, `NOT_FOUND 404`, `ENTITY_DELETED/LAST_ADMIN/ALREADY_IN_FAMILY/SUBSCRIPTION_BOUND_TO_OTHER_FAMILY 409`, `INVITATION_INVALID 410`, `PREMIUM_REQUIRED 402` (`details.feature`: `members | multiple_lists | recurring_tasks | documents`), `RATE_LIMITED/RESEND_TOO_SOON/TOO_MANY_CODES/CODE_ATTEMPTS_EXCEEDED 429`, `CODE_INVALID/CODE_EXPIRED 401`.
- Идентификаторы синхронизируемых записей создаёт **клиент** (UUID). `PUT /…/{id}` — upsert: повтор запроса не создаёт дубликат.
- Пагинация — курсорная: `?limit=&cursor=` → `{ items, nextCursor }`.
- Даты календарные — строки `YYYY-MM-DD` (локальные даты семьи), время — `HH:mm`; моменты — ISO-8601 UTC.

## Поля синхронизируемых сущностей
Каждая запись (`shoppingList`, `shoppingItem`, `taskSeries`, `taskOccurrence`, `checklistItem`, `document`) содержит:
`id`, `familyId`, `authorId`, `createdAt`, `updatedAt`, `version` (растёт на каждую серверную правку), `deletedAt` (маркер удаления, `null` у живых).

| Сущность | Основные поля |
|---|---|
| shoppingList | `name`, `status` (`active`/`archived`), `archivedAt` |
| shoppingItem | `listId`, `name`, `quantity`, `unit`, `category`, `assigneeId` (`null` = «Любой»), `note`, `purchased`, `purchasedById`, `purchasedAt` |
| taskOccurrence | `seriesId?`, `originalDate?`, `overridden`, `title`, `assigneeId`, `date`, `time?`, `timezone`, `place`, `note`, `reminderMinutes` (по умолчанию 30, `null` — нет), `status` (`open`/`done`), `completedById`, `completedAt`; в `GET /tasks` ещё `checklist[]`, `overdue` |
| taskSeries | `title`, `assigneeId`, `startDate`, `time`, `timezone`, `place`, `note`, `repeat` (`daily`/`weekly`/`monthly`), `reminderMinutes`, `checklist` (шаблон — строки) |
| checklistItem | `occurrenceId`, `title`, `done`, `position` |
| document | `title`, `category` (`personal/health/home/travel`), `ownerId` (чей документ), `number`, `expiresAt`, `access` (`author_only/selected/family`), `selectedUserIds[]`, `fileName`, `mimeType`, `sizeBytes`, `status` (`pending_upload/ready`) |

## Вход
1. `POST /auth/request-code {email}` → `{expiresInSeconds: 600, resendAfterSeconds: 60}`; раньше таймера → `429 RESEND_TOO_SOON {details.retryAfterSeconds}`; не больше 5 кодов в час.
2. `POST /auth/verify {email, code, deviceName?}` → `{accessToken, refreshToken, expiresInSeconds, user}`; 5 попыток на код.
3. `GET /me` → `{user, family|null}`. Без семьи доступны только `/me`, `/families` (POST), `/invitations/accept`, `/invitations/preview`, `/auth/*`, `/account`, `/devices`, `/settings`.
4. `POST /auth/logout` (204).

## Семья
`POST /families {name, displayName}` · `GET /families/me` (участники, роль, `plan`) · `PATCH /families/me {name}` (admin) · `PATCH /families/me/members/{userId} {displayName?, role?, color?}` · `DELETE /families/me/members/{userId}` (admin) · `POST /families/me/leave` · `DELETE /account`.
Единственный админ не может выйти/сняться/удалить аккаунт, пока есть другие участники → `409 LAST_ADMIN`.

Приглашения: `POST /invitations` (admin) → `{id, token, url, expiresAt}` (токен виден один раз, действует 7 дней, одноразовый) · `GET /invitations` · `DELETE /invitations/{id}` (отзыв) · `GET /invitations/preview?token=` (без авторизации → `{familyName, invitedBy, expiresAt}`) · `POST /invitations/accept {token, displayName}`.

## Покупки
`GET /shopping/lists?status=active|archived` (со вложенными `items`; для архива на free — `historyLimitDays: 30`, `hiddenByPlan: N`) · `PUT /shopping/lists/{id}` · `DELETE …` · `POST /shopping/lists/new {id, name?}` («Начать новый список»: активные → архив) · `PUT /shopping/items/{id}` (`listId` и `name` обязательны при создании) · `DELETE /shopping/items/{id}`.

## Дела
`GET /tasks?from=&to=&assigneeId=&status=&today=` · `GET /tasks/occurrences/{id}` · `PUT /tasks/occurrences/{id}` (**разовое дело или правка только этого выполнения**) · `POST …/complete|reopen` · `POST …/postpone {date, time?}` · `DELETE …`
`PUT /tasks/checklist/{id}` / `DELETE`.
Серии (**явное изменение всей серии**, Premium): `GET /tasks/series` · `PUT /tasks/series/{id}` · `DELETE /tasks/series/{id}`. Сервер материализует выполнения серии на 60 дней вперёд (id выполнений выдаёт сервер — клиент получает их через pull). Правка серии не трогает выполненные и правленные вручную выполнения.

## Документы
1. `POST /documents {id, title, fileName, mimeType, sizeBytes, category?, ownerId?, number?, expiresAt?, access?, selectedUserIds?}` → `{document, upload: {url, method:"PUT", headers, expiresInSeconds}}` (идемпотентно по `id`).
2. `PUT <upload.url>` с телом файла и `upload.headers` — **напрямую в хранилище**, не через API.
3. `POST /documents/{id}/confirm` → сервер проверяет размер (= заявленному), сигнатуру PDF/JPEG/PNG; `409 UPLOAD_INCOMPLETE`, `422 UPLOAD_SIZE_MISMATCH|UPLOAD_TYPE_MISMATCH`. До подтверждения документ видит только автор.
Повтор загрузки: `POST /documents/{id}/upload-url` → новая ссылка. Незавершённые загрузки старше 24 ч удаляются.
`GET /documents?category=&q=&limit=&cursor=` · `GET /documents/{id}` · `GET /documents/{id}/download-url` (ссылка живёт 120 с) · `PATCH /documents/{id}` · `DELETE /documents/{id}` · `GET /documents/usage`.
Менять/удалять документ может только автор; видимость — по `access`. Админ не видит чужие `author_only`.

## Синхронизация
- `POST /sync/push {operations:[{opId, entity, entityId, type:"upsert"|"delete", baseVersion?, payload?}]}` (≤100 операций, применяются по порядку) → `{results:[{opId, status:"applied"|"rejected", conflict, record, error?}]}`.
  - Повтор того же `opId` возвращает **тот же результат** без повторного применения (идемпотентность, переживает перезапуск сервера).
  - `payload` — те же поля, что у REST `PUT`/`PATCH` (частичные).
  - `baseVersion < version` → правка всё равно применяется (last-accepted-write-wins по полям), `conflict: true`, в `record` — актуальная запись.
  - Правка удалённой записи → `rejected`, `error.code = ENTITY_DELETED`, `record` с `deletedAt` (**удаление приоритетнее**). Операция над недоступным документом → `rejected NOT_FOUND` (доступ из очереди не восстановить).
  - Документы через push: только изменение метаданных/доступа и удаление (создание — через REST из-за загрузки файла).
- `GET /sync/pull?cursor=0&limit=200` → `{changes:[{entity, id, deleted, revoked?, record}], cursor, hasMore, serverTime}`. Сохраняйте `cursor` после каждой страницы; повторяйте, пока `hasMore`. `deleted: true` — удалить локально; `revoked: true` — доступ закрыт, **очистить локальную копию файла**. `entity: "family"` без `record` — перечитать `GET /families/me` (состав/тариф изменились).
- WebSocket: `wss://…/ws?token=<accessToken>` → сообщения `{"type":"ready"}` и `{"type":"changed","cursor":"123"}`. Это только сигнал: по нему и после каждого реконнекта вызывайте `/sync/pull`. Исключённого участника сервер отключает (код 4001).

## Уведомления и настройки
`PUT /devices {token, environment: "sandbox"|"production"}` (hex-токен APNs) · `DELETE /devices/{token}` · `GET|PUT /settings {taskReminders, shoppingPush, quietHoursEnabled, quietStart, quietEnd, timezone, documentsProtection}`.
Push уходят при назначении дела/покупки другому участнику; без содержимого документов.

## Подписки
`GET /billing/status` → `{premium, limits, maxFileBytes, subscription}` (всегда считается на сервере) · `POST /billing/verify {signedTransaction}` (JWS StoreKit 2) · `POST /billing/restore {signedTransactions[]}` · `POST /billing/apple-notifications {signedPayload}` (вебхук Apple, без токена, подпись проверяется).
Лимиты: free — 3 участника, 1 активный список, 10 файлов/100 МБ, история 30 дней, без повторов; Plus — 8 участников, списки без ограничений, 10 ГБ, вся история, повторы. Файл ≤ 25 МБ на обоих.
Dev (`BILLING_MODE=sandbox-mock`, не в production): `POST /billing/dev/mock-purchase`, `POST /billing/dev/mock-expire`.
