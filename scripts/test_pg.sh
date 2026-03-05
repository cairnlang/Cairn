#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker is required for scripts/test_pg.sh" >&2
  exit 1
fi

IMAGE="${CAIRN_PG_IMAGE:-postgres:16-alpine}"
PORT="${CAIRN_PG_PORT:-55432}"
DATABASE="${CAIRN_PG_DATABASE:-cairn}"
USER_NAME="${CAIRN_PG_USER:-postgres}"
PASSWORD="${CAIRN_PG_PASSWORD:-postgres}"
HOST="${CAIRN_PG_HOST:-127.0.0.1}"
SSLMODE="${CAIRN_PG_SSLMODE:-disable}"
TIMEOUT_MS="${CAIRN_PG_TIMEOUT_MS:-5000}"
CONTAINER="cairn-pg-test-${RANDOM}"

cleanup() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "pg-test: starting ${IMAGE} as ${CONTAINER} on ${HOST}:${PORT}"
docker run -d --name "${CONTAINER}" \
  -e "POSTGRES_DB=${DATABASE}" \
  -e "POSTGRES_USER=${USER_NAME}" \
  -e "POSTGRES_PASSWORD=${PASSWORD}" \
  -p "${PORT}:5432" \
  "${IMAGE}" >/dev/null

echo "pg-test: waiting for postgres readiness"
for _ in $(seq 1 40); do
  if docker exec "${CONTAINER}" pg_isready -U "${USER_NAME}" -d "${DATABASE}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

if ! docker exec "${CONTAINER}" pg_isready -U "${USER_NAME}" -d "${DATABASE}" >/dev/null 2>&1; then
  echo "error: postgres did not become ready in time" >&2
  exit 1
fi

echo "pg-test: running gated Postgres integration coverage"
CAIRN_PG_TEST=1 \
CAIRN_DATA_STORE_BACKEND=postgres \
CAIRN_PG_HOST="${HOST}" \
CAIRN_PG_PORT="${PORT}" \
CAIRN_PG_DATABASE="${DATABASE}" \
CAIRN_PG_USER="${USER_NAME}" \
CAIRN_PG_PASSWORD="${PASSWORD}" \
CAIRN_PG_SSLMODE="${SSLMODE}" \
CAIRN_PG_TIMEOUT_MS="${TIMEOUT_MS}" \
mix test test/cairn/db_test.exs test/cairn/http_test.exs

echo "pg-test: success"
