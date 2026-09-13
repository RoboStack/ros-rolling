mkdir build
cd build

# Upstream's build.sh deletes $PREFIX/bin/python* here ("remove all the
# fake pythons") -- but that's the crossenv shim cross-python_<target>'s
# activation script (etc/conda/activate.d/activate_z-cross-python_*.sh,
# named to run last) just created, and *every* emsdk python-wrapper script
# (emcc/em++/emcmake/...) honors a generic $PYTHON env var that activation
# also exports pointing straight at this same file -- deleting it breaks
# any later emcc/em++/emcmake invocation with "$PREFIX/bin/python: No such
# file or directory". Our own explicit -DPYTHON_EXECUTABLE=... hints below
# already tell CMake which python to use for pybind11 detection, so this
# deletion isn't needed; skip it.

# cross-python_<target>'s activation sets LDFLAGS=$EM_FORGE_SIDE_MODULE_LDFLAGS
# (i.e. ...-s SIDE_MODULE=1), assuming (correctly, for the overwhelming
# majority of python-embedding emscripten-forge recipes) that we're building
# a Python C-extension .so. xeus-python instead links one real executable
# (xpython, add_executable + -sMAIN_MODULE=1) -- CMake picks up the LDFLAGS
# env var automatically for every target's link line, so that stray
# SIDE_MODULE=1 rides along into xpython's own link command too. Harmless
# on its own (MAIN_MODULE apparently wins silently), but Emscripten's
# Asyncify support explicitly asserts `not settings.SIDE_MODULE` during
# linker setup -- fails outright once -sASYNCIFY is added (see recipe.yaml's
# top comment) unless this is cleared first.
export LDFLAGS="$EM_FORGE_LDFLAGS_BASE"

# The emscripten-forge toolchain's own activation script sets
# EMCC_CFLAGS="... -fwasm-exceptions" globally, so every em++/emcc
# invocation gets native wasm exception-handling by default -- including
# the xeus-python-wasm static library's own compile steps (its CMakeLists.txt
# target doesn't call xeus_wasm_compile_options, which is patched
# per-target for xpython itself; see patches/0001-...). Binaryen's Asyncify
# pass hard-crashes on wasm EH instructions, and there's no
# -fno-wasm-exceptions counter-flag emcc honors -- same fix as vinca's
# build_ament_cmake.sh.in applies project-wide.
export EMCC_CFLAGS="${EM_FORGE_CFLAGS_BASE:-}"

export CMAKE_PREFIX_PATH=$PREFIX
export CMAKE_SYSTEM_PREFIX_PATH=$PREFIX

if [[ $target_platform == "emscripten-wasm32" ]]; then
    export USE_WASM=ON
else
    export USE_WASM=OFF
fi

# Cross-compiling: pybind11Config.cmake's find_package(PythonInterp/Libs)
# otherwise picks up $BUILD_PREFIX/bin/python (the native build-platform
# python), not the wasm32-target-shaped one cross-python_<target> provides
# under the same name -- see recipe.yaml's requirements.build comment.
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" == "1" ]]; then
  PYTHON_EXECUTABLE_HINTS="-DPYTHON_EXECUTABLE=$BUILD_PREFIX/bin/python -DPython_EXECUTABLE=$BUILD_PREFIX/bin/python -DPython3_EXECUTABLE=$BUILD_PREFIX/bin/python"
else
  PYTHON_EXECUTABLE_HINTS=""
fi

# Configure step
cmake ${CMAKE_ARGS} ..                                \
    -GNinja                                           \
    -DCMAKE_BUILD_TYPE=Release                        \
    -DCMAKE_PREFIX_PATH=$PREFIX                       \
    -DCMAKE_INSTALL_PREFIX=$PREFIX                    \
    -DXPYT_EMSCRIPTEN_WASM_BUILD=$USE_WASM            \
    ${PYTHON_EXECUTABLE_HINTS}

# Build step
ninja

ninja install

# remove raw-kernel
rm -rf $PREFIX/share/jupyter/kernels/xpython-raw/
