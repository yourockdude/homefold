#!/usr/bin/env bash
# Сквозная проверка живого API (нужны Mailpit :8025, API :3000 и засеянная БД). Требует curl и jq.
set -euo pipefail
API=${API:-http://localhost:3000}
MAILPIT=${MAILPIT:-http://localhost:8025}
EMAIL=${1:-anna@smirnovy.example}

step() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
uuid() { uuidgen | tr 'A-Z' 'a-z'; }

step "1. Запрос кода на $EMAIL"
curl -fsS -X POST "$API/auth/request-code" -H 'content-type: application/json' -d "{\"email\":\"$EMAIL\"}"; echo
sleep 1
CODE=$(curl -fsS "$MAILPIT/api/v1/search?query=to:$EMAIL" | jq -r '.messages[0].Snippet' | grep -oE '[0-9]{6}' | head -1)
echo "код получен из Mailpit (не печатаем)"; [ -n "$CODE" ]

step "2. Подтверждение кода (неверный → 401, верный → токены)"
curl -s -o /dev/null -w 'неверный код: HTTP %{http_code}\n' -X POST "$API/auth/verify" -H 'content-type: application/json' -d "{\"email\":\"$EMAIL\",\"code\":\"000000\"}"
TOKENS=$(curl -fsS -X POST "$API/auth/verify" -H 'content-type: application/json' -d "{\"email\":\"$EMAIL\",\"code\":\"$CODE\"}")
TOKEN=$(echo "$TOKENS" | jq -r .accessToken)
H=(-H "Authorization: Bearer $TOKEN" -H 'content-type: application/json')

step "3. Семья"
curl -fsS "$API/families/me" "${H[@]}" | jq '{name, myRole, members: [.members[] | {displayName, role}], premium: .plan.premium}'

step "4. Покупки"
curl -fsS "$API/shopping/lists" "${H[@]}" | jq '.items[0] | {name, total: (.items|length), notBought: ([.items[]|select(.purchased|not)]|length)}'

step "5. Дела"
curl -fsS "$API/tasks?today=$(date -u +%F)&from=$(date -u -v-2d +%F 2>/dev/null || date -u -d '-2 day' +%F)&to=$(date -u -v+2d +%F 2>/dev/null || date -u -d '+2 day' +%F)" "${H[@]}" | jq '[.items[] | {title, date, time, status, overdue}]'

step "6. Документы (метаданные) и скачивание по короткоживущей ссылке"
DOCS=$(curl -fsS "$API/documents" "${H[@]}")
echo "$DOCS" | jq '[.items[] | {title, category, access, expiresAt}]'
DOC=$(echo "$DOCS" | jq -r '.items[0].id')
URL=$(curl -fsS "$API/documents/$DOC/download-url" "${H[@]}" | jq -r .url)
curl -fsS "$URL" | head -c 8; echo " ← первые байты файла"

step "7. Идемпотентный push: одна операция дважды → один и тот же результат, одна запись"
LIST=$(curl -fsS "$API/shopping/lists" "${H[@]}" | jq -r '.items[0].id'); ITEM=$(uuid); OP=$(uuid)
BODY="{\"operations\":[{\"opId\":\"$OP\",\"entity\":\"shoppingItem\",\"entityId\":\"$ITEM\",\"type\":\"upsert\",\"payload\":{\"listId\":\"$LIST\",\"name\":\"Сыр\",\"quantity\":1,\"unit\":\"шт\",\"category\":\"Молочное\"}}]}"
A=$(curl -fsS -X POST "$API/sync/push" "${H[@]}" -d "$BODY" | jq -c '.results[0]|{status,version:.record.version}')
B=$(curl -fsS -X POST "$API/sync/push" "${H[@]}" -d "$BODY" | jq -c '.results[0]|{status,version:.record.version}')
echo "1-й: $A / 2-й: $B"; [ "$A" = "$B" ]
echo "товаров «Сыр» в списке: $(curl -fsS "$API/shopping/lists/$LIST" "${H[@]}" | jq '[.items[]|select(.name=="Сыр")]|length')"

step "8. Pull по курсору"
CUR=$(curl -fsS "$API/sync/pull?limit=1000" "${H[@]}" | jq -r .cursor)
curl -fsS -X POST "$API/sync/push" "${H[@]}" -d "{\"operations\":[{\"opId\":\"$(uuid)\",\"entity\":\"shoppingItem\",\"entityId\":\"$ITEM\",\"type\":\"delete\"}]}" >/dev/null
curl -fsS "$API/sync/pull?cursor=$CUR" "${H[@]}" | jq -c '{cursor, changes:[.changes[]|{entity,deleted}]}'

step "9. Тариф и лимиты"
curl -fsS "$API/billing/status" "${H[@]}" | jq '{premium, limits}'

step "10. Выход"
curl -s -o /dev/null -w 'logout: HTTP %{http_code}\n' -X POST "$API/auth/logout" "${H[@]}"
curl -s -o /dev/null -w 'после выхода /me: HTTP %{http_code}\n' "$API/me" "${H[@]}"
printf '\n\033[32mOK\033[0m\n'
