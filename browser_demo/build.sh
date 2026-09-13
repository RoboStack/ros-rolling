#!/usr/bin/env bash
set -eo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$DEMO_DIR/../demo_env"
BUILD_ENV=/private/tmp/zenoh-emsdk-env

mkdir -p "$DEMO_DIR/out"

# No pthreads (see build_ament_cmake.sh.in for the full rationale) -- rclcpp's
# default executor (rclcpp::spin -> Executor::wait_for_work) doesn't have any
# blocking primitive of its own; it delegates entirely to rcl_wait ->
# rmw_wait, same as rclc/rclpy, which is patched to poll instead of block
# (see the rmw_zenoh_pico patch). Asyncify is what lets that poll loop
# cooperatively yield. MAIN_MODULE+dlopen is how the final executable pulls
# in all the separately-built SIDE_MODULE .so packages at runtime.
LIBS=(
  "$PREFIX/lib/librclcpp.so"
  "$PREFIX/lib/librcl.so"
  "$PREFIX/lib/librcl_yaml_param_parser.so"
  "$PREFIX/lib/librcl_logging_interface.so"
  "$PREFIX/lib/librmw.so"
  "$PREFIX/lib/librmw_zenoh_pico.so"
  "$PREFIX/lib/libzenohpico.so"
  "$PREFIX/lib/librosidl_runtime_c.so"
  "$PREFIX/lib/librosidl_typesupport_microxrcedds_c.so"
  "$PREFIX/lib/librcutils.so"
  "$PREFIX/lib/librcpputils.so"
  "$PREFIX/lib/liblibstatistics_collector.so"
  "$PREFIX/lib/libstd_msgs__rosidl_generator_c.so"
  "$PREFIX/lib/libstd_msgs__rosidl_typesupport_c.so"
  "$PREFIX/lib/libstd_msgs__rosidl_typesupport_cpp.so"
  "$PREFIX/lib/libstd_msgs__rosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/libstd_msgs__rosidl_typesupport_introspection_cpp.so"
  "$PREFIX/lib/librosidl_typesupport_cpp.so"
  "$PREFIX/lib/librosidl_typesupport_introspection_cpp.so"
  "$PREFIX/lib/librosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/librcl_interfaces__rosidl_generator_c.so"
  "$PREFIX/lib/librcl_interfaces__rosidl_typesupport_c.so"
  "$PREFIX/lib/librcl_interfaces__rosidl_typesupport_cpp.so"
  "$PREFIX/lib/librcl_interfaces__rosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/librcl_interfaces__rosidl_typesupport_introspection_cpp.so"
  "$PREFIX/lib/librosgraph_msgs__rosidl_generator_c.so"
  "$PREFIX/lib/librosgraph_msgs__rosidl_typesupport_c.so"
  "$PREFIX/lib/librosgraph_msgs__rosidl_typesupport_cpp.so"
  "$PREFIX/lib/librosgraph_msgs__rosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/librosgraph_msgs__rosidl_typesupport_introspection_cpp.so"
  "$PREFIX/lib/libbuiltin_interfaces__rosidl_generator_c.so"
  "$PREFIX/lib/libbuiltin_interfaces__rosidl_typesupport_c.so"
  "$PREFIX/lib/libbuiltin_interfaces__rosidl_typesupport_cpp.so"
  "$PREFIX/lib/libbuiltin_interfaces__rosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/libbuiltin_interfaces__rosidl_typesupport_introspection_cpp.so"
  "$PREFIX/lib/libservice_msgs__rosidl_generator_c.so"
  "$PREFIX/lib/libservice_msgs__rosidl_typesupport_c.so"
  "$PREFIX/lib/libservice_msgs__rosidl_typesupport_cpp.so"
  "$PREFIX/lib/libservice_msgs__rosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/libservice_msgs__rosidl_typesupport_introspection_cpp.so"
  "$PREFIX/lib/libtype_description_interfaces__rosidl_generator_c.so"
  "$PREFIX/lib/libtype_description_interfaces__rosidl_typesupport_c.so"
  "$PREFIX/lib/libtype_description_interfaces__rosidl_typesupport_cpp.so"
  "$PREFIX/lib/libtype_description_interfaces__rosidl_typesupport_introspection_c.so"
  "$PREFIX/lib/libtype_description_interfaces__rosidl_typesupport_introspection_cpp.so"
  "$PREFIX/microcdr-2.0.2/lib/libmicrocdr.so"
)

INCLUDE_FLAGS=(-I"$PREFIX/include")
for d in "$PREFIX"/include/*/; do
  INCLUDE_FLAGS+=(-I"${d%/}")
done

# The emscripten-forge toolchain env's own activation script sets
# EMCC_CFLAGS="$EM_FORGE_CFLAGS_BASE -sSUPPORT_LONGJMP=wasm -fwasm-exceptions"
# globally -- every em++ invocation gets native wasm exception-handling by
# default, which crashes binaryen's Asyncify pass outright ("UNREACHABLE
# executed ... Asyncify.cpp"), not just compiles slower. Override it here to
# drop just the exception-handling part (matching EM_FORGE_CFLAGS_BASE's own
# value, from that same activation script) -- see build_ament_cmake.sh.in
# for the same fix applied to the vinca-driven package builds.
micromamba run -p "$BUILD_ENV" env EMCC_CFLAGS="-O2 -g0 -fPIC -msimd128" em++ \
  -std=c++17 \
  -DZENOH_EMSCRIPTEN -DRMW_IMPLEMENTATION=rmw_zenoh_pico \
  "${INCLUDE_FLAGS[@]}" \
  -sMAIN_MODULE=1 \
  -s ASSERTIONS=1 \
  -fexceptions \
  -sWASM_BIGINT \
  -sASYNCIFY -s ASYNCIFY_STACK_SIZE=24576 \
  -s ALLOW_MEMORY_GROWTH=1 \
  -L"$PREFIX/lib" \
  -L"$PREFIX/microcdr-2.0.2/lib" \
  "$DEMO_DIR/talker.cpp" \
  "${LIBS[@]}" \
  -o "$DEMO_DIR/out/talker.js"

echo "Build finished: $DEMO_DIR/out/talker.js / talker.wasm"
