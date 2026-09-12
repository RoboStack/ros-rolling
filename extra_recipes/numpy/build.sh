#!/bin/bash

set -ex

echo "PYTHON"

rm -r -f branding

# Prefer the relocatable openblas.pc shipped by the openblas package.
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

# NumPy tries dependency('scipy-openblas', method: 'pkg-config') before
# dependency('openblas'). That name is not registered in Meson's BLAS
# factory, so it avoids wasm-ld-breaking void dgemm_() symbol probes.
# OpenBLAS only ships openblas.pc; provide a build-local alias derived
# from it (rewrite prefix to $PREFIX — pcfiledir would be wrong here).
PKGCONFIG_DIR="${SRC_DIR}/.emscripten-pkgconfig"
mkdir -p "${PKGCONFIG_DIR}"
sed -e "s|^prefix=.*|prefix=${PREFIX}|" \
    -e 's/^Name: .*/Name: scipy-openblas/' \
    "${PREFIX}/lib/pkgconfig/openblas.pc" \
    > "${PKGCONFIG_DIR}/scipy-openblas.pc"
export PKG_CONFIG_PATH="${PKGCONFIG_DIR}:${PKG_CONFIG_PATH}"

# Fail early if OpenBLAS is not usable from pkg-config.
pkg-config --exists --print-errors openblas
pkg-config --exists --print-errors scipy-openblas
pkg-config --cflags --libs openblas
test -f "${PREFIX}/include/cblas.h"
test -f "${PREFIX}/lib/libopenblas.so"

# Cross builds do not always inherit PKG_CONFIG_PATH; tell Meson where to look.
cp "${RECIPE_DIR}/emscripten.meson.cross" "${SRC_DIR}/emscripten.meson.cross"
cat >> "${SRC_DIR}/emscripten.meson.cross" <<EOF

[built-in options]
pkg_config_path = ['${PKGCONFIG_DIR}', '${PREFIX}/lib/pkgconfig']
EOF
export MESON_CROSS_FILE="${SRC_DIR}/emscripten.meson.cross"

# The emscripten-forge toolchain env's own activation script sets
# EMCC_CFLAGS="... -fwasm-exceptions ..." globally, which any em++/emcc
# invocation ALSO consults independently of CFLAGS/LDFLAGS above -- so
# dropping -fwasm-exceptions from CFLAGS/LDFLAGS alone isn't enough; the
# __cpp_exception WebAssembly.Tag import came right back from this env var
# (confirmed: wasm-dis still showed the tag import with only the CFLAGS fix
# applied). Reset it to the toolchain's own pre-wasm-exceptions base value,
# matching extra_recipes/zenoh-pico/build.sh's identical fix.
export EMCC_CFLAGS="${EM_FORGE_CFLAGS_BASE:-}"

# Deviation from upstream emscripten-forge's own numpy recipe: upstream adds
# -fwasm-exceptions -s SUPPORT_LONGJMP (native wasm exception handling) to
# both CFLAGS and LDFLAGS, and additionally sed's numpy/_core/meson.build's
# own default -fexceptions to -fwasm-exceptions -- producing a
# _multiarray_umath.so that imports a WebAssembly.Tag ("env.__cpp_exception")
# at instantiation time. Our browser_demo/build_rclpy.sh MAIN_MODULE can't
# provide that Tag: native wasm exceptions are incompatible with Asyncify
# (confirmed earlier -- enabling -fwasm-exceptions there crashes binaryen's
# Asyncify pass outright), and Asyncify is required for rmw_wait's
# cooperative polling (see RoboStack/ros-rolling#46). Dropping both flags
# here (and NOT sed-ing meson.build, leaving its own default -fexceptions
# intact) makes this numpy build use the same JS-based exception mechanism
# as the rest of this project's own emscripten-wasm32 packages, resolving
# "LinkError: ... __cpp_exception: tag import requires a WebAssembly.Tag"
# when dlopen()'d from rclpy_boot.js.
export CFLAGS="$CFLAGS -Wno-return-type -Wno-implicit-function-declaration -msimd128"
export LDFLAGS="$LDFLAGS -sWASM_BIGINT -s WASM_BIGINT"

cp $RECIPE_DIR/config/config.h.in  numpy/_core/config.h.in

# otherwise "cython" is not properly executable
echo "add shebang to cython file"
sed -i '1i#!/usr/bin/env python' $BUILD_PREFIX/bin/cython

# -Dblas=openblas makes NumPy try scipy-openblas first (see numpy/meson.build).
# allow-noblas defaults to true; force OpenBLAS to be required.
# Restricting Meson install tags is required to *include* extra files:
# tests  — Python tests and C helpers (_multiarray_tests, …). Packaged as
#          numpy-tests, not numpy; np.test() needs both packages.
# devel  — numpy.pc and headers; SciPy's meson dependency('numpy') uses
#          pkg-config and otherwise fails with "Dependency numpy not found"
MESON_ARGS="-Dhave_backtrace=false" ${PYTHON} -m pip install . -vvv --no-deps --no-build-isolation \
    -Csetup-args="-Dblas=openblas" \
    -Csetup-args="-Dlapack=openblas" \
    -Csetup-args="-Dallow-noblas=false" \
    -Csetup-args="--cross-file=$MESON_CROSS_FILE" \
    -Cinstall-args="--tags=runtime,python-runtime,tests,devel"
