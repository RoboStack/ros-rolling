#!/usr/bin/env bash
set -eo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$DEMO_DIR/../demo_env"
PY="$PREFIX/python3.13"
SP="$PY/site-packages-rclpy"
BUILD_ENV=/private/tmp/zenoh-emsdk-env

mkdir -p "$DEMO_DIR/out"

LIBS=(
  "$PREFIX/lib/librclc.so"
  "$PREFIX/lib/librcl.so"
  "$PREFIX/lib/librcl_action.so"
  "$PREFIX/lib/librcl_lifecycle.so"
  "$PREFIX/lib/librcl_yaml_param_parser.so"
  "$PREFIX/lib/librcl_logging_interface.so"
  "$PREFIX/lib/librmw.so"
  "$PREFIX/lib/librmw_zenoh_pico.so"
  "$PREFIX/lib/libzenohpico.so"
  "$PREFIX/lib/librosidl_runtime_c.so"
  "$PREFIX/lib/librcpputils.so"
  "$PREFIX/lib/librcutils.so"
  "$PREFIX/lib/liblibstatistics_collector.so"
  "$PREFIX/lib/libstd_msgs__rosidl_generator_c.so"
  "$PREFIX/lib/libstd_msgs__rosidl_typesupport_c.so"
  "$PREFIX/lib/libstd_msgs__rosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/libstd_msgs__rosidl_typesupport_microxrcedds_c.so"
  "$PREFIX/lib/libbuiltin_interfaces__rosidl_generator_c.so"
  "$PREFIX/lib/libbuiltin_interfaces__rosidl_typesupport_c.so"
  "$PREFIX/lib/libbuiltin_interfaces__rosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/libbuiltin_interfaces__rosidl_typesupport_microxrcedds_c.so"
  "$PREFIX/lib/librcl_interfaces__rosidl_generator_c.so"
  "$PREFIX/lib/librcl_interfaces__rosidl_typesupport_c.so"
  "$PREFIX/lib/librcl_interfaces__rosidl_typesupport_microxrcedds_c.so"
  "$PREFIX/lib/librcl_interfaces__rosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/liblifecycle_msgs__rosidl_generator_c.so"
  "$PREFIX/lib/liblifecycle_msgs__rosidl_typesupport_c.so"
  "$PREFIX/lib/libtype_description_interfaces__rosidl_typesupport_microxrcedds_c.so"
  "$PREFIX/lib/libtype_description_interfaces__rosidl_typesupport_c.so"
  "$PREFIX/lib/libservice_msgs__rosidl_typesupport_microxrcedds_c.so"
  "$PREFIX/lib/libservice_msgs__rosidl_typesupport_c.so"
  "$PREFIX/microcdr-2.0.2/lib/libmicrocdr.so"
  "$SP/rclpy/_rclpy_pybind11.cpython-313-wasm32-emscripten.so"
  "$SP/rcl_interfaces/rcl_interfaces_s__rosidl_typesupport_c.so"
  "$SP/builtin_interfaces/builtin_interfaces_s__rosidl_typesupport_c.so"
  "$SP/std_msgs/std_msgs_s__rosidl_typesupport_c.so"
  "$SP/type_description_interfaces/type_description_interfaces_s__rosidl_typesupport_c.so"
  "$SP/service_msgs/service_msgs_s__rosidl_typesupport_c.so"
  "$SP/numpy/_core/_multiarray_umath.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/_core/_simd.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/linalg/_umath_linalg.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/linalg/lapack_lite.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/fft/_pocketfft_umath.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/random/_common.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/random/_bounded_integers.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/random/bit_generator.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/random/mtrand.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/random/_philox.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/random/_sfc64.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/random/_generator.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/random/_pcg64.cpython-313-wasm32-emscripten.so"
  "$SP/numpy/random/_mt19937.cpython-313-wasm32-emscripten.so"
)

INCLUDE_FLAGS=(-I"$PREFIX/include" -I"$PY/include/python3.13")
for d in "$PREFIX"/include/*/; do
  INCLUDE_FLAGS+=(-I"${d%/}")
done

# See build.sh's comment: the toolchain env's own activation script injects
# -fwasm-exceptions into every em++ call via EMCC_CFLAGS, which crashes
# binaryen's Asyncify pass -- override it here (this links CPython and
# rclpy's own C++ pybind11 extension, both Asyncify targets).
micromamba run -p "$BUILD_ENV" env EMCC_CFLAGS="-O2 -g0 -fPIC -msimd128" em++ \
  -std=c11 -x c \
  -DZENOH_EMSCRIPTEN -DRMW_IMPLEMENTATION=rmw_zenoh_pico \
  "${INCLUDE_FLAGS[@]}" \
  -sMAIN_MODULE=2 \
  -s ASSERTIONS=1 \
  -fexceptions \
  -sWASM_BIGINT \
  -s USE_ZLIB=1 -s USE_SQLITE3=1 -s USE_BZIP2=1 \
  -lwebsocket.js \
  -sASYNCIFY -s ASYNCIFY_STACK_SIZE=24576 \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s STACK_SIZE=5MB \
  -s INITIAL_MEMORY=67108864 -s MAXIMUM_MEMORY=1024MB \
  --embed-file "$PY/lib/python3.13@/pyhome/lib/python3.13" \
  --embed-file "$SP@/pyhome/site-packages" \
  --embed-file "$DEMO_DIR/talker_rclpy.py@/pyhome/talker_rclpy.py" \
  -L"$PY/lib" \
  -L"$PREFIX/lib" \
  -L"$PREFIX/microcdr-2.0.2/lib" \
  -Wl,--allow-multiple-definition \
  "$DEMO_DIR/rclpy_boot.c" \
  "$DEMO_DIR/wasm_link_stubs_rclpy.c" \
  -Wl,--start-group -lpython3.13 -lffi -llzma "${LIBS[@]}" -Wl,--end-group \
  -o "$DEMO_DIR/out/rclpy_boot.js"

echo "Build finished: $DEMO_DIR/out/rclpy_boot.js / rclpy_boot.wasm"

# Emscripten's MAIN_MODULE loader resolves each "needed" shared library by
# basename, relative to the deployed .js file's own directory -- not via the
# -L paths used at link time above. Every dylink dependency has to sit flat
# next to rclpy_boot.js, regardless of where it lived in demo_env/.
cp "$PREFIX"/lib/*.so "$DEMO_DIR/out/"
cp -L "$PREFIX"/microcdr-2.0.2/lib/*.so* "$DEMO_DIR/out/"
find "$SP" -iname "*.so" -exec cp {} "$DEMO_DIR/out/" \;
cp "$DEMO_DIR/index_rclpy.html" "$DEMO_DIR/out/index_rclpy.html"
echo "Deployed $(find "$DEMO_DIR/out" -iname '*.so' | wc -l | tr -d ' ') shared libraries to $DEMO_DIR/out/"
