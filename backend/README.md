# «рядом» — backend

NestJS 11 · TypeScript · Prisma 6 · PostgreSQL · S3-совместимое хранилище · Mailpit (dev-почта).
Контракт для iOS: [`../docs/API.md`](../docs/API.md), схема: [`openapi.json`](openapi.json), живая документация: `http://localhost:3000/docs`.

## Запуск

### Вариант А — Docker Compose (весь стек)
```bash
cd Ryadom
docker compose up --build        # postgres, minio (+bucket), mailpit, api; миграции применяются при старте
DATABASE_URL=postgresql://ryadom:ryadom@localhost:5432/ryadom npm --prefix backend run seed   # демо-семья Смирновых
```
API `http://localhost:3000` · Swagger `/docs` · Mailpit (письма с кодами) `http://localhost:8025` · MinIO-консоль `http://localhost:9001` (ryadom / ryadom-secret).

> Для **физического iPhone** задайте `PUBLIC_BASE_URL=http://<IP-Mac>:3000` и `S3_PUBLIC_ENDPOINT=http://<IP-Mac>:9000` (подписанные ссылки на файлы ведут напрямую в MinIO, устройство должно его видеть). Без HTTPS iOS потребует исключение ATS — только для dev.

### Вариант Б — без Docker
```bash
cd backend
npm install
cp .env.example .env
npm run dev:db        # PostgreSQL через embedded-postgres в .pgdata (порт 5432) + миграции; оставить работать
npm run seed          # демо-данные
npm run start:dev     # API на :3000
# почта: установите Mailpit (brew install mailpit; mailpit) или смотрите коды в логе SMTP-приёмника на :1025
```
Хранилище по умолчанию `STORAGE_DRIVER=local` (файлы в `backend/.storage`, «подписанные» ссылки — короткоживущие JWT на `/storage/*`). Это **только для разработки**: в production сервер с `local` не стартует.

### Вход в dev
Войдите как `anna@smirnovy.example` (админ), `mikhail@…` или `sonya@…`: запросите код, откройте Mailpit, возьмите 6 цифр. Dev-эндпоинта «прочитать код» в API **нет**.
Быстрая сквозная проверка живого API: `./scripts/smoke.sh` (curl+jq, читает код из Mailpit).

## Переменные окружения
Полный список с комментариями — [`.env.example`](.env.example). Секреты только из окружения.

| Группа | Переменные |
|---|---|
| Ядро | `DATABASE_URL`, `PORT`, `PUBLIC_BASE_URL`, `INVITE_BASE_URL`, `JWT_SECRET` (≥32 симв. в prod), `OTP_PEPPER` |
| Почта | `MAIL_TRANSPORT=smtp`, `SMTP_HOST/PORT/SECURE/USER/PASS`, `MAIL_FROM` |
| Хранилище | `STORAGE_DRIVER=local\|s3`, `S3_BUCKET/REGION/ENDPOINT/PUBLIC_ENDPOINT/ACCESS_KEY_ID/SECRET_ACCESS_KEY/FORCE_PATH_STYLE` |
| Подписки | `BILLING_MODE=apple\|sandbox-mock`, `APPLE_BUNDLE_ID`, `APPLE_PRODUCT_IDS`, `APPLE_ROOT_CA_PATHS`, `APPLE_IAP_KEY_ID/ISSUER_ID/PRIVATE_KEY` |
| Push | `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`, `APNS_PRIVATE_KEY`, `APNS_PRODUCTION` |

**Защита от dev-режимов в production** (`NODE_ENV=production`): сервер не стартует при `BILLING_MODE=sandbox-mock`, `MAIL_TRANSPORT=memory`, `STORAGE_DRIVER=local`, слабом `JWT_SECRET`/`OTP_PEPPER` или `PUBLIC_BASE_URL` без https; mock-эндпоинты биллинга отвечают 404.

## Настройка внешних сервисов (нужны ваши ключи)

**Почта.** Dev — Mailpit. Production — любой SMTP (Postmark, SES SMTP, Mailgun…): `SMTP_HOST/PORT/USER/PASS`, `SMTP_SECURE=true` для 465, `MAIL_FROM` с вашего домена (SPF/DKIM/DMARC настроить у провайдера).

**S3.** Создайте **приватный** бакет (Block Public Access), включите шифрование на стороне хранилища (SSE-S3 или SSE-KMS по умолчанию на бакете) и CORS не нужен (iOS не браузер). Создайте IAM-пользователя с правами `s3:PutObject/GetObject/DeleteObject/HeadObject` на этот бакет, задайте `S3_*`. Для Яндекс Object Storage / Cloudflare R2 / MinIO укажите `S3_ENDPOINT` и при необходимости `S3_FORCE_PATH_STYLE=true`. Ссылки на загрузку живут 15 минут, на скачивание — 2 минуты.
Шифрование — серверное (на стороне инфраструктуры), **не сквозное**: сервер/оператор хранилища технически способен прочитать файлы.

