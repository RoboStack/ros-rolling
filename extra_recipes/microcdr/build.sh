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
  cat > "$SRC_DIR/__vinca_shared_lib_patch.cmake" <<'EOF'
set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS TRUE)
add_compile_options("SHELL: -s USE_PTHREADS=1")
set(CMAKE_SHARED_LIBRARY_CREATE_C_FLAGS "-s ASSERTIONS=1 -s SIDE_MODULE=1 -sWASM_BIGINT -s USE_PTHREADS=1 -s ALLOW_MEMORY_GROWTH=1 ")
EOF

  emcmake cmake .. \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_TOOLCHAIN_FILE="$BUILD_PREFIX/opt/emsdk/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake" \
    -DCMAKE_CROSSCOMPILING_EMULATOR="$BUILD_PREFIX/bin/node" \
    -DCMAKE_PROJECT_INCLUDE="$SRC_DIR/__vinca_shared_lib_patch.cmake" \
    -DCMAKE_C_FLAGS="-pthread" \
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
