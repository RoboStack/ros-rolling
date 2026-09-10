#!/usr/bin/env bash
set -eo pipefail

# conda-forge's cross-compilation activation scripts define a `cmake` shell
# function that auto-injects -DCMAKE_TOOLCHAIN_FILE/-DCMAKE_CROSSCOMPILING_EMULATOR
# into every invocation -- including `cmake --build`/`cmake --install`, which
# don't accept -D defines and fail with "Unknown argument". vinca's own
# build_ament_cmake.sh.in does the same `unset -f cmake` before calling the
# real binary directly for anything past the initial configure.
unset -f cmake || true

mkdir -p build
cd build

if [[ $target_platform =~ emscripten.* ]]; then
  # Same shared-memory/pthread-ABI fix as every other emscripten-wasm32
  # package in this build (see build_ament_cmake.sh.in / the yaml-cpp-vendor
  # and spdlog-vendor emscripten patches for the same pattern): without
  # explicitly re-enabling TARGET_SUPPORTS_SHARED_LIBS and re-applying
  # USE_PTHREADS=1 at every compile step via CMAKE_PROJECT_INCLUDE,
  # Emscripten.cmake's own default (TARGET_SUPPORTS_SHARED_LIBS=FALSE)
  # silently downgrades BUILD_SHARED_LIBS=ON to a static libzenohpico.a
  # compiled without atomics/bulk-memory, which then fails to link with
  # "--shared-memory is disallowed ... because it was not compiled with
  # 'atomics' or 'bulk-memory' features" into anything that expects a real
  # pthread-enabled shared library.
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
    -DZP_PLATFORM=emscripten \
    -DBUILD_SHARED_LIBS=ON \
    -DZ_FEATURE_MULTI_THREAD=1 \
    -DZ_FEATURE_LINK_WS=1 \
    -DZ_FEATURE_LINK_TCP=0 \
    -DZ_FEATURE_LINK_UDP_MULTICAST=0 \
    -DZ_FEATURE_LINK_UDP_UNICAST=0 \
    -DZ_FEATURE_SCOUTING_UDP=0 \
    -DCMAKE_C_FLAGS="-pthread" \
    -DCMAKE_EXE_LINKER_FLAGS="-pthread -s USE_PTHREADS=1 -s ALLOW_MEMORY_GROWTH=1 -s MAXIMUM_MEMORY=1024MB" \
    -DCMAKE_SHARED_LINKER_FLAGS="-pthread -s USE_PTHREADS=1" \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF
else
  cmake .. \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_SHARED_LIBS=ON \
    -DZ_FEATURE_MULTI_THREAD=1 \
    -DZ_FEATURE_LINK_WS=1 \
    -DZ_BUILD_EXAMPLES=OFF \
    -DZ_BUILD_TESTS=OFF
fi

cmake --build . -j"${CPU_COUNT}"
cmake --install .
