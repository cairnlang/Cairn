#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_cmd curl
require_cmd docker

if [[ ! -x ./cairn ]]; then
  echo "error: ./cairn executable not found" >&2
  exit 1
fi

PORT="${1:-8133}"
PG_PORT="${CAIRN_PG_PORT:-55435}"
PG_DB="${CAIRN_PG_DATABASE:-cairn}"
PG_USER="${CAIRN_PG_USER:-postgres}"
PG_PASSWORD="${CAIRN_PG_PASSWORD:-postgres}"
PG_HOST="${CAIRN_PG_HOST:-127.0.0.1}"
PG_SSLMODE="${CAIRN_PG_SSLMODE:-disable}"
IMAGE="${CAIRN_PG_IMAGE:-postgres:16-alpine}"
CONTAINER="cairn-ch23-pg-${RANDOM}"

TMP_SOURCE="$(mktemp /tmp/runewarden-ch23-postgres-XXXX.txt)"
COOKIE_JAR="$(mktemp /tmp/runewarden-ch23-postgres-cookies-XXXX.txt)"
cp "$SEED" "$TMP_SOURCE"

cleanup() {
  if [[ -n "${PID:-}" ]]; then
    kill "$PID" >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -f "$TMP_SOURCE" "$COOKIE_JAR"
}
trap cleanup EXIT

echo "[postgres] starting ${IMAGE} on ${PG_HOST}:${PG_PORT}"
docker run -d --name "$CONTAINER" \
  -e "POSTGRES_DB=${PG_DB}" \
  -e "POSTGRES_USER=${PG_USER}" \
  -e "POSTGRES_PASSWORD=${PG_PASSWORD}" \
  -p "${PG_PORT}:5432" \
  "$IMAGE" >/dev/null

for _ in $(seq 1 80); do
  if docker exec "$CONTAINER" pg_isready -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

docker exec "$CONTAINER" pg_isready -U "$PG_USER" -d "$PG_DB" >/dev/null

run_with_pg_env=(
  env
  CAIRN_DATA_STORE_BACKEND=postgres
  CAIRN_PG_HOST="$PG_HOST"
  CAIRN_PG_PORT="$PG_PORT"
  CAIRN_PG_DATABASE="$PG_DB"
  CAIRN_PG_USER="$PG_USER"
  CAIRN_PG_PASSWORD="$PG_PASSWORD"
  CAIRN_PG_SSLMODE="$PG_SSLMODE"
)

start_server "$TMP_SOURCE" "$PORT" "${run_with_pg_env[@]}"
PID="$STARTED_PID"
wait_for_health "$PORT"

echo "[postgres] watch login sees seeded incidents"
login_watch="$(curl -sS -i -c "$COOKIE_JAR" -X POST -d 'username=warden&password=ironhold' "http://127.0.0.1:${PORT}/login")"
assert_status "$login_watch" "200"
assert_contains "$login_watch" "incidents: 3"

echo "[postgres] add incident updates report"
add_resp="$(curl -sS -i -b "$COOKIE_JAR" -X POST -d 'kind=gas_leak&magnitude=5' "http://127.0.0.1:${PORT}/add")"
assert_status "$add_resp" "200"
assert_contains "$add_resp" "incidents: 4"

echo "[postgres] restart keeps persisted state"
kill "$PID" >/dev/null 2>&1 || true
wait "$PID" >/dev/null 2>&1 || true
unset PID

start_server "$TMP_SOURCE" "$PORT" "${run_with_pg_env[@]}"
PID="$STARTED_PID"
wait_for_health "$PORT"
login_admin="$(curl -sS -i -X POST -d 'username=thane&password=anvil' "http://127.0.0.1:${PORT}/login")"
assert_status "$login_admin" "200"
assert_contains "$login_admin" "incidents: 4"

echo "[postgres] smoke checks passed"
