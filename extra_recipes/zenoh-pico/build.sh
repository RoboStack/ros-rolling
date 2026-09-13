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
  # No real pthreads, and (as of 2026-09-13) no Asyncify either -- see
  # vinca's build_ament_cmake.sh.in for the full rationale (Asyncify +
  # runtime dlopen() of a SIDE_MODULE hits a real, unresolved
  # Emscripten/Binaryen limitation). Z_FEATURE_MULTI_THREAD=0 puts
  # zenoh-pico into its already-existing single-threaded/no-RTOS mode
  # (the same mode it uses for e.g. WITH_ARDUINO_OPENCR), where the
  # application pumps the session manually via
  # zp_read()/zp_send_keep_alive() instead of a background read thread
  # signalling a condvar -- this project's own rmw_zenoh_pico patch calls
  # these in a genuinely non-blocking, single-poll fashion whenever the
  # requested rmw_wait timeout is exactly zero, never actually needing to
  # cooperatively sleep at all (see that patch, and
  # ros-rolling-emscripten-zenoh's AGENTS.md's "MAJOR PIVOT" section).
  #
  # TARGET_SUPPORTS_SHARED_LIBS still needs the explicit override:
  # Emscripten.cmake's own default (TARGET_SUPPORTS_SHARED_LIBS=FALSE)
  # silently downgrades BUILD_SHARED_LIBS=ON to a static libzenohpico.a,
  # unrelated to threading.
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
    -DZP_PLATFORM=emscripten \
    -DBUILD_SHARED_LIBS=ON \
    -DZ_FEATURE_MULTI_THREAD=0 \
    -DZ_FEATURE_LINK_WS=1 \
    -DZ_FEATURE_LINK_TCP=0 \
    -DZ_FEATURE_LINK_UDP_MULTICAST=0 \
    -DZ_FEATURE_LINK_UDP_UNICAST=0 \
    -DZ_FEATURE_SCOUTING_UDP=0 \
    -DCMAKE_EXE_LINKER_FLAGS="-sALLOW_MEMORY_GROWTH=1" \
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
