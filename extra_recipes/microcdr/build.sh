#!/usr/bin/env bash
set -eo pipefail

# See extra_recipes/zenoh-pico/build.sh for why this is needed on
# cross-compiling conda-forge toolchains.
unset -f cmake || true

mkdir -p build
cd build

if [[ $target_platform =~ emscripten.* ]]; then
  # Building microcdr as a static archive (its own default) causes
  # "duplicate symbol" wasm-ld errors once two consumers both link against
  # it in the same final module (confirmed with rmw_zenoh_pico, which
  # links microcdr directly AND transitively via
  # rosidl_typesupport_microxrcedds_c's exported libraries, 2026-09-09) --
  # wasm-ld treats the same static archive appearing twice on the link
  # line as a hard error, unlike a normal linker. Build a real dynamically
  # linked SIDE_MODULE .so instead, same fix as zenoh-pico's own build.sh.
  # No real pthreads, and (as of 2026-09-13) no Asyncify either -- see
  # vinca's build_ament_cmake.sh.in for the full rationale (Asyncify +
  # runtime dlopen() of a SIDE_MODULE hits a real, unresolved
  # Emscripten/Binaryen limitation). This package's own build.sh sets its
  # shared-module flags directly (bypassing vinca's template, since it's
  # a hand-written extra_recipe, not vinca-generated), so it needed this
  # fix applied separately here too -- confirmed necessary the hard way:
  # a plain vinca-template rebuild left this package's own hardcoded
  # -sASYNCIFY untouched, still requiring a shared __asyncify_state
  # global at dlopen() time even after every other package's Asyncify was
  # dropped.
  cat > "$SRC_DIR/__vinca_shared_lib_patch.cmake" <<'EOF'
set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS TRUE)
set(CMAKE_SHARED_LIBRARY_CREATE_C_FLAGS "-s ASSERTIONS=1 -s SIDE_MODULE=1 -sWASM_BIGINT -s ALLOW_MEMORY_GROWTH=1 ")
EOF

  emcmake cmake .. \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_TOOLCHAIN_FILE="$BUILD_PREFIX/opt/emsdk/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake" \
    -DCMAKE_CROSSCOMPILING_EMULATOR="$BUILD_PREFIX/bin/node" \
    -DCMAKE_PROJECT_INCLUDE="$SRC_DIR/__vinca_shared_lib_patch.cmake" \
    -DUCDR_SUPERBUILD=OFF \
    -DUCDR_BUILD_TESTS=OFF \
    -DUCDR_BUILD_EXAMPLES=OFF \
    -DBUILD_SHARED_LIBS=ON
else
  cmake .. \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DUCDR_SUPERBUILD=OFF \
    -DUCDR_BUILD_TESTS=OFF \
    -DUCDR_BUILD_EXAMPLES=OFF \
    -DBUILD_SHARED_LIBS=OFF
fi

cmake --build . -j"${CPU_COUNT}"
cmake --install .
