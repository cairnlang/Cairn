#!/usr/bin/env bash
set -euo pipefail

ROOT="book/code/runewarden/chapters/ch11_assurance_workflow"

echo "[1/3] native tests"
./cairn --test "$ROOT/test.crn"

echo "[2/3] property checks"
./cairn "$ROOT/verify.crn"

echo "[3/3] proofs"
./cairn "$ROOT/prove.crn"
