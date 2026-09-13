#!/usr/bin/env bash
set -eo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ENV=/private/tmp/zenoh-emsdk-env
mkdir -p "$DEMO_DIR/out"

# See build.sh's comment on EMCC_CFLAGS / -fwasm-exceptions vs Asyncify.
micromamba run -p "$BUILD_ENV" env EMCC_CFLAGS="-O2 -g0 -fPIC -msimd128" em++ \
  -std=c11 -x c \
  -s ASSERTIONS=1 \
  -sWASM_BIGINT \
  -sASYNCIFY -s ASYNCIFY_STACK_SIZE=24576 \
  -s ALLOW_MEMORY_GROWTH=1 \
  -sSOCKET_DEBUG=1 \
  "$DEMO_DIR/nettest.c" \
  -o "$DEMO_DIR/out/nettest.js"

echo "Build finished: $DEMO_DIR/out/nettest.js"
