#!/usr/bin/env bash
set -euo pipefail

ROOT="book/code/runewarden/chapters/ch23_operational_testing"
MAIN="$ROOT/main.crn"
SEED="$ROOT/data/shift_day_013.txt"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command '$1'" >&2
    exit 1
  fi
}

wait_for_health() {
  local port="$1"
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  echo "error: server not healthy on port ${port}" >&2
  return 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "assertion failed: expected response to contain: $needle" >&2
    return 1
  fi
}

assert_status() {
  local response="$1"
  local code="$2"
  assert_contains "$response" "HTTP/1.1 ${code}"
}

start_server() {
  local source_path="$1"
  local port="$2"
  shift 2
  "$@" ./cairn "$MAIN" "$source_path" "$port" >/tmp/ch23_server_${port}.log 2>&1 &
  STARTED_PID="$!"
}
