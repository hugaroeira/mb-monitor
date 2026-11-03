#!/usr/bin/env bash
# Checa a pagina de login do Mercado Bitcoin. O Cloudflare pode bloquear o acesso automatizado,
# entao ha 3 estados: maint (200 + aviso de manutencao), open (200 sem o aviso) e blocked (qualquer outra coisa).
# Bloqueio e erro NUNCA contam como "voltou"; "open" so vale apos 2 checagens seguidas.
set -u

URL="${MB_LOGIN_URL:-https://www.mercadobitcoin.com.br/conta/login/}"
STATE_FILE="${STATE_FILE:-state/login.state}"
TEXT="Plataforma em manuten"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

body=$(mktemp)
code=$(curl -sS -m 25 -L -A "$UA" -H "Accept-Language: pt-BR,pt;q=0.9" -o "$body" -w '%{http_code}' "$URL" 2>/dev/null) || code=000
if [ "$code" != 200 ]; then now=blocked
elif grep -qi "$TEXT" "$body"; then now=maint
elif grep -qi "Attention Required\|Just a moment\|cf-chl" "$body"; then now=blocked
else now=open; fi
rm -f "$body"

prev=none; streak=0
[ -f "$STATE_FILE" ] && read -r prev streak < "$STATE_FILE"

if [ "$now" = open ]; then
  streak=$((streak + 1)); [ "$streak" -gt 2 ] && streak=2
  if [ "$prev" = none ] || [ "$streak" -ge 2 ]; then new=open; else new=$prev; fi
else
  streak=0; new=$now
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
  case "$new" in
    maint)   send "Monitor do login do MB ativo. Estado: em manutencao." ;;
    open)    send "Monitor do login do MB ativo. Estado: pagina sem aviso de manutencao (confirme a mao)." ;;
    blocked) send "Monitor do login do MB ativo, mas o acesso esta BLOQUEADO (HTTP ${code}): ele nao consegue ver a pagina, entao nao vai avisar." ;;
  esac
elif [ "$new" = open ] && [ "$prev" != open ]; then
  send "Login do MB: a pagina NAO mostra mais o aviso de manutencao. Abra e confirme a mao."
elif [ "$new" = maint ] && [ "$prev" = open ]; then
  send "Login do MB voltou a mostrar manutencao."
fi

mkdir -p "$(dirname "$STATE_FILE")"
echo "$new $streak" > "$STATE_FILE"
echo "http=${code} now=${now} estado=${new} (antes: ${prev})"
