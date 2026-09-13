#!/usr/bin/env bash
set -eo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$DEMO_DIR/../demo_env"
BUILD_ENV=/private/tmp/zenoh-emsdk-env
mkdir -p "$DEMO_DIR/out"

# See build.sh's comment on EMCC_CFLAGS / -fwasm-exceptions vs Asyncify.
micromamba run -p "$BUILD_ENV" env EMCC_CFLAGS="-O2 -g0 -fPIC -msimd128" em++ \
  -std=c11 -x c \
  -I"$PREFIX/include/python3.13" \
  -sMAIN_MODULE=1 \
  -s ASSERTIONS=1 \
  -sWASM_BIGINT \
  -sASYNCIFY -s ASYNCIFY_STACK_SIZE=24576 \
  -s ALLOW_MEMORY_GROWTH=1 \
  --embed-file "$PREFIX/lib/python3.13@/pyhome/lib/python3.13" \
  -L"$PREFIX/lib" \
  "$DEMO_DIR/pytest_boot.c" \
  -lpython3.13 \
  -o "$DEMO_DIR/out/pytest_boot.js"

echo "Build finished: $DEMO_DIR/out/pytest_boot.js"
