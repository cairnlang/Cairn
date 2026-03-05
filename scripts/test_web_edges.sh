#!/usr/bin/env bash
set -euo pipefail

echo "web-edge: running login/session/mutation/invalid-input checks"

echo "[1/1] mix test --only web_edge test/cairn/http_test.exs"
mix test --only web_edge test/cairn/http_test.exs

echo "web-edge: success"
