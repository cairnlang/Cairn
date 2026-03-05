#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_cmd curl
if [[ ! -x ./cairn ]]; then
  echo "error: ./cairn executable not found" >&2
  exit 1
fi

PORT="${1:-8133}"
TMP_SOURCE="$(mktemp /tmp/runewarden-ch23-mnesia-XXXX.txt)"
COOKIE_JAR="$(mktemp /tmp/runewarden-ch23-mnesia-cookies-XXXX.txt)"
cp "$SEED" "$TMP_SOURCE"

cleanup() {
  if [[ -n "${PID:-}" ]]; then
    kill "$PID" >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
  rm -f "$TMP_SOURCE" "$COOKIE_JAR"
}
trap cleanup EXIT

start_server "$TMP_SOURCE" "$PORT" env
PID="$STARTED_PID"
wait_for_health "$PORT"

echo "[mnesia] unauthorized add rejected"
unauth_resp="$(curl -sS -i -X POST -d 'kind=gas_leak&magnitude=5' "http://127.0.0.1:${PORT}/add")"
assert_status "$unauth_resp" "200"
assert_contains "$unauth_resp" "<h1>Unauthorized</h1>"

echo "[mnesia] watch login sees seeded incidents"
login_watch="$(curl -sS -i -c "$COOKIE_JAR" -X POST -d 'username=warden&password=ironhold' "http://127.0.0.1:${PORT}/login")"
assert_status "$login_watch" "200"
assert_contains "$login_watch" "incidents: 3"

echo "[mnesia] add incident updates report"
add_resp="$(curl -sS -i -b "$COOKIE_JAR" -X POST -d 'kind=gas_leak&magnitude=5' "http://127.0.0.1:${PORT}/add")"
assert_status "$add_resp" "200"
assert_contains "$add_resp" "incidents: 4"

echo "[mnesia] restart keeps persisted state"
kill "$PID" >/dev/null 2>&1 || true
wait "$PID" >/dev/null 2>&1 || true
unset PID

start_server "$TMP_SOURCE" "$PORT" env
PID="$STARTED_PID"
wait_for_health "$PORT"
login_admin="$(curl -sS -i -X POST -d 'username=thane&password=anvil' "http://127.0.0.1:${PORT}/login")"
assert_status "$login_admin" "200"
assert_contains "$login_admin" "incidents: 4"

echo "[mnesia] smoke checks passed"
