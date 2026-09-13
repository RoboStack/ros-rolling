#!/usr/bin/env bash
set -eo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$DEMO_DIR/../demo_env"
BUILD_ENV=/private/tmp/zenoh-emsdk-env

mkdir -p "$DEMO_DIR/out"

LIBS=(
  "$PREFIX/lib/librclc.so"
  "$PREFIX/lib/librcl.so"
  "$PREFIX/lib/librcl_yaml_param_parser.so"
  "$PREFIX/lib/librcl_logging_interface.so"
  "$PREFIX/lib/librmw.so"
  "$PREFIX/lib/librmw_zenoh_pico.so"
  "$PREFIX/lib/libzenohpico.so"
  "$PREFIX/lib/librosidl_runtime_c.so"
  "$PREFIX/lib/librosidl_typesupport_microxrcedds_c.so"
  "$PREFIX/lib/librcutils.so"
  "$PREFIX/lib/liblibstatistics_collector.so"
  "$PREFIX/lib/libstd_msgs__rosidl_generator_c.so"
  "$PREFIX/lib/libstd_msgs__rosidl_typesupport_c.so"
  "$PREFIX/lib/libstd_msgs__rosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/libstd_msgs__rosidl_typesupport_microxrcedds_c.so"
  "$PREFIX/lib/libbuiltin_interfaces__rosidl_typesupport_microxrcedds_c.so"
  "$PREFIX/microcdr-2.0.2/lib/libmicrocdr.so"
)

INCLUDE_FLAGS=(-I"$PREFIX/include")
for d in "$PREFIX"/include/*/; do
  INCLUDE_FLAGS+=(-I"${d%/}")
done

# See build.sh's comment: the toolchain env's own activation script injects
# -fwasm-exceptions into every em++ call via EMCC_CFLAGS, which crashes
# binaryen's Asyncify pass -- override it here even though this source is
# pure C, since the link step also processes the C++ .so's it links against.
micromamba run -p "$BUILD_ENV" env EMCC_CFLAGS="-O2 -g0 -fPIC -msimd128" em++ \
  -std=c11 -x c \
  -DZENOH_EMSCRIPTEN -DRMW_IMPLEMENTATION=rmw_zenoh_pico \
  "${INCLUDE_FLAGS[@]}" \
  -sMAIN_MODULE=2 \
  -s ASSERTIONS=1 \
  -fexceptions \
  -sWASM_BIGINT \
  -lwebsocket.js \
  -sSOCKET_DEBUG=1 \
  -sASYNCIFY -s ASYNCIFY_STACK_SIZE=24576 \
  -s ALLOW_MEMORY_GROWTH=1 \
  -L"$PREFIX/lib" \
  -L"$PREFIX/microcdr-2.0.2/lib" \
  "$DEMO_DIR/talker_rclc.c" \
  "$DEMO_DIR/wasm_link_stubs.c" \
  "${LIBS[@]}" \
  -o "$DEMO_DIR/out/talker_rclc.js"

echo "Build finished: $DEMO_DIR/out/talker_rclc.js / talker_rclc.wasm"