**APNs.** В Apple Developer → Keys создайте ключ с APNs, скачайте `.p8`. Задайте `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` (= bundle id), `APNS_PRIVATE_KEY` (содержимое `.p8`, переводы строк как `\n`), `APNS_PRODUCTION=true` для боевых токенов (токены `sandbox` помечаются приложением при регистрации в `PUT /devices`). Без этих значений push не отправляются, остальное работает. В push не попадает содержимое документов.

**App Store (подписки).**
1. В App Store Connect создайте группу подписок и продукты (`app.ryadom.plus.monthly`, `app.ryadom.plus.yearly` — или свои, тогда `APPLE_PRODUCT_IDS`).
2. `BILLING_MODE=apple`, `APPLE_BUNDLE_ID=<bundle id>`.
3. Корневой сертификат Apple Root CA G3 уже лежит в `certs/AppleRootCA-G3.pem` (отпечаток SHA-256 `63:34:3A:BF:…:91:79`, совпадает с опубликованным Apple); сервер проверяет цепочку x5c подписанных транзакций и уведомлений именно на него.
4. Для авторитетной сверки через App Store Server API: App Store Connect → Users and Access → Integrations → In-App Purchase → создайте ключ; задайте `APPLE_IAP_KEY_ID`, `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_PRIVATE_KEY` (.p8). Без них сервер полагается на проверенную подпись JWS.
5. Server Notifications V2: URL `https://<ваш-домен>/billing/apple-notifications` (отдельно для Production и Sandbox).
6. Локальное тестирование StoreKit в Xcode использует **свою** подпись (StoreKit Configuration) — сервер её отвергнет, так что для проверки на устройстве нужна Sandbox-среда App Store (тестовый Apple ID) или `BILLING_MODE=sandbox-mock`.

## Тесты
```bash
npm test      # Jest + supertest; PostgreSQL поднимается автоматически через embedded-postgres, Docker не нужен
```
98 сценариев, включая: вход (неверный/просроченный/повторный код, лимиты), изоляция семей, приглашения (отзыв, срок, одноразовость), права на документы и отзыв доступа, идемпотентность `sync/push` (в т.ч. «перезапуск» сервера), конфликт правка/удаление, повторяющиеся дела, лимиты free/Plus, проверка/восстановление подписки и уведомления Apple (на тестовой PKI с настоящей проверкой цепочки и подписи), WebSocket, S3-слой на фейковом S3.

## Миграции
`npx prisma migrate deploy` — применить; новая миграция из изменений `schema.prisma` без Docker: `npx ts-node scripts/make-migration.ts <имя>`.
OpenAPI: `npm run openapi` → `openapi.json`.

## Известные ограничения (v1)
- **Docker Compose не запускался на машине разработки** (Docker не установлен): проверены сам API на PostgreSQL, Mailpit, локальном хранилище и фейковом S3; сборка `Dockerfile` и связка MinIO не прогонялись.
- **Не проверено вживую** (нет ключей/аккаунтов): APNs, App Store Server API, реальная подпись Apple (проверка цепочки/подписи покрыта тестовой PKI), реальный S3/MinIO, боевой SMTP.
- Проверка JWS Apple не делает OCSP/CRL-проверку отзыва сертификатов и не проверяет специфичные OID листового сертификата.
- Конфликты — last-accepted-write-wins на уровне **полей** (изменённых в payload); две правки одного поля — побеждает принятая сервером позже. Пополевого слияния текста нет.
- Курсор pull — монотонный `seq` журнала. При одновременных транзакциях seq теоретически может быть закоммичен «не по порядку» и пропущен; на практике записи в журнал — одиночные авто-коммиты, а клиент перечитывает по сигналу. При необходимости — вернуть курсор с небольшим перекрытием (повторная доставка безвредна).
- Журнал изменений и tombstone не компактируются; `SyncOperation` не чистится по возрасту (нужен регулярный job).
- Cron-задачи (продление окна повторов, очистка загрузок) и rate limiting работают в памяти одного инстанса: при нескольких репликах нужны распределённый лок и общее хранилище лимитов.
- Файл в хранилище нельзя ограничить по размеру самой presigned-ссылкой PUT; размер/тип проверяются при `confirm`, несоответствующий объект удаляется, неподтверждённые — через 24 ч.
- Удаление аккаунта анонимизирует строку пользователя (записи семьи ссылаются на автора); семья из одного человека удаляется целиком, включая файлы.
- Выполнения повторяющихся дел хранятся как «настенные» дата/время + `timezone`; пересчёт напоминаний при смене часового пояса — на клиенте.
- Тихие часы учитываются только для push (по `timezone` из настроек); локальные напоминания — на устройстве.
- Один пользователь — одна семья; роль у участника одна (admin/member).
