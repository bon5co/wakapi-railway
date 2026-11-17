#!/bin/sh
# Railway entrypoint for Wakapi: validate secrets, create the administrator once, seed its API key, then start Wakapi
# on Railway's PORT with sign-up closed.
set -eu

fail() { echo "wakapi wrapper: $*" >&2; exit 1; }

: "${WAKAPI_PASSWORD_SALT:?set WAKAPI_PASSWORD_SALT}"
: "${WAKAPI_ADMIN_PASSWORD:?set WAKAPI_ADMIN_PASSWORD}"
: "${WAKAPI_API_KEY:?set WAKAPI_API_KEY}"
ADMIN_USER="${WAKAPI_ADMIN_USERNAME:-admin}"
DB="${WAKAPI_DB_NAME:-/data/wakapi.db}"
[ "${#WAKAPI_PASSWORD_SALT}" -ge 16 ] || fail "WAKAPI_PASSWORD_SALT must be at least 16 characters"
[ "${#WAKAPI_ADMIN_PASSWORD}" -ge 12 ] || fail "WAKAPI_ADMIN_PASSWORD must be at least 12 characters"
case "$WAKAPI_API_KEY" in *[!A-Za-z0-9-]*) fail "WAKAPI_API_KEY may only contain letters, digits and hyphens";; esac
[ "${#WAKAPI_API_KEY}" -ge 32 ] || fail "WAKAPI_API_KEY must be at least 32 characters"
case "$ADMIN_USER" in *[!A-Za-z0-9._-]*|current|"") fail "WAKAPI_ADMIN_USERNAME must be letters, digits, dot, dash or underscore, and not 'current'";; esac
mkdir -p "$(dirname "$DB")"

count_users() { [ -f "$DB" ] && sqlite3 "$DB" 'SELECT count(*) FROM users' 2>/dev/null || echo 0; }

if [ "$(count_users)" = "0" ]; then
  # First boot: start Wakapi on loopback only, with sign-up open for this one request, and register the administrator.
  # The first registered user is the administrator.
  echo "wakapi wrapper: creating administrator '$ADMIN_USER'"
  WAKAPI_ALLOW_SIGNUP=true WAKAPI_LISTEN_IPV4=127.0.0.1 WAKAPI_LISTEN_IPV6=- WAKAPI_PORT=3999 \
    WAKAPI_PUBLIC_URL=http://127.0.0.1:3999 WAKAPI_INSECURE_COOKIES=true /app/wakapi &
  PID=$!
  n=0
  until curl -fs -o /dev/null http://127.0.0.1:3999/api/health; do
    n=$((n+1)); [ "$n" -le 120 ] || { kill "$PID" 2>/dev/null || true; fail "bootstrap server did not become healthy"; }
    kill -0 "$PID" 2>/dev/null || fail "bootstrap server exited"
    sleep 1
  done
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:3999/signup \
    --data-urlencode "username=$ADMIN_USER" --data-urlencode "password=$WAKAPI_ADMIN_PASSWORD" \
    --data-urlencode "password_repeat=$WAKAPI_ADMIN_PASSWORD" --data-urlencode "location=UTC")
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  [ "$CODE" = "302" ] || fail "administrator sign-up answered $CODE, expected 302"
  [ "$(count_users)" = "1" ] || fail "administrator was not created"
fi

# Every boot: the administrator's API key is the variable's value (changing the variable rotates the key).
sqlite3 "$DB" "UPDATE users SET api_key='$WAKAPI_API_KEY' WHERE id='$ADMIN_USER'"
[ "$(sqlite3 "$DB" "SELECT count(*) FROM users WHERE id='$ADMIN_USER' AND api_key='$WAKAPI_API_KEY'")" = "1" ] \
  || fail "API key could not be set: no user '$ADMIN_USER' (was it renamed after the first boot?)"

export WAKAPI_LISTEN_IPV4=0.0.0.0 WAKAPI_LISTEN_IPV6="::" WAKAPI_PORT="${PORT:-3000}"
if [ -z "${WAKAPI_PUBLIC_URL:-}" ] && [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export WAKAPI_PUBLIC_URL="https://$RAILWAY_PUBLIC_DOMAIN"
fi
export WAKAPI_ALLOW_SIGNUP=false WAKAPI_INVITE_CODES=false
exec /app/wakapi
