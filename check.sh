#!/usr/bin/env bash
# Checa o orderbook publico do Mercado Bitcoin e avisa no Telegram quando o estado muda.
# "up" so com HTTP 200 E o campo "asks" no JSON; erro, bloqueio ou timeout contam como "down".
set -u

URL="${MB_URL:-https://api.mercadobitcoin.net/api/v4/USDC-BRL/orderbook}"
STATE_FILE="${STATE_FILE:-state/api.state}"
FAILS_TO_DOWN=2

body=$(mktemp)
code=$(curl -sS -m 20 -o "$body" -w '%{http_code}' "$URL" 2>/dev/null) || code=000
if [ "$code" = 200 ] && grep -q '"asks"' "$body"; then now=up; else now=down; fi
rm -f "$body"

prev=none; fails=0
[ -f "$STATE_FILE" ] && read -r prev fails < "$STATE_FILE"

# Primeira falha depois de "up" ainda nao derruba: so declara down apos FAILS_TO_DOWN seguidas.
if [ "$now" = up ]; then
  new=up; fails=0
else
  fails=$((fails + 1)); [ "$fails" -gt "$FAILS_TO_DOWN" ] && fails=$FAILS_TO_DOWN
  if [ "$prev" = up ] && [ "$fails" -lt "$FAILS_TO_DOWN" ]; then new=up; else new=down; fi
fi

send() {
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -sS -m 20 -o /dev/null \
      --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=$1" \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
  else
    echo "(dry-run, sem Telegram) $1"
  fi
}

if [ "$prev" = none ]; then
  send "Monitor da API do Mercado Bitcoin ativo. Estado atual: ${new} (HTTP ${code})."
elif [ "$new" != "$prev" ]; then
  if [ "$new" = up ]; then
    send "API do Mercado Bitcoin VOLTOU (HTTP 200, orderbook ok). Isso nao prova que os saques voltaram: confira antes de religar."
  else
    send "API do Mercado Bitcoin FORA (HTTP ${code})."
  fi
fi

mkdir -p "$(dirname "$STATE_FILE")"
echo "$new $fails" > "$STATE_FILE"
echo "http=${code} now=${now} estado=${new} (antes: ${prev})"
