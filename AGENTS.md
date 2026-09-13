# AGENTS.md

Working notes for future coding agents in a RoboStack repo. Replace $DISTRO with e.g. noetic/humble/kilted/rolling and so forth; you can check the working directory.

## Session defaults for this repo

- Prefer fixing easy, low-risk build failures first (one-line CMake / include / standard-level fixes).
- Do not stop to ask the maintainer to run commands; run build/debug loops directly.
- Use checked-out sources in `.pixi` and `output/src_cache` when patching.
- Use `./build_gap_report.py` to track build/recipe gaps across platforms:
  - `Built package artifacts without matching recipe directory`: packages built in `output/<platform>` that are not represented as recipe folders.
  - `Recipe directories without built artifact on this platform`: generated recipes that still need successful builds for that platform.
- If a package is truly Linux-only, move it to Linux-only handling in `vinca.yaml` (or non-linux skip), instead of keeping ad-hoc macOS comments. Follow similar strategies for other platforms such as Windows.
- For patch naming, keep one patch per package and use package-based naming (`patch/ros-$DISTRO-<pkg>.patch`) with no extra suffix variants.

## Standard build loop

```bash
# single package (preferred for debugging)
pixi run build-one ros-$DISTRO-<pkg>

# broad pass when needed
pixi run build_continue_on_failure
```

## Common fix patterns seen in this repo

- Boost 1.88 breakages often need C++14 (`-std=c++14`) instead of `-std=c++11`.
- Avoid linking to `Python::Python` on Apple for module-style targets; use:

```cmake
if( APPLE )
  set_target_properties( ${_name} PROPERTIES LINK_FLAGS "-undefined dynamic_lookup" )
else()
  target_link_libraries( ${_name} ${PYTHON_LIBRARIES} )
endif()
```

- For gtest-related failures, prefer dependency or test-disable fixes over custom shims:
  - add dependency via `patch/dependencies.yaml`, or
  - disable tests when safe.
- For rtabmap RViz plugin issues, force/confirm Qt5 discovery in CMake where needed.

## Debug a failed build

### 1. Find the work directory

```bash
tail -1 output/rattler-build-log.txt
```

### 2. Inspect full log

Read `conda_build.log` in the work dir. Focus on:
- compile errors
- link errors
- configure failures
- patch failures
- missing files

### 3. Inspect build env

Read `build_env.sh` in the work dir:
- `PREFIX`
- `BUILD_PREFIX`
- `SRC_DIR`
- `RECIPE_DIR`

### 4. Check fetched source metadata

```bash
cat .source_info.json | jq .
```

### 5. Investigate by failure class

- Missing headers: check `requirements.host`; verify under `$PREFIX/include`.
- Undefined symbols: check host deps, `$PREFIX/lib`, linker flags.
- Configure failures: inspect flags in `conda_build.sh`; rerun manually with verbosity.
- Patch failures: refresh patch against current source revision.
- Relocatability issues: inspect hardcoded prefixes/rpaths.

### 6. Reproduce interactively

```bash
cd <work-directory>
source build_env.sh
bash -x conda_build.sh 2>&1 | less
```

### 7. Rebuild package

```bash
pixi run build-one ros-$DISTRO-<pkg>
```

## Create a patch from build-directory edits

```bash
WORK_DIR=$(tail -1 output/rattler-build-log.txt)
cd "$WORK_DIR"

# preview first
rattler-build create-patch --directory . --name <patch-name> --dry-run

# with excludes if needed
rattler-build create-patch \
  --directory . \
  --name <patch-name> \
  --exclude "*.o,*.so,*.dylib,*.a,*.pyc,__pycache__,build/" \
  --dry-run

# generate
rattler-build create-patch \
  --directory . \
  --name <patch-name> \
  --exclude "*.o,*.so,*.dylib,*.a,*.pyc,__pycache__,build/"
```

Then move/merge patch into repo package patch file and ensure recipe uses it.

## Validate that patches still apply

Use the patch checker before/after large patch edits:

```bash
pixi run check-patches
```

For faster iteration on one package patch, run the script directly with a recipe filter:

```bash
# prepare + check only one recipe
python check_patches_clean_apply.py --recipe ros-$DISTRO-<pkg>

# prepare only (no build), useful while editing
python check_patches_clean_apply.py --dry --recipe ros-$DISTRO-<pkg>

# multiple focused recipes
python check_patches_clean_apply.py --recipe ros-$DISTRO-<pkg1> --recipe ros-$DISTRO-<pkg2>
```

What it does:
- scans all `recipes/**/recipe.yaml`
- keeps only recipes that declare `source.patches`
- creates `recipes_only_patch/` with minimal patch-check recipes
- runs patch application checks recipe-by-recipe and prints a pass/fail summary

## Patch placement and recipe wiring

- Canonical patch location: `patch/ros-$DISTRO-<pkg>.patch`
- Keep recipe copy in `recipes/ros-$DISTRO-<pkg>/patch/` if this repo flow expects it.
- Ensure `recipes/ros-$DISTRO-<pkg>/recipe.yaml` has:

```yaml
source:
  patches:
    - patch/ros-$DISTRO-<pkg>.patch
```

## Parallelization and dependency-aware scheduling

It is worth splitting work across multiple agents, but only for independent packages.

Rules:
- Do not build dependent packages in parallel.
- Infer dependency relationships from `recipes/ros-$DISTRO-<pkg>/recipe.yaml` (`requirements.host` and `requirements.run`).
- If package A depends on package B (for example `rosmon` -> `rosmon-core`), build/fix B first.
- Run parallel lanes only for packages that do not depend on each other.
- If unsure, serialize the builds.

## Cross-distribution sync

- Work from the clean checked-out heads of rolling, lyrical, kilted, jazzy, and humble; create `codex/cross-distro-sync` in each repo and never merge their independent histories.
- Classify every candidate before editing: portable shared tooling/CI/metadata, conditional package fix requiring a compatible source and refreshed patch, or excluded distro-owned state.
- Keep rosdistro snapshots, mutex/build numbers, ABI/compiler/Python pins, channels/upload targets, package selection, generated recipes, and temporary rebuild controls distro-owned.
- Port patches only for an existing compatible package, using `patch/ros-$DISTRO-<pkg>.patch` and matching recipe wiring; do not copy a patch solely because its filename exists elsewhere.
- Validate changed patch metadata with `pixi run check-patches` and each changed package with `pixi run build-one ros-$DISTRO-<pkg>`; inspect final diffs for protected state.

## Inspect a built conda package

```bash
find output/ -name "*<package-name>*" -type f \( -name "*.conda" -o -name "*.tar.bz2" \)
```

For `.conda` artifacts:

```bash
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
unzip -q <package.conda>
zstd -d < pkg-*.tar.zst | tar -xvf -
zstd -d < info-*.tar.zst | tar -xvf -
```

Check:
- `info/index.json` (deps/build string)
- `info/paths.json` (installed files)
- binaries/libs/rpaths (`otool -L` on macOS)
- hardcoded prefixes in text metadata

## `vinca.yaml` maintenance guidelines

- Add package seeds under `packages_select_by_deps` using ROS package names (dash/underscore accepted).
- Use platform conditions for Linux-only packages; avoid temporary macOS comment blocks.
- Keep `packages_skip_by_deps` and `packages_remove_from_deps` coherent with platform constraints.
- When `build_gap_report.py` shows built artifacts without recipe directories, add those package seeds to `vinca.yaml`.
- After `vinca.yaml` edits, regenerate recipes before expecting `build_gap_report.py` results to change.

## Local contribution workflow (RoboStack)

```bash
pixi run build
```

## Full rebuilds
For full rebuilds also remember:
- refresh snapshot: `pixi run create_snapshot`
- update `conda_build_config.yaml` for active migrations. You can use https://github.com/conda-forge/conda-forge-pinning-feedstock/blob/main/recipe/conda_build_config.yaml as a base, and then also apply migrations that are mostly done; you can check the status at https://conda-forge.org/status/.
- bump `build_number`
- bump mutex minor and update hardcoded mutex refs where needed
- clear stale `pkg_additional_info.yaml` build-number overrides unless intentional
- remember that in CI there is a build cache, if you fix a problem in an already built package you need to delete the cache for this package in the .github/workflows/testpr.yml under "Delete specific outdated cache entries"

## Emscripten-wasm32 Asyncify migration (active sub-project, this repo + the demo repo)

This repo (fork branch `feature/emscripten-wasm32-zenoh-pico`, pushed to
`Tobias-Fischer/ros-rolling`) plus the deployed demo at
`~/robot/ros2-emscripten-zenoh-demo` (git clone of
`Tobias-Fischer/ros2-emscripten-zenoh-demo`, moved out of `/tmp` on
2026-09-12 specifically so it survives a reboot -- **never park a live
working copy of this demo repo under `/tmp` again**, only truly disposable
scratch belongs there) together implement: drop real pthreads from the
whole emscripten-wasm32 ROS2 build, replace blocking waits with
Emscripten Asyncify + zenoh-pico's non-threaded polling mode
(`Z_FEATURE_MULTI_THREAD=0`). Goal: rclc/rclpy/rclcpp browser demos AND
`import rclpy` inside a JupyterLite notebook, both working end-to-end.

### Status (2026-09-12)

Fixed and pushed:
- zenoh-pico bumped 1.4.0 -> 1.7.0 (multi-publisher write-filter bug, ABI
  mismatch from a stale-header pin in `robostack.yaml`). See
  `extra_recipes/zenoh-pico/recipe.yaml` and
  `patch/ros-rolling-rmw-zenoh-pico.patch`.
- `rmw_wait()` network-pump gap for `Z_FEATURE_MULTI_THREAD=0`: added an
  unconditional `zp_read()`/`zp_send_keep_alive()` pump in `rmw_wait.c`
  before `skip_wait` is computed (same patch file). rclc and rclpy
  standalone browser demos both deliver continuously now.
- `_z_string_len`/`_z_report_system_error` trivial exported stub
  definitions for a `static inline` cross-module link gap --
  `browser_demo/wasm_link_stubs.c` in the demo repo.
- `pyjs`'s `pyodide.ffi.to_js()` polyfill missing `dict_converter` kwarg
  (upstream bug, emscripten-forge/pyjs#73) -- patched via
  `patches/pyjs-pyodide-polyfill-to_js-compat.patch` in the demo repo,
  applied to `demo_env_build`'s prefix in `demo_env_build/build.sh`.
  Confirmed present in the actual shipped JupyterLite kernel-package
  tarball (`jupyterlite-content/_output/xeus/demo_env/kernel_packages/
  pyjs-rt-*.tar.gz`), not just the build-time env.
- Resolved a red herring: the JupyterLite launcher never listing the
  `xpython` kernel was traced (via direct `t === serviceManager.kernelspecs`
  identity check, `false` on both jupyterlite-xeus 5.0.0 and 5.1.0) to an
  **upstream webpack Module Federation shared-singleton bug in
  jupyterlite-core/jupyterlite-xeus**, reproduced in a from-scratch
  ROS-free environment (`xeus-python` + `numpy` only, no ROS/zenoh) --
  not something to keep chasing in this project's own code.

Currently blocking `import rclpy` inside the JupyterLite kernel (this is
a *different* bug from the one above -- the kernel now loads and starts,
`import rclpy` itself fails):
- `rclpy`'s compiled extension (`_rclpy_pybind11...so`) is built by this
  repo's vinca template as an Emscripten `SIDE_MODULE` with `-sASYNCIFY`
  (needed for the non-blocking wait fix above). It gets `dlopen()`'d at
  runtime into **xeus-python's own interpreter binary** (`xpython.wasm`,
  from `emscripten-forge-4x`, confirmed via `conda-meta` to be a stock,
  un-rebuilt package -- channel is the remote repo, not a local build),
  which acts as the `MAIN_MODULE` and was **not** built with `-sASYNCIFY`.
  Asyncify's dynamic-linking support needs a shared `__asyncify_state`
  global that only exists when the main module also has Asyncify enabled,
  so linking fails at `dlopen` time:
  `LinkError: ... Import #71 "env" "__asyncify_state": imported mutable
  global must be a WebAssembly.Global object`.
- **Fix identified, in progress as of 2026-09-12 night session**:
  `xeus-python`'s own CMakeLists.txt does the final `-sMAIN_MODULE=1` link
  for `xpython.wasm`/`xpython.js` -- confirmed by cloning
  jupyter-xeus/xeus-python at the exact installed tag (0.19.0) and reading
  its `CMakeLists.txt` directly (`~/robot/wasm-rattler/emscripten-forge-recipes`'s
  own copy of the recipe was stale, pinned to 0.17.3 -- don't trust it,
  clone the actual xeus-python/xeus/pyjs GitHub repos at the exact
  installed version instead when you need real source). Local recipe now
  lives at `extra_recipes/xeus-python/` (recipe.yaml + build.sh + a source
  patch adding `-sASYNCIFY`/`-sASYNCIFY_STACK_SIZE=24576` to the `xpython`
  target's link options, stripping xeus's own hardcoded
  `-fwasm-exceptions` from that same target).
- **This turned into a whole dependency chain needing the same
  `-fwasm-exceptions`-vs-Asyncify fix**, not just xeus-python itself --
  Binaryen's Asyncify pass (`UNREACHABLE executed ... Asyncify.cpp:1146,
  unexpected expression type`) crashes if **any** statically-linked object
  anywhere in the final `xpython.wasm` declares the wasm
  exception-handling target feature, even a pure-C object that never
  actually throws/catches (confirmed via
  `wasm-objdump -s -j target_features` on a stock `_bz2module.o` inside
  `libpython3.13.a` -- shows `+exception-handling` purely from the compile
  flag, not real usage). Every one of these needed its own
  `extra_recipes/<name>/` with the flag stripped and `build_number` bumped
  to 100, discovered one link failure at a time in this order:
  1. `xeus-lite` (`libxeus-lite.a`, statically linked) -- simple
     `EMCC_CFLAGS` reset in `build.sh`, built clean first try.
  2. `pyjs` -- only the `pyjs-dev` output is needed (`libpyjs.a` + cmake
     config); dropped `pyjs-rt`/meta `pyjs` from the local recipe (an
     unrelated pre-existing test-glob gap in `pyjs-rt`, not worth
     chasing). Took **5 attempts** to get right -- see
     `extra_recipes/pyjs/recipe.yaml`/`build_all.sh` comments for the
     full detail, but briefly: (a) needed the same
     `cross-python_${target_platform}` + explicit
     `-DPYTHON_EXECUTABLE=$BUILD_PREFIX/bin/python` hints as
     xeus-python's own first fix, (b) `build_all.sh` had no `set -e`, so
     that failure was silently swallowed and rattler-build happily
     packaged an **empty** `.conda` (0 content files) -- always check
     `grep "Package statistics"` for a nonzero content count, never trust
     a clean-looking log tail alone, (c) a shell comment block
     accidentally landed *inside* a backslash-continued multi-line `cmake`
     command, splitting it and causing `-DBUILD_RUNTIME_BROWSER=OFF:
     command not found` -- comments must go *outside* `\`-continued
     command blocks, (d) `BUILD_RUNTIME_BROWSER=OFF` turned out to be a
     vestigial CMake option in pyjs's own upstream source that doesn't
     actually gate the `pyjs_runtime_browser` executable target (checked
     by cloning `emscripten-forge/pyjs` at the installed tag and reading
     `CMakeLists.txt` directly) -- that unneeded executable needed the
     same `LDFLAGS` reset as xeus-python for its own `MAIN_MODULE=1` vs
     stray `SIDE_MODULE=1` conflict.
  3. `python` (CPython itself, the biggest of the four) -- `-fwasm-exceptions`
     here is hardcoded directly in the recipe's own `Makefile.envs`
     (`CFLAGS_BASE`/`LDFLAGS_BASE`), completely independent of the
     toolchain's global `EMCC_CFLAGS` env var trick used elsewhere --
     stripped directly from `extra_recipes/python/Makefile.envs`. Recipe
     copied from `emscripten-forge/recipes` at commit `fecf57a2`
     (`git log --all -- recipes/recipes_emscripten/python/recipe.yaml`,
     bisected to find `version: 3.13.1, build_number: 11` matching this
     project's actually-installed `python-3.13.1-h_..._11_cp313` -- the
     tip of `main` has since moved to 3.14.x, don't use it).
     **Hit a genuinely nasty rattler-build limitation** getting this one
     to even start building: this recipe's own package is named "python",
     and it also needs a *native build-platform* python at build time
     (HOSTPYTHON in the Makefile, to bootstrap CPython's own cross-compile
     -- regen frozen modules, sysconfigdata). Any requirement whose bare
     package name is literally "python" -- in `build:` or `host:`, exact
     version+build pin or not, channel-qualified (`conda-forge::python=3.13`)
     or not, `cross-python_${{ target_platform }}` swapped in instead, tried
     with `--recipe` vs `--recipe-dir`, tried with an explicit
     `--build-platform osx-arm64` flag -- makes rattler-build's dependency
     analysis see this recipe as self-referential:
     `Cycle detected in dependencies: python`. This reproduced identically
     across roughly ten variations; it is a hard limitation of building
     this recipe standalone (single-recipe invocation), not a syntax
     mistake. `cross-python_${{ target_platform }}` alone *does* dodge the
     literal name match (it expands to a different string) and does pull
     in a working native python (3.13.15 from conda-forge) -- but its own
     `activate.d` script *also* unconditionally tries to bootstrap a
     `crossenv` using `$PREFIX/bin/python` (the **host/target**-side
     python), which doesn't exist because this recipe is what creates it
     -- crashes with `"$PREFIX/bin/python does not exist"`. Resolution:
     drop every python-named requirement from `recipe.yaml` entirely, and
     have `build.sh` itself `wget` + manually unpack (`unzip` then
     `zstd -d | tar -x`) a native osx-arm64 `python-3.13.15` `.conda`
     directly from `repo.prefix.dev/conda-forge`, dropping just the
     `bin/python3.13` binary into `$BUILD_PREFIX/bin/` -- entirely
     bypassing rattler-build's dependency graph for this one bootstrap
     need. Status as of this writing: build launched, not yet confirmed.
     **If any other package in this sub-chain ever needs a native version
     of itself to cross-compile, expect the identical cycle bug** and
     reach for this same manual-fetch pattern rather than re-litigating
     the ~10 dependency-syntax variations above.
- General lesson from this whole sub-chain: **verify every rattler-build
  result by grepping its own log for `Package statistics: N files (M
  content, ...)` with `M > 0`**, not just the absence of an error at the
  tail -- a build script without `set -e` can fail silently and still
  produce a technically-valid, empty `.conda` package that a later
  consumer then fails against with a much more confusing error
  ("Could not find pyjsConfig.cmake" instead of the real underlying
  Python-detection failure).
- **Always bump `build_number` when rebuilding any of these packages** so
  rattler-build's package-cache treats it as a new artifact and the
  solver actually picks up the rebuild.

### Status update (2026-09-13 overnight session)

**Milestone: the whole `-fwasm-exceptions`-vs-Asyncify dependency chain is
now fixed end-to-end.** A 4th package needed the same fix, found only
*after* `xeus-lite` + `pyjs-dev` + `python` were all already fixed and
`xeus-python`'s link *still* crashed with the Asyncify `UNREACHABLE`:
`xeus` itself. Its own `cmake/WasmBuildOptions.cmake` (shared by
xeus-lite and xeus-python via `include(WasmBuildOptions)`) hardcodes
`-fwasm-exceptions` as a *PUBLIC* compile/link option on the `xeus`
target -- PUBLIC options propagate via CMake usage requirements into
every consumer's own new compilation units too (confirmed via `grep
INTERFACE_COMPILE_OPTIONS` on the installed `xeusTargets.cmake`), so even
though `libxeus.so` is dynamically loaded and never itself embedded in
`xpython.wasm`, the flag still poisoned xeus-python's own compile.
Fixed via `extra_recipes/xeus/` (recipe.yaml, two patches -- see the
recipe's own header comment for the full trace). Second, separate bug in
the same package: `xeus`'s own `libxeus.so` final link step never set
`DISABLE_EXCEPTION_CATCHING`/`SUPPORT_LONGJMP` explicitly at all (the
only one of the four packages missing this), so it silently defaulted to
wasm-native EH at link time regardless of the compile-time patch --
caught by direct symbol search (`wasm-objdump -x libxeus.so | grep -o
"_Unwind_CallPersonality\|__cpp_exception\|__wasm_lpad_context"`), NOT by
`target_features` metadata (which looked clean and was misleading).
First attempt at the explicit-flags patch also hit a hard emscripten
error, `DISABLE_EXCEPTION_CATCHING=0 is not compatible with
-fwasm-exceptions`, because `xeus`'s own `build.sh` was the only one of
the four that never reset the toolchain-global `EMCC_CFLAGS` env var
(which the activation script sets to include `-fwasm-exceptions`
unconditionally) -- fixed by adding the same `export EMCC_CFLAGS=
"${EM_FORGE_CFLAGS_BASE:-}"` reset the other three packages already had.

Result: `xeus-python-0.19.0-py313hfc49295_101.conda` now builds
completely cleanly -- 8 content files, `bin/xpython.wasm`/`bin/
xpython.js` both present, `package_contents` test passed, zero errors in
the full build log. `demo_env_build` and `jupyterlite-content` both
rebuilt successfully on top of it and confirmed (via `conda-meta`) to
embed all four fixed packages: `python-3.13.1-h_0e8c188_101_cp313`,
`xeus-6.0.5-hc0b4002_103`, `xeus-python-0.19.0-py313hfc49295_101`.

**Confirmed live in the browser (via one connected kernel tab): the core
fix genuinely works.** The old `LinkError: ... __asyncify_state`
(xpython.wasm as a non-Asyncify MAIN_MODULE refusing rclpy's Asyncify
SIDE_MODULE) is completely gone. `import rclpy`'s first cell now
progresses to a *new, later-stage* error instead:
```
ImportError: dynamic module does not define module export function
(PyInit__rclpy_pybind11)
```
This is real progress (a different, later failure), but the root cause
is **not yet found**. Ruled out so far (2026-09-13 follow-up):
- Not a build/export gap: `wasm-objdump -x -j Export` on the actual
  `.so` shipped inside the real kernel package tarball
  (`jupyterlite-content/_output/xeus/demo_env/kernel_packages/
  ros2-rclpy-11.0.3-*.tar.gz`) shows `func[816] <PyInit__rclpy_pybind11>
  -> "PyInit__rclpy_pybind11"` in the actual runtime-visible Export
  section (not just the object's symbol table, which was the misleading
  check in an earlier, different bug this session -- this time the
  Export section itself is clean too).
- Not a missing-package gap: `empack_env_meta.json` lists all 145 needed
  conda packages (`ros2-rclpy`, `ros2-rmw-zenoh-pico`, `zenoh-pico`,
  `python`, etc.) and every one has a matching tarball in
  `kernel_packages/` -- nothing is silently dropped from what ships to
  the browser.
- **New lead, not yet confirmed**: `pyjs`'s own
  `include/pyjs/pre_js/dynload/dynload.js` (compiled verbatim into
  `xpython.js` -- `grep loadDynlibsFromPackage bin/xpython.js` finds it)
  implements a custom **async promise-based dlopen preloader**
  (`Module._emscripten_dlopen_promise`, one at a time behind a mutex)
  that's supposed to `dlopen()` every package's shared libraries
  up front, at kernel-package-install time, before any Python code runs
  -- this is presumably the mechanism that lets CPython's own later
  *synchronous* `dlopen()` (inside `_imp.create_dynamic`) just hit an
  already-resolved cache instead of needing to itself do async work.
  `_rclpy_pybind11.cpython-313-wasm32-emscripten.so` needs 71 transitive
  `.so` dependencies (its own `dylink.0` `needed_dynlibs` list -- every
  librcl/librmw/rosidl-generated lib) -- **not yet confirmed whether
  this preload step actually completes for all 71 before `import rclpy`
  executes**, or whether it's silently failing/being skipped for some of
  them (a manifest/empack-side gap in how `shared_libs[i]` gets
  populated for this package specifically), leaving CPython's own
  later plain synchronous dlopen as the only real load attempt for a
  .so with an unusually deep dependency chain. Unlike CPython's generic
  `ImportError`, the JS preloader *does* capture and rethrow the real
  `dlerror()` text on failure (`error loading shared library ${path}
  from package ${pkg_file_name}: ${error_msg}`) -- if kernel startup
  logs one of these and continues anyway instead of hard-failing, that
  would be the smoking gun.
- **Next step once a kernel connects**: check the browser console log
  around kernel *startup* (not just the `import rclpy` cell) for any
  `"error loading shared library"` message from this preloader; if none
  appears, add a diagnostic cell that individually `ctypes.CDLL()`s a
  handful of the 71 dependency paths to see whether one throws first.

**2026-09-13, further console-log archaeology on the kernel-registration
flakiness** (real Chrome, via `claude-in-chrome`, `read_console_messages`
with no pattern filter to get the FULL history across many reloads of the
same tab over several hours): found two genuinely new, previously-unseen
things, neither of which is the module-federation bug itself, but both
of which make it much harder to get a clean test:
1. **Stale-build `ChunkLoadError` from an old cached webpack chunk**: for
   roughly 15 minutes of repeated reloads, every attempt logged
   `SyntaxError: Unexpected strict mode reserved word` (later `Unexpected
   token ','`) when parsing
   `extensions/@jupyterlite/xeus-extension/static/724.<hash>.js`,
   immediately followed by `ChunkLoadError: Loading chunk 724 failed` and
   `Failed to create module: package: @jupyterlite/xeus-extension`. The
   chunk hash (`724.5ee411669b4955cb.js`) stayed IDENTICAL across all
   these failing reloads -- almost certainly the JupyterLite ServiceWorker
   serving a stale/corrupted cached copy of that chunk from BEFORE one of
   this session's several `jupyterlite-content` rebuilds (each rebuild
   changes file hashes; the old SW cache doesn't know to invalidate until
   it notices a version mismatch). This resolved itself only once the SW
   logged `"New version, unregistering existing service workers"` /
   `"All existing service workers have been unregistered"` -- after which
   the chunk hash changed to a fresh one (`724.be1303a8fd1a3e1b.js`) and
   parsed fine. **This self-healing check is NOT immediate** -- it took
   on the order of 15-20 minutes of periodic reloads in this observation
   before it fired, which lines up with "it takes a while but it shows up
   for me." If you hit this exact `SyntaxError`/`ChunkLoadError` pair,
   the fix is a real **"Clear site data"** (not just a reload) rather
   than waiting -- don't just keep reloading and hoping.
2. **A stale persisted kernel-id reconnect loop, separate from (1) and
   separate from the module-federation bug**: long after the chunk-load
   issue cleared, the console kept logging `Starting WebSocket: ws://.../
   api/kernels/c5578e6d-1f4d-437f-bb32-8fe7e98cbd5f` followed immediately
   by `Trying to send message on removed socket for kernel c5578e6d-...`
   on EVERY subsequent reload, hours apart (`20:02`, `01:59`, `02:00`
   timestamps all reconnecting to the exact same kernel id). This is
   JupyterLite's workspace/layout-restoration state (persisted in
   IndexedDB for the origin) remembering "this notebook was bound to
   kernel `c5578e6d-...`" from an EARLIER session in this same marathon
   (almost certainly the kernel-restart-hang incident from earlier
   tonight) and re-attempting that same dead reconnect on every load
   instead of ever trying to start a fresh kernel. Explicitly selecting
   "No Kernel" in the Select Kernel dialog stops the reconnect attempts
   (confirmed), but the Select Kernel dropdown's own list of available
   kernelspecs is a *separate* thing (driven by the module-federation
   singleton bug) and stayed empty regardless -- so clearing this stale
   reconnect state alone did not surface the xpython kernel option.
   **If kernel selection is completely stuck, a real "Clear site data"**
   for the `127.0.0.1:8877` / `:8880` origins (not just picking "No
   Kernel") is the more thorough reset -- it clears both this stale
   session-restore state AND any leftover stale-chunk SW cache in one
   shot, and is worth doing proactively before a long test session
   rather than only after hitting one of these two symptoms.

**Tested and ruled out**: did a real programmatic "Clear site data"
(`serviceWorker.getRegistrations()`+`unregister()`, `caches.keys()`+
`delete()`, `indexedDB.databases()`+`deleteDatabase()`, `localStorage`/
`sessionStorage.clear()`) via the browser console on both `:8877` and
`:8880`, then a fresh reload of each -- the Select Kernel dropdown was
STILL empty (`["No Kernel"], no xpython entry`) on both immediately
after. So clearing site data reliably fixes symptoms (1) and (2) above,
but does **not** by itself fix the core module-federation kernelspec-
registration bug -- that one really does seem to need actual wall-clock
patience/retries as observed before, not a cache reset.

**2026-09-13, further corroboration via a genuinely fresh tab (not a
reload)**: opened a brand-new tab (no prior JS/IndexedDB state at all)
to `:8880/lab/index.html` and checked `read_network_requests` +
`read_console_messages`. Confirmed the extension's static assets load
perfectly cleanly every time -- `remoteEntry.*.js` and all its chunks
return 200, and critically **the extension successfully fetches its own
kernel manifests**: both `http://.../xeus/kernels.json` and
`http://.../xeus/demo_env/xpython/kernel.json` return 200. So the plugin
code runs far enough to discover and read the xpython kernelspec from
disk. Despite that, the kernel never appears anywhere in the UI on this
fresh tab (`document.body.innerText` contains no "xpython"/"XPython" at
all). **This corroborates rather than contradicts the standing
module-federation-singleton diagnosis**: the plugin genuinely does the
work (fetch + parse the kernelspec), it just doesn't end up registered
in the SAME `IKernelSpecs` instance the shell's UI reads from. Nothing
here suggests a fix on our side -- still upstream jupyterlite-core/
jupyterlite-xeus territory, not introduced by any of tonight's changes.

**Kernel-registration upstream bug reconfirmed, not caused by us.**
Reproduced via a *third* independent UI surface beyond the two from the
earlier session (Select Kernel dropdown only offering "No Kernel"; a
kernel restart hanging forever in "Unknown" status) -- the New Launcher's
tile grid also shows no Python/xpython tile at all. All three are
consistent with the already-diagnosed upstream jupyterlite-core/
jupyterlite-xeus webpack Module Federation shared-singleton bug (the
`IKernelSpecs` instance `activate()` receives `!==` the one
`app.serviceManager.kernelspecs` actually reads from). It genuinely does
resolve sometimes with no code change (one tab connected live, "Python
3.13 (XPython) | Idle", matching what you'd already observed) -- but
**do not click "Restart the kernel" on a working tab to test further**,
it got the only working tab stuck disconnecting/reconnecting forever
("Connection lost, reconnecting in 0 seconds" x3) with no recovery
observed; a fresh reload/new tab is safer than a restart for getting a
kernel back. If you need a reliable test loop, consider: opening several
fresh tabs at once and using whichever one connects, or scripting a
retry-reload loop and polling `app.serviceManager.kernels` from the
browser console rather than relying on the UI dropdown (which reads from
the broken singleton).

### Local dev server conventions (demo repo)

Always serve via `site/_serve_local.py <port> <root>` (sends
`Cache-Control: no-cache` + a content-hash `ETag`, and the COOP/COEP
headers JupyterLite needs) -- never plain `python3 -m http.server`, and
never leave ad-hoc one-off server scripts running; they pile up and make
it easy to test a stale/wrong build by hitting the wrong port. Canonical
ports as of 2026-09-12, all rooted under
`~/robot/ros2-emscripten-zenoh-demo`:
- `8877` -- whole repo root (rclc/rclpy talker demos at
  `/browser_demo/out/index_rclc.html` / `index_rclpy.html`)
- `8880` -- `jupyterlite-content/_output` (`/lab/index.html`)

JupyterLite also keeps its own Service Worker + Cache Storage per origin
for offline support, independent of HTTP caching -- after rebuilding
`jupyterlite-content`, do a real "Clear site data" in the browser before
retesting on the same port, not just a hard reload.

### Side investigation: `ros2-micro-ros-msgs` CI failure (GHA run 34686508869, unrelated to the Asyncify work above)

Looked at `gh run view 34686508869 --repo Tobias-Fischer/ros2-emscripten-zenoh-demo
--log-failed` (this CI job builds the FULL generic ros-rolling closure --
moveit, autoware, gazebo, clearpath, etc. -- much broader than anything this
demo project actually needs; not our narrow local build). The actual error,
repeated for `ros2-micro-ros-msgs` and several sibling message packages
(`ros2-test-msgs`, `ros2-rcl-interfaces`, `ros2-statistics-msgs`,
`ros2-std-msgs`, `ros2-example-interfaces`, `ros2-lifecycle-msgs`, all
clustered in the same ~90s window):
```
Could NOT find Python3 (missing: Python3_NumPy_INCLUDE_DIRS NumPy) (found ...)
emcmake: error: 'cmake ... -DPYTHON_EXECUTABLE=$BUILD_PREFIX/bin/python3.13 ...' failed
```
**Root cause hypothesis (fairly confident, not yet verified by a fix
attempt)**: the CMake invocation passes `$BUILD_PREFIX/bin/python3.13` (the
NATIVE/host-arch interpreter used to run codegen scripts during
cross-compilation) as `PYTHON_EXECUTABLE`, and some ament/rosidl CMake macro
in these packages then does `find_package(Python3 COMPONENTS ... NumPy)`
against THAT SAME native interpreter. But numpy in this whole build is only
ever installed as a **cross-compiled wasm32 TARGET package** (`extra_recipes/
numpy`, installed into `$PREFIX`, the emscripten sysroot) -- confirmed via
the solver's own package table for this exact failing micro_ros_msgs solve,
which shows `numpy 2.5.3 py313h97174d1_100 output` correctly resolved as a
`host:` (cross-compilation target-side) dependency. It is never installed
into `$BUILD_PREFIX`'s own native python at all, so `find_package(Python3
COMPONENTS NumPy)` against the native interpreter can never succeed --
this isn't a solver/caching mismatch (ruled out: the right numpy build is
being picked), it's a structural gap between "which python numpy is
installed for" and "which python this particular CMake check inspects".
**Update: fixed 2026-09-13, once the user was back online and explicitly
asked for it** (previously deliberately left unfixed here given the
blast radius -- see below for why that call changed). This affects a much
larger, mostly out-of-scope closure than the demo project's own narrow
build (which doesn't build any of these specific message packages the
same way), and the real fix does mean patching the ament/rosidl macro that
requests the NumPy component against the native interpreter
unconditionally -- done below, scoped to `EMSCRIPTEN` only.

**Exact culprit found** (via `grep -rn NumPy` over `output/src_cache`):
`rosidl_python-release.git/cmake/rosidl_generator_py_generate_interfaces.cmake`
line 36:
```cmake
find_package(Python3 REQUIRED COMPONENTS Interpreter Development NumPy)
```
and later (~line 167) `target_link_libraries(${_target_name_lib} PRIVATE
Python3::NumPy Python3::Python)` -- this is `rosidl_generator_py`'s own
interfaces-generation macro, invoked by EVERY ROS message package that
generates Python bindings (which is all of `ros2-test-msgs`,
`ros2-rcl-interfaces`, `ros2-statistics-msgs`, `ros2-std-msgs`,
`ros2-example-interfaces`, `ros2-lifecycle-msgs`, `ros2-micro-ros-msgs`,
and presumably every other `*_msgs`/`*_interfaces` package in the whole
ros-rolling closure). It unconditionally requires the `NumPy` component
of whatever `Python3_EXECUTABLE` vinca's template points CMake at for this
build -- which vinca deliberately pins to `$BUILD_PREFIX/bin/python3.13`
(the native host interpreter, presumably so `Python3_FIND_STRATEGY=LOCATION`
gets consistent version/ABI info without trying to actually *run* a
cross-compiled wasm32 python on the build host).

**Fixed 2026-09-13** (once the user was back and explicitly asked for this
specific fix + a full emscripten rebuild -- previously left unfixed here
given the blast radius, see the note above). Went with option (b) from
the original writeup -- a patch to `rosidl_python` itself, scoped to
`EMSCRIPTEN` only, in
`patch/ros-rolling-rosidl-generator-py.emscripten.patch` (the same patch
file this recipe already carried, for the earlier, separate
`Python3::NumPy`/pthreads-link fix -- added a second hunk right before it):
on `EMSCRIPTEN`, `find_package(Python3 REQUIRED COMPONENTS Interpreter
Development)` (dropping the `NumPy` component, which can never be found
against the native `$BUILD_PREFIX` python) and instead locate NumPy's
`_core/include` directory directly under the TARGET prefix (`file(GLOB
... "$ENV{PREFIX}/lib/python*/site-packages/numpy/_core/include")`,
verified against the actual installed layout of our own `numpy` `.conda`)
-- non-emscripten platforms are untouched (`else()` branch keeps the
original `find_package(... NumPy)` call). This works because numpy is
already a `host:` (cross-compiled target-side) dependency of every
`*_msgs`/`*_interfaces` package -- confirmed present under `$PREFIX` at
CMake-configure time, just never visible to `find_package`'s native-python
NumPy-component probe.

Bumped `build_number` (25 -> 26) for `rosidl_generator_py` itself (in
`pkg_additional_info.yaml`, vinca's own per-package override mechanism)
plus all 15 `*_msgs`/`*_interfaces` packages in this repo's own (233-recipe,
much smaller than the CI closure) local build -- `action_msgs`,
`builtin_interfaces`, `example_interfaces`, `geometry_msgs`,
`lifecycle_msgs`, `micro_ros_msgs`, `rcl_interfaces`, `rosgraph_msgs`,
`sensor_msgs`, `service_msgs`, `statistics_msgs`, `std_msgs`, `test_msgs`,
`type_description_interfaces`, `unique_identifier_msgs` -- so rattler's
cache can't silently keep serving a stale pre-fix artifact for any of
them. Verified via `python check_patches_clean_apply.py` that the new
patch hunk applies cleanly (`ros2-rosidl-generator-py -> OK`; the 4
unrelated failures in that same run, for `python`/`xeus`/`xeus-lite`/
`xeus-python`, are a pre-existing false-positive in the check script for
those hand-written `extra_recipes` -- nothing to do with this fix).
Kicked off a full `pixi run build-emscripten` (backgrounded, `nohup` to
`/tmp/build_emscripten_run.log`, watched via a Monitor task) to rebuild
this repo's whole emscripten-wasm32 recipe set end to end.

**Result: complete success.** Both passes of the fixed two-pass sequence
ran (`build-emscripten-pass` -> `sync-native-bootstrap-mirror` ->
`build-emscripten-pass` again) against the full 233-recipe closure.
`ros2-rosidl-generator-py`/`ros-rolling-rosidl-generator-py` rebuilt
clean, and every one of the 15 bumped `*_msgs`/`*_interfaces` packages
(both name variants) rebuilt clean too -- including `ros2-micro-ros-msgs`
itself, the exact package the original CI failure (GHA run 34686508869)
named. `grep -niE "could not find python3|error:|panicked|traceback"` over
the full ~50k-line build log returns **zero matches**; everything else in
the closure that was already built from earlier in this session correctly
`Skip`ped (451 "Skipping build for" lines) rather than needlessly
rebuilding. The `ros2-micro-ros-msgs` CI failure this whole side
investigation started from is now genuinely fixed, not just diagnosed.

### BREAKTHROUGH 2026-09-13: the "kernel never registers" problem is a
### tab-visibility artifact of automated testing, not an upstream bug in
### our build (or even necessarily a real, permanent upstream bug at all)

At the user's request, re-tested kernel registration against a **pure,
from-scratch emscripten-forge environment with nothing ROS-related at
all** (`/tmp/vanilla_jupyterlite_test` -- stock `xeus-python` + `numpy`
from `emscripten-forge-4x`, `jupyterlite-xeus` 5.1.0, built earlier this
marathon, served on `:8879`). **Same symptom**: Select Kernel dropdown
shows only "No Kernel" when opened via any of this session's browser
automation tools. This rules out anything specific to this project's own
build/patches -- the earlier "upstream jupyterlite-core/jupyterlite-xeus
Module Federation singleton bug" diagnosis (an `IKernelSpecs` instance
identity mismatch, established much earlier in this marathon) is real,
but is NOT the reason it never resolves for automated testing.

**Root cause of "never resolves for Claude, always eventually works for
the user" found**: every tab this session's browser tools produce --
`claude-in-chrome` (even after `tabs_context_mcp`, a real click, or
attempting to bring the tab forward) and the embedded `Claude_Browser`
preview pane (even with `tabs_create({foreground:true})` and an explicit
`tabs_select`) -- reports `document.visibilityState === "hidden"` and
`document.hasFocus() === false`. Neither tool produces a tab that is
genuinely OS-level visible/focused the way a human's own browser window
is; "foreground" in these tools' own vocabulary means "the frontmost tab
*within this tool's tracked group*", not "actually rendered and visible
on a real screen."

This matters specifically because of how JupyterLab's own service layer
is built: `grep -o "when-hidden" build/jlab_core.*.js` in the vanilla
build confirms `@jupyterlab/services-extension:kernel-spec-manager`
(and every other core service manager -- kernels, sessions, contents,
settings, terminals) constructs its background poll with
`standby: () => !isConnected || "when-hidden"` (Lumino's `Poll` class,
used throughout JupyterLab for periodic refresh). **A poll with
`standby: "when-hidden"` does not run at all while
`document.visibilityState === "hidden"`.** So whatever one-time race
causes the kernelspec to be transiently missing/misregistered right
after the Module Federation extension activates, a real user's visible
tab lets the `KernelSpecManager`'s own periodic refresh poll keep
retrying and self-correct within moments ("takes a while but it shows up
for me") -- while every tab this session drives is permanently `hidden`
from the browser's own perspective, so that self-healing poll never
fires, and the dropdown looks permanently, unfixably broken even though
nothing is actually wrong with the underlying kernel/package data.

**Follow-up test (same session, right after the finding above) --
NEGATIVE result, corrects the theory above**: re-did the
`document.visibilityState`/`hidden` monkey-patch (`Object.defineProperty`
+ dispatch a synthetic `visibilitychange`) on a `claude-in-chrome` tab
this time rather than the `Claude_Browser` pane -- it did NOT crash here
(so the earlier crash was likely specific to the `Claude_Browser` preview
pane's own rendering path, not a general hazard of the patch itself), and
`document.visibilityState`/`hidden` genuinely stayed spoofed as
"visible"/`false` for the full duration. Waited **~70 seconds** (well
past any plausible `KernelSpecManager` poll interval) with the page
otherwise untouched. **The kernel still never appeared** -- dropdown
still empty, `document.body.innerText` never gained "Python"/"XPython".
Also tried the Kernels sidebar's "Refresh List" button first (before the
monkey-patch): no effect either, but that button refreshes the
*session* list (running kernels), not the *specs* list (available
kernel types) -- wrong manager, not a real test of the specs-poll theory.

**Conclusion: the `standby: "when-hidden"` Poll mechanism is real,
confirmed in the actual bundled code, and IS a genuine reason a
background/non-visible tab won't self-heal on its own schedule -- but it
is NOT sufficient by itself to explain this bug, since forcing visibility
"on" well after the fact and waiting a full poll interval still didn't
surface the kernel.** This means the earlier, original diagnosis from
much earlier in this marathon -- an actual `IKernelSpecs` *instance*
identity mismatch between what the `xeus-extension`'s `activate()`
registers into and what the shell's `serviceManager.kernelspecs` reads
from (confirmed via a direct `===` identity check, `false`, on both
jupyterlite-xeus 5.0.0 and 5.1.0) -- is still the more likely primary
root cause: polling (with or without standby) a manager instance that
was simply never given the registration in the first place will never
surface anything, no match how many times or how promptly it retries.
Tab visibility may still be A contributing factor (e.g. for whatever
one-time async race happens at *first activation*, before any poll ever
runs) but is not, on its own, the mechanism behind the "never resolves"
symptom in this session's testing. **Do not re-attempt the global
`document.hidden` monkey-patch as a fix** -- it's now tested twice with
no positive result, only inconsistent side effects (crashed once, no
effect the other time).

**Practical implication going forward**: this project's actual browser
demos (`browser_demo/build_rclc.sh`/`build_rclpy.sh` output, and the
compiled-to-JS/wasm executables, as opposed to the interactive
JupyterLite *kernel*) do NOT depend on JupyterLab's service-manager
polling at all -- they're plain HTML pages running a compiled program,
not a Jupyter kernel session -- so this visibility issue is specific to
testing the **JupyterLite notebook kernel** path, not the rclc/rclpy
standalone demos, which is why those were confirmed working via
automation earlier without needing this same investigation.

### BREAKTHROUGH 2026-09-13 (later the same day): `xpython.js`/`xpython.wasm`
### can run directly under Node -- no browser needed at all -- and this
### found and fixed a genuine, previously-undiscovered upstream bug

At the user's prompt ("doesn't Jupyter have an API interface that doesn't
need browser interaction?"): `xpython.js` is a MODULARIZE-style emscripten
build exporting a plain CommonJS factory function
(`module.exports = createXeusModule`). It's compiled with
`-sENVIRONMENT=web,worker` (confirmed: `readAsync`/`readBinary` are only
assigned inside `if(ENVIRONMENT_IS_WEB||ENVIRONMENT_IS_WORKER){...}`, the
`else` branch for Node was completely empty), so it doesn't run under
plain Node out of the box, but the gap is small and patchable:
1. Pass `Module.wasmBinary` (bytes read via Node's own `fs.readFileSync`)
   to the factory call -- bypasses the whole browser-only wasm-fetch path.
2. Patch the empty `else{}` branch (in a **local copy** of `xpython.js`,
   never the deployed one) to assign `readAsync`/`readBinary` using
   Node's global `fetch` (Node 18+), resolving relative paths (e.g. bare
   `"libxeus.so"`, requested by the dynamic linker) against the same
   `http://127.0.0.1:8880/xeus/demo_env/` root this project already
   serves locally.
3. Call `Module.bootstrap_from_empack_packed_environment(
   \`${kernel_root}/empack_env_meta.json\`, \`${kernel_root}/kernel_packages\`,
   true)` -- this is the SAME function jupyterlite-xeus's own JS harness
   calls to fetch/extract every kernel package tarball into the virtual
   FS; pointing it at this project's already-served `jupyterlite-content`
   deployment reproduces the exact real runtime environment.
4. `Module._eval`/`Module._eval_file` are the raw embind-exported
   functions (need embind-wrapped args, not a plain string -- passing a
   plain JS string throws `Cannot read properties of undefined (reading
   '$$')`); the *real*, usable `Module.eval`/`Module.exec` JS wrappers
   (see `pyjs`'s own `include/pyjs/pre_js/init.js`) only exist AFTER
   `Module.init_phase_2(...)` completes successfully -- don't call the
   underscore-prefixed raw ones directly.

A working minimal harness following this recipe is invaluable for fast
iteration on kernel-bootstrap bugs -- no browser, no tab-visibility
flakiness, no Module Federation singleton bug in the way, just
`node test.mjs` with full stdout/stderr and JS stack traces. **This is
how the actual `PyInit__rclpy_pybind11` investigation should continue**,
not by fighting for a live browser kernel connection.

**What this immediately found**: running this harness against the real
deployed `jupyterlite-content` surfaced `ERROR No module named 'pyjs'`
during kernel bootstrap (`Module.init_phase_2`'s own internal
`import pyjs`) -- a **completely different, earlier failure than
`PyInit__rclpy_pybind11`**, meaning the kernel has likely never
successfully finished bootstrapping in ANY environment (browser included)
this whole marathon; `PyInit__rclpy_pybind11` was probably never even
reached in a real kernel session. Root cause: the `pyjs-rt` conda package
(`emscripten-forge/pyjs`'s own recipe, `build_all.sh`, both upstream's
copy and this repo's local copy before this fix) never passes
`-DPY_VERSION` to its `cmake` configure call. `pyjs`'s own
`CMakeLists.txt` defaults `PY_VERSION` to `3.11` when unset, and uses it
to compute `install(DIRECTORY module/pyjs DESTINATION
lib/python${PY_VERSION}/site-packages)` -- so the actual Python module
(`pyjs/__init__.py`, `core.py`, etc.) silently installs to
`lib/python3.11/site-packages` while everything else in this Python 3.13
build looks under `lib/python3.13/site-packages`. Confirmed via
`tar tzf pyjs-rt-4.0.6-py313h32dd476_100.tar.gz` on the actual deployed
package: **it contained only `conda-meta/*.json` -- zero real files.**
This is a genuine upstream bug (confirmed by checking
`emscripten-forge/recipes`' own `build_all.sh` on GitHub directly -- same
gap, not something introduced by this repo's copy), not previously caught
because nobody had gotten far enough into kernel bootstrap to notice
`import pyjs` itself failing.

**Fixed**: `extra_recipes/pyjs/build_all.sh` now passes
`-DPY_VERSION=3.13` to the cmake configure line (see that file's own
comment). `extra_recipes/pyjs/recipe.yaml` gained a proper `pyjs-rt`
output (`build_rt.sh` already existed from an earlier abandoned attempt,
just never wired into `outputs:` -- now it is), with a
`package_contents` test asserting `lib/python3.13/site-packages/pyjs/
core.py` and `__init__.py` exist, specifically so a PY_VERSION regression
shows up as a build-time test failure instead of silently shipping an
empty package again. `build.number` bumped 102 -> 103. Verified via
`tar tzf` on the freshly-built `pyjs-rt-4.0.6-py313hc2c4625_103.tar.bz2`:
all 8 `.py` files genuinely present at the correct path this time.
Rebuilt `demo_env_build` (`ROS_ROLLING_OUTPUT=.../output ./build.sh`,
confirmed it now resolves to `pyjs-rt-...-py313hc2c4625_103`, not the old
broken one) and `jupyterlite-content` (`pixi run build`) through the real
pipelines -- both picked up the fix cleanly, no manual file-swapping
needed in the end (a manual swap-in-place was used ONLY for a first fast
sanity check before doing the real rebuild, then cleaned up).

**Still open**: with `pyjs-rt` fixed, `import pyjs` no longer fails, but
`Module.init_phase_2` now hits a NEW failure inside its own internal
`Module.exec(...)` call: `RuntimeError: null function or function
signature mismatch` (an emscripten `dynCall_vii`/`invoke_vii` table
lookup failure). Not yet root-caused. Two live hypotheses, not yet
distinguished: (a) a genuine bug that was always there but masked by the
pyjs-rt emptiness (i.e. kernel bootstrap has NEVER actually completed,
in any environment, and this is simply the next layer down), or (b) an
artifact of this Node harness's incomplete replication of the real
browser embedding (Asyncify's actual yield/resume behavior and the
browser event loop timing this build assumes may not translate 1:1 to
Node's own microtask/timer semantics) -- **test this same fixed
deployment in a real, live browser kernel session next** (now genuinely
worth another patient attempt, since this is the first real, substantive
fix to kernel bootstrap this entire marathon) to see whether the
signature-mismatch crash reproduces there too or is Node-harness-specific.
If it reproduces in-browser too, this is the new real blocker and
supersedes the `PyInit__rclpy_pybind11` investigation entirely (that
error can never have been reached for real before now). If it does NOT
reproduce in-browser, the Node harness needs a bit more JS-side scaffolding
(look at what jupyterlite-xeus's real `xeus.ts`/kernel-provider JS does
between module instantiation and `bootstrap_from_empack_packed_environment`
that this minimal harness skips) before it can be trusted for testing
past this point.

**Immediate follow-up, same session: the "null function or function
signature mismatch" crash turned out to be a red herring in the harness,
not a real blocker -- `import rclpy` GENUINELY WORKS now.** Root cause of
the confusion: `Module._eval`/`Module._exec` (underscore-prefixed) are
the RAW embind bindings and need embind-wrapped `globals`/`locals`
arguments, not bare strings -- calling them directly (as the harness
initially did) throws `Cannot read properties of undefined (reading
'$$')`. The real, intended API is `Module.eval`/`Module.exec` (no
underscore) -- plain JS wrapper functions defined in `pyjs`'s own
`init_phase_1` (see `include/pyjs/pre_js/init.js`) that supply the
correct default scope automatically. `init_phase_1` completes
successfully as part of module instantiation, so `Module.exec`/`.eval`
are usable immediately -- **the dynCall signature-mismatch crash inside
`init_phase_2`'s own internal exec call is apparently caught/swallowed
internally by pyjs (bootstrap's promise still resolves, "bootstrap
complete" logs right after) and does NOT prevent basic `Module.exec`
from working afterward.** Switching the harness to use `Module.exec`
instead of `Module._eval` immediately produced:
```
[harness] executing: import rclpy
[harness] SUCCESS: import rclpy worked!
```
**The `PyInit__rclpy_pybind11` error that drove the whole earlier
`dynload.js`/dependency-preload investigation is GONE.** It was almost
certainly a downstream symptom of `pyjs-rt` being empty all along (some
partial/inconsistent bootstrap state), not a real, separate rclpy-side
bug -- once `import pyjs` itself started working (the fix above), rclpy's
own `_rclpy_pybind11.so` dlopen chain (all 71 transitive dependencies)
resolves cleanly.

**New, more precise blocker found immediately after, by executing the
notebook's first-cell statements one at a time**: `import rclpy` alone
succeeds every time; the very next statement, `from rclpy.node import
Node`, aborts with a bare, contextless `RuntimeError: Aborted(). Build
with -sASSERTIONS for more info.` -- no Python traceback, no stderr
message at all before the abort (confirmed by checking every `[stderr]`/
`[stdout]` line logged up to that point -- genuinely nothing). Leading
hypothesis, not yet confirmed: **`ASYNCIFY_STACK_SIZE=24576`** (set in
`extra_recipes/xeus-python`'s own Asyncify-enablement patch) **may be too
small** for whatever deeper/wider call stack `rclpy.node`'s own import
triggers (it's rclpy's main submodule, likely pulling in more of the
`_rclpy_pybind11` C-extension's actual functionality where `import rclpy`
itself might only touch a shallow subset) -- a bare, message-less
`Aborted()` immediately after a `dynCall`/`invoke_v` frame is exactly the
signature of an Asyncify internal-stack overflow, not a Python-level
exception (which would print a traceback via `printErr` first). **Next
step**: bump `ASYNCIFY_STACK_SIZE` in `extra_recipes/xeus-python`'s patch
(try e.g. 65536 or 131072), rebuild xeus-python + demo_env_build +
jupyterlite-content, and retest the SAME `from rclpy.node import Node`
statement via this same Node harness (fast iteration, no browser/kernel-
registration flakiness needed) before touching anything else. This is now
the closest this whole marathon has gotten to the actual finish line --
`import rclpy` itself is confirmed working end-to-end for the first time.

**`ASYNCIFY_STACK_SIZE` bump tested -- ruled out. Real cause found, and
it's much deeper: WASM indirect-function-table corruption, not a stack
overflow, not anything Python/rclpy-specific.** Bumped 24576 -> 131072
(5x), rebuilt xeus-python (build_number 101->102) + `demo_env_build` +
`jupyterlite-content` through the real pipelines (confirmed the new
`StackSize:131072` literally appears in the rebuilt `xpython.js`), reran
the Node harness -- **identical** `from rclpy.node import Node` ->
`Aborted()`, byte-for-byte the same failure. Stack size was not it.

Wrote a second, tighter harness (`test_one.mjs`, taking one Python
statement as a CLI arg so each test gets a genuinely fresh Module/
interpreter -- necessary because after one `Aborted()` the whole wasm
instance is poisoned and every subsequent call in the SAME process also
"fails," which would have made naive one-process-many-statements testing
meaningless) and bisected `rclpy/node.py`'s own early imports one at a
time, always after a working `import rclpy`:
- `from rcl_interfaces.msg import FloatingPointRange` -- OK
- `from rclpy.callback_groups import CallbackGroup` -- OK
- `from rclpy.client import Client` -- **Aborted()**
- `from rclpy.clock import BaseClock, Clock` -- **Aborted()**
- `from rclpy.context import Context` -- **Aborted()**
- `from rclpy.endpoint_info import ActionEndpointInfo` -- **Aborted()**
- `from rclpy.utilities import ok` -- **Aborted()**

At first glance this looks like "some rclpy submodules are broken, others
aren't." **It isn't that.** Confirmed `rclpy.context` is ALREADY in
`sys.modules` after the earlier successful `import rclpy` (`rclpy/
__init__.py` itself does `from rclpy.context import Context as Context`)
-- so `from rclpy.context import Context` right after should be a pure
cache hit, zero new code execution, zero new dlopen activity. Yet it
still aborts. Narrowed further with a plain expression-statement (no
import machinery at all): `sys.modules['rclpy.context'].Context` --
**also aborts**, while `import rclpy.context` (bare form, no attribute
access) succeeds, and `from os import path` (an ordinary stdlib
from-import, same syntax shape) succeeds fine. **So this was never about
which module gets imported, or even about import statements at all --
it's about something in ATTRIBUTE ACCESS on an object descended from the
compiled `_rclpy_pybind11` extension, and it doesn't reproduce
consistently for the same code -- different attribute accesses on
different already-loaded objects abort while syntactically identical
operations on other objects (`os.path`) do not.**

**Working theory (not yet confirmed, but fits every observation):** this
is WASM indirect-function-table corruption from the sheer scale of the
dlopen chain, not a Python-level or rclpy-authorship bug at all.
`_rclpy_pybind11.so` alone pulls in 71 transitive `.so` dependencies
(`dylink.0`'s `needed_dynlibs`, confirmed via `wasm-objdump` much earlier
this marathon). Emscripten's dynamic linker grows a single shared
indirect function table as each `.so` is dlopen'd, appending each
module's exported functions/vtable entries -- under Asyncify, dlopen
itself is asynchronous, and with a chain this deep it's plausible for
table-growth bookkeeping to end up with a stale or overlapping entry for
at least one function-pointer slot (a class's vtable slot, a bound
method's C function pointer, etc.). That would produce exactly this
non-deterministic-looking pattern: most calls resolve to the right
function and work fine, but some specific pre-existing objects'
attribute-dispatch happens to route through a corrupted/reused table
slot and calls into whatever ended up there instead -- a `dynCall_vii`
"null function or function signature mismatch" is the textbook signature
of exactly this failure mode (an indirect call through a bad table
index), not of a stack overflow (ruled out above) or a Python exception
(which would print a traceback via `printErr`, and none ever does).

**This is a much bigger, harder problem than anything fixed so far
tonight** -- it's not a missing `-DPY_VERSION` flag or an unset ASYNCIFY
option, it's a potential Emscripten dynamic-linker correctness issue
under deep multi-`.so` dlopen chains combined with Asyncify, which would
need either a genuine Emscripten upstream fix/workaround or a
significant reduction in how many separate `.so` files get dlopen'd at
once (e.g. statically linking more of the 71 dependencies together
instead of leaving them as 71 separate dynamic libraries) to sidestep
rather than fix directly. **Not attempted yet this session** -- this is
where the investigation should pick up next. Concretely worth trying,
roughly in order of effort:
1. ~~Re-run the SAME failing statement (e.g. `from rclpy.context import
   Context`) two or three times in a fresh process each time~~ -- DONE,
   confirmed **fully deterministic**: 3/3 fresh-process runs of
   `from rclpy.context import Context` abort identically. Doesn't rule
   out the table-corruption theory (a fully deterministic dlopen call
   order would corrupt the same slot the same way every time), but does
   rule out any theory relying on run-to-run timing randomness.
2. Try calling `Module.exec('import gc; gc.collect()')` or forcing a
   table-consistency check between `import rclpy` and the failing
   statement, to see if anything makes the corruption visible/detectable
   earlier.
3. Check emscripten's own changelog/issue tracker for known
   indirect-function-table bugs interacting with `dlopen()` + `ASYNCIFY`
   at this scale -- this may already be a filed, understood upstream
   limitation with a documented workaround (e.g. a minimum
   `TABLE_BASE`/`RESERVED_FUNCTION_POINTERS` setting, or a
   `-sMAIN_MODULE=2` vs `=1` distinction).
4. As a blunter workaround: reduce the SIDE_MODULE count by statically
   linking some of the 71 dependencies directly into `_rclpy_pybind11.so`
   itself (or into `xpython.wasm`) instead of leaving them all as
   separate dlopen targets -- more invasive, but sidesteps the scale
   that's plausibly triggering this rather than needing to fix Emscripten
   itself.

This is genuinely the front line of the investigation now. Everything
above it in this file (pyjs-rt, the Asyncify/-fwasm-exceptions chain, the
NumPy CMake fix) is confirmed fixed and shipped; this table-corruption
issue is the one thing standing between here and a fully working
`import rclpy` + `Node()` in the real notebook.

### Immediate follow-up, same session: precisely characterized -- and it's
### a cross-`Module.exec()`-call object-lifetime bug, not "table corruption"
### in the generic sense; genuinely blocks the real multi-cell notebook

**Ruled out "any big dlopen chain is unstable"**: tested `numpy` (a
different pybind11/embind-loaded SIDE_MODULE) -- creating arrays,
printing them, reading `.ndarray`/`type()` all work perfectly across
separate `Module.exec()` calls, no issue at all. Also tested
`rcl_interfaces.msg.FloatingPointRange.__import_type_support__()` (a
REAL, different typesupport `.so` dlopen, triggered explicitly) followed
by more calls in a fresh exec -- also totally fine. **This rules out any
"generic pyjs/exec-across-calls" or "any ROS typesupport .so" theory.**
It is specific to objects tied to `_rclpy_pybind11` itself.

**Precise trigger, found by testing single combined vs. separate exec
calls**: `import rclpy` followed immediately by `from rclpy.node import
Node` **in the SAME `Module.exec()` call** -- works. In fact, **the
ENTIRE real demo-notebook first cell** (`import os`, env vars, `import
rclpy`, `from rclpy.node import Node`, event-handler/message imports,
`rclpy.init(args=[])`, `Node(...)` construction, `print(...)`) run
together as one `Module.exec()` call -- **succeeds completely**:
```
[test] executing full cell 1 as ONE exec call...
[test] RESULT: CELL 1 SUCCEEDED
```
This IS the actual finish line for `import rclpy` + `Node()` construction
-- genuinely confirmed working, for the whole real first-cell content,
not just a bare `import rclpy`.

**But it does NOT stop there -- tested cell 2 next (a separate
`Module.exec()` call, using `node`/`PublisherEventCallbacks`/`String`
created in cell 1's call, matching the real demo notebook's actual
`create_publisher`/`create_subscription` cell) -- and it crashes the same
way**:
```
[test] executing CELL1... [test] CELL1: OK
[test] executing CELL2... [test] CELL2: FAILED: Aborted().
```
Bisected CELL2 down to the single simplest possible statement: **merely
referencing `node` (`print(node)`, `x = node`, `node.get_name()`) or
`String` (`print(String)`, `String()`) from a NEW exec call after CELL1's
exec call finished -- aborts, every time.** A totally unrelated trivial
statement (`print('trivial')`) in that SAME new call is fine. So: **any
Python-level reference to an object connected to `_rclpy_pybind11`'s
compiled layer, made from a DIFFERENT top-level `Module.exec()`
invocation than the one that originally created/touched it, crashes with
a message-less abort.** Within one call: totally fine, however much code.
Across two separate calls: guaranteed crash, deterministic, regardless of
which specific rclpy-descended object or how trivial the reference is.

**Why this matters a lot**: a real Jupyter notebook executes each CELL as
its own separate top-level "execute this code" call into the kernel --
there is no way to make a real notebook's cell 1/cell 2/cell 3 collapse
into a single call. If this bug is real in the actual browser kernel (not
just an artifact of this Node harness's use of `Module.exec` specifically
-- see caveat below), **it would still fully block the practical goal**
even with pyjs-rt fixed: you could get `import rclpy` and even construct
a `Node` in one cell, but the moment a LATER cell tries to use that node
(publish, subscribe, spin, anything), it would crash.

**Open question, not yet resolved**: does the REAL xeus-python kernel
even route notebook cell execution through this same `Module.exec()` JS
function at all? `Module.exec`/`Module.eval` are pyjs's own JS<->Python
bridge (used, per its own `init.js`, for things like the async/webloop
integration) -- xeus-python's actual `execute_request` handling is
implemented in xeus's own C++ interpreter class (calling CPython's C API
like `PyRun_String` directly, compiled into `xpython.wasm`'s `main()`
loop), and no `execute_request`/`interpreter`-named function is exposed
on `Module` at all (`grep -o 'Module\["[a-zA-Z_]*"\]=' xpython.js` finds
nothing named that way) -- meaning the REAL per-cell entry point is
entirely internal to the compiled binary, reached via some other
message-passing mechanism (likely a Web Worker `postMessage` protocol
from jupyterlite-xeus's own JS, not a plain JS function call at all).
**This Node harness cannot currently exercise that real path** -- it can
only call pyjs's own `Module.exec`, which may or may not share the exact
same crash-prone code path as the real per-cell interpreter loop.
Tried switching to `Module.async_exec_eval`/`Module.exec_eval` (pyjs's
own "run a script" functions, closer in spirit to what a REAL kernel
`execute_request` handler might use) instead of plain `Module.exec` to
see if they behave differently -- **both are `undefined`**, because
`init_phase_2` (which defines them) itself aborts partway through on its
own internal `import pyjs` call before reaching that assignment (the
SAME "null function or function signature mismatch" `dynCall_vii` crash
documented above, at a DIFFERENT point in the sequence than the
cross-cell rclpy-object bug -- these may or may not be manifestations of
the same underlying root cause; not yet determined).

**Next step**: get a real, live, connected browser kernel (patience
required, per the earlier-documented Module Federation flakiness -- but
now genuinely worth another attempt, since this is the single most
valuable open question) and test the SAME cell-1-then-cell-2 pattern for
real, in the actual demo.ipynb, to determine whether this cross-cell
crash is a real bug that will need a genuine fix (Emscripten-level, or a
recipe-level workaround reducing dlopen scope) or an artifact specific to
this Node harness's use of pyjs's `Module.exec` bridge rather than the
real kernel's own C++ execution path.

### Follow-up, same session: found and used the REAL xeus kernel entry
### point (not pyjs's `Module.exec` bridge) -- same underlying bug
### confirmed present there too, and it's a KNOWN, longstanding,
### unresolved Emscripten limitation, not something specific to this
### project

**Found the actual production entry point.** `xeus-lite`'s
`include/xeus-lite/xembind.hpp`/`src/xembind.cpp` expose a real
`Module.xkernel` JS class via embind (`xeus::export_kernel<interpreter_type>
("xkernel")`, instantiated in xeus-python's own `src/main_wasm.cpp`) with
`.start()` and `.get_server()`; the returned server object has
`.notify_listener(js_message)`, which for `{channel: "shell", header:
{msg_type: "execute_request", ...}, content: {code, ...}}` calls straight
into `xserver_emscripten::notify_shell_listener` -- **this is exactly
what jupyterlite-xeus's own JS calls for every real notebook cell
execution**, not pyjs's `Module.exec`. Built a harness
(`test_real_kernel.mjs`) that constructs a real `xkernel`, stubs
`self.postMessage`/`self.get_stdin` (the two JS globals
`xserver_emscripten` calls out to, normally provided by the browser's Web
Worker context) to log replies instead, and sends real `execute_request`
messages for cell 1 and cell 2 content.

**Result: neither cell crashes with the "null function"/`Aborted()`
symptom via this real path** -- both come back with a clean
`execute_reply`. But both ALSO fail, with a different, very telling
error: `RuntimeError: no running event loop` from
`xeus_python_shell/shell.py`'s `run_cell_async` (`asyncio.get_running_loop()`
inside `XPythonLoopRunner.__call__`). Traced this to `pyjs/webloop.py`
(imported as a side effect of the bare `import pyjs` that
`wasm_interpreter::configure_impl()` does via `py::module::import("pyjs")`
during `kernel.start()`): its module-level code does
`asyncio.set_event_loop_policy(WebLoopPolicy())` and, since
`PYJS_DONT_AUTOSTART_EVENT_LOOP` isn't set, constructs a `WebLoop()` --
whose own `__init__` immediately calls `asyncio._set_running_loop(self)`.
So there SHOULD be a running loop by the time `kernel.start()` returns.
Confirmed directly (bypassing rclpy and the real kernel entirely, testing
via two separate plain `Module.exec()` calls) that this genuinely doesn't
persist: `import pyjs` succeeds, but a LATER separate exec call's
`asyncio.get_running_loop()` still raises `RuntimeError: no running event
loop` -- **the exact same shape of bug as the rclpy-object crash, just
manifesting as "state silently reverted to unset" instead of a hard
abort**, because asyncio's own running-loop bookkeeping degrades
gracefully where pybind11's does not.

**This unifies the whole investigation into one theory**: whatever
Asyncify/Emscripten does between separate top-level calls into the wasm
module (`Module.exec()` calls, OR real `notify_listener()` calls -- both
exhibit it, ruling out "it's specific to pyjs's bridge") resets or
invalidates some form of call-scoped state that several different
subsystems depend on being persistent: pybind11's own type/instance
registry (crashes hard when touched) and CPython's asyncio running-loop
marker (silently reverts, since asyncio's `RuntimeError` path is a normal,
graceful check rather than a crash). Tested and ruled out one concrete
candidate mechanism: emscripten's `noExitRuntime`/`EXIT_RUNTIME` runtime-
teardown-after-`main()`-returns behavior (`Module.noExitRuntime = true`
passed at module-construction time) -- made no difference, so it isn't
simply that. The true mechanism is still unidentified at the Emscripten
internals level.

**Researched via web search: this is a real, known, longstanding,
UNRESOLVED category of Emscripten bug, not something specific to this
project's build.** "Function signature mismatch"/"null function" errors
with dynamic libraries (`dlopen`) + Embind are the subject of multiple
long-running, still-open GitHub issues on `emscripten-core/emscripten`
going back years -- e.g. [#13026 "Random 'function signature mismatch'
with dynamic libraries + Embind"](https://github.com/emscripten-core/emscripten/issues/13026),
[#13241](https://github.com/emscripten-core/emscripten/issues/13241),
[#9901](https://github.com/emscripten-core/emscripten/issues/9901),
[#12950](https://github.com/emscripten-core/emscripten/issues/12950),
[#8235 "dlopen: RuntimeError: indirect call signature mismatch"](https://github.com/emscripten-core/emscripten/issues/8235),
[#5337](https://github.com/emscripten-core/emscripten/issues/5337). No
generic, reliable fix is documented across these threads -- reported
causes vary (ABI/signature mismatches for specific parameter/return
types, table-growth races, optimization-level sensitivity) and several
are explicitly described as intermittent/"random." This project is
currently on **emscripten 4.0.9** (`conda_build_config.yaml`'s
`emscripten_emscripten-wasm32` pin) -- a version bump is a large,
untested, many-hour undertaking (the whole toolchain + every package
would need rebuilding) and isn't something to attempt casually; worth
keeping in mind as a possible future avenue if this remains blocking,
but out of scope for this session.

**Where this leaves the project**: `import rclpy` and constructing a
`Node()` are CONFIRMED working, for real, when done together in one
notebook cell (this is a genuine, first-time milestone this marathon).
Using the node/rclpy objects from a LATER, separate cell currently does
not work, for what looks like a real, upstream Emscripten limitation
around dynamic-linking + Embind/pybind11 state persistence across
separate top-level wasm entry points -- not a bug in this project's own
recipes, patches, or ROS packages.

**Correction, tested immediately after via the real `xkernel`/
`notify_listener` path**: the "single-cell workaround" idea above does
**not** actually hold up for the real kernel. Sent the ENTIRE combined
cell 1+2+3 content (`import rclpy` through `pub.publish(msg)`) as ONE
`execute_request` via the real `notify_listener()` -- it still hits
`RuntimeError: no running event loop`, on this very first and only
`notify_listener()` call. This clarifies the actual mechanism: `pyjs`'s
webloop gets set up during `configure_impl()`, which runs as part of the
**`kernel.start()`** call -- a call that is necessarily SEPARATE from
whatever later call runs `notify_listener()`, no matter how the
notebook's own cells are organized. So the earlier "everything in one
`Module.exec()` call works" result was specific to pyjs's own simplified
`exec()` bridge (which never touches `asyncio.get_running_loop()` at
all) -- it does not carry over to the real kernel's actual
`xeus_python_shell.run_cell_async` mechanism, which needs a running
event loop for EVERY cell, starting with the very first one. **There is
currently no known single-cell or multi-cell workaround** -- this is a
real blocker on the real kernel path specifically, distinct from (but
likely sharing a root cause with) the rclpy cross-cell crash found via
`Module.exec`. Next avenue, not yet tried: see whether the event loop can
be (re-)established from WITHIN the same call as `notify_listener` itself
-- e.g. patching `xeus_python_shell`'s `run_cell_async`/`XPythonLoopRunner`
to defensively call `asyncio.set_event_loop(pyjs.webloop.WebLoop())`
(or check-and-recreate) right before use instead of assuming a loop
already exists from a previous call, since creating a `WebLoop()` is
cheap and its own `__init__` self-registers as the running loop
immediately.

**Tried this immediately -- doesn't work, and reveals mixing the two
entry points is itself unsafe.** Attempted to inject exactly this
defensive patch via a `Module.exec()` call sandwiched between
`kernel.start()` and `server.notify_listener()` (same process, same
kernel instance). **The `Module.exec()` call itself crashed** --
`RuntimeError: memory access out of bounds` -- merely from importing
`pyjs.webloop`/`xeus_python_shell.shell` fresh and defining a function,
nothing pybind11-instance-specific this time. So it's not only "touching
an existing pybind11 object across calls" that's unsafe -- **any
`Module.exec()` call made after `kernel.start()` has already run seems to
inherit the same instability**, suggesting `kernel.start()`'s own
internal `configure_impl()` (which itself does real Python-level work
via this same class of call) leaves the runtime in a state where pyjs's
simplified exec bridge specifically can no longer be used safely
afterward -- a further wrinkle, not yet fully understood. **Do not try
to patch Python-side behavior via `Module.exec()` after `kernel.start()`
as a workaround** -- confirmed unsafe. Any future fix attempt for the
event-loop issue needs to happen either (a) inside `xeus_python_shell`'s
own source *before* it's packaged (a real code change, rebuilt into the
package) rather than injected at runtime, or (b) inside the C++
`configure_impl()`/kernel-startup path itself.

**Tried (a) for real -- a genuine, rebuilt-into-the-package patch, not a
runtime injection.** Added `patches/xeus_python_shell-defensive-event-
loop.patch` to the demo repo (wired into `demo_env_build/build.sh`
alongside the other 3 existing `xeus_python_shell`/`rclpy`/`pyjs`
patches), rewriting `XPythonLoopRunner.__call__` to catch
`RuntimeError` from `asyncio.get_running_loop()` and construct a fresh
`WebLoop()` instead of assuming a prior call's setup persisted. Rebuilt
`demo_env_build` + `jupyterlite-content` through the real pipeline and
retested via `test_real_kernel.mjs` (the real `xkernel`/`notify_listener`
path).

**Result: confirms the patch code path IS reached (progress), but
uncovers something even more fundamental.** The error changed from `no
running event loop` to `ModuleNotFoundError: No module named 'js'`,
raised from `pyjs/webloop.py`'s own top-level `import js` -- meaning the
`except RuntimeError` branch correctly fired, but `import pyjs.webloop`
(the fallback) re-executes that module's top-level code fresh, which
fails. Revised the patch to check `sys.modules.get('pyjs.webloop')`
first and only fall back to a real `import` if not already cached
(reasoning: reuse the module object from the SUCCESSFUL earlier `import
pyjs` in `configure_impl()`, whose own globals -- including its already-
resolved `js` reference -- should still be valid, sidestepping a fresh,
fragile `import js`). Rebuilt and retested again -- **still exactly the
same `ModuleNotFoundError`, at the SAME fresh-import line**, meaning
`sys.modules.get('pyjs.webloop')` returned `None`. **This means
`sys.modules` itself does not reliably carry the `pyjs.webloop` entry
from the `kernel.start()` call into the later `notify_listener()` call**
-- a stronger and more fundamental version of the persistence problem
than what the `Module.exec()`-only tests suggested (those showed
`sys.modules` entries DO persist across separate `Module.exec()` calls,
e.g. `'rclpy.context' in sys.modules` reliably returned `True` in a later
call). The discrepancy suggests `kernel.start()`'s C++-side
`py::module::import("pyjs")` (called via pybind11's own `gil_scoped_acquire`
API, not through pyjs's JS `Module.exec` bridge at all) and pyjs's own
JS-driven exec path may not be fully sharing the same persistence
guarantees, even though both ultimately run in the one embedded CPython
interpreter -- exactly why is still unresolved.

**Status of this patch**: left in place (it's strictly an improvement --
it now fails with a clearer, more specific `ModuleNotFoundError` instead
of the more generic `no running event loop`, and is harmless/inert on any
future build where the underlying persistence issue gets fixed some
other way, since the `try` branch is a no-op whenever a loop is already
running). **Not a working fix on its own.** This whole event-loop/
`sys.modules`-persistence rabbit hole is now understood to be deeply
intertwined with the SAME root-cause class as the earlier rclpy-object
crash and the `init_phase_2` "null function" crash -- all three are
different symptoms of state not reliably surviving across separate
top-level entries into the compiled kernel, which independent web
research confirms is a real, longstanding, still-unresolved category of
Emscripten bug with dynamic libraries (`dlopen`) + Embind (see the
GitHub issue links above). **Stopping the deep C++/Emscripten-internals
investigation here for this session** -- further progress most likely
needs either genuine Emscripten-level expertise/upstream engagement, or
a fundamentally different build strategy (e.g. reducing reliance on
`dlopen` for this many side modules). The `import rclpy` + `Node()`
success (confirmed working end-to-end in one `Module.exec()` call) and
the `pyjs-rt`/NumPy-CMake/Asyncify-chain fixes earlier in this file
remain solid, real, shipped progress regardless of this remaining
blocker.

### CONFIRMED 2026-09-13: the "null function" crash reproduces in a real,
### live browser kernel too -- not specific to the Node harness

The user opened `http://127.0.0.1:8880/lab/index.html?path=demo.ipynb`
directly in their own real browser (the same freshly-rebuilt deployment,
with the pyjs-rt fix, the `ASYNCIFY_STACK_SIZE` bump, and the
`xeus_python_shell` defensive event-loop patch all applied) and hit
`RuntimeError: null function` **before even trying to execute a cell** --
i.e. during kernel startup/bootstrap itself, matching the exact
`init_phase_2` "null function or function signature mismatch" crash
documented above (`Module.exec`'s own internal `import pyjs` call, inside
`bootstrap_from_empack_packed_environment`). **This resolves the open
question from earlier in this file definitively: it is NOT specific to
this session's Node.js harness.** It's a real bug that manifests in an
actual, live, browser-connected xeus-python kernel. Combined with
everything else found this session (the same class of "state doesn't
persist across separate top-level wasm calls" issue affecting pybind11
objects, `sys.modules` entries, and asyncio's running-loop marker; the
web-research confirmation that "function signature mismatch"/"null
function" with Emscripten `dlopen` + Embind is a known, longstanding,
unresolved upstream bug class) -- this is now about as thoroughly
triangulated as it can be without either live browser DevTools access to
capture a full stack trace, or genuine Emscripten-internals debugging.

**Got the real browser stack trace (from the user's own DevTools):**
```
Uncaught (in promise) Error: RuntimeError: null function
    at Bg.initialize (654.01688496c997e850.js?v=01688496c997e850:68:20425)
    at async 654.01688496c997e850.js?v=01688496c997e850:54:114975
```
`654.01688496c997e850.js` is the `@jupyterlite/xeus-extension`'s own
webpack chunk (the SAME file whose `visibilitychange`/hidden-tracking
code was found much earlier this marathon) -- i.e. this is **JupyterLite's
own JS kernel-provider code**, not raw wasm-engine output. `Bg` is a
minified class (almost certainly the xeus remote-kernel wrapper class
jupyterlite-xeus uses to drive `xpython.wasm`), and `.initialize()` is
presumably exactly the method that calls into `Module.async_init`/
`bootstrap_from_empack_packed_environment` -- i.e. this confirms the
crash happens during **kernel bootstrap**, called from the real
extension's own initialization path, not something invoked later by a
cell. The browser's own promise-rejection handling caught the original
Emscripten `RuntimeError` and re-threw it wrapped in a plain `Error`,
which is why the deeper `dynCall_vii`/`invoke_vii`/`Asyncify` wasm-level
frames visible in the Node harness's own capture don't show up here --
JS-level try/catch across an async boundary loses the original engine
stack. Still unmistakably the same underlying crash: `init_phase_2`'s
internal `Module.exec('import pyjs...')` call, now confirmed to happen
for real, inside `Bg.initialize()`, in a live browser.

**New, important hypothesis this raises**: if `Bg.initialize()` -- the
kernel PROVIDER's own initialization -- throws uncaught during kernel
startup, that could very plausibly be why the kernelspec never
successfully finishes registering with the shell's `serviceManager`,
which is exactly the symptom this whole marathon has called "the
Module Federation kernel-registration bug" (empty Select Kernel dropdown,
no tile in the New Launcher, etc.). In other words: **the "kernel
registration is flaky" mystery from much earlier in this marathon and
this session's `init_phase_2`/"null function" crash may be the SAME bug,
not two separate ones** -- a provider whose `initialize()` sometimes
throws (perhaps depending on Asyncify/dlopen table-state timing, matching
this session's "state doesn't reliably persist across separate top-level
wasm calls" theme) would look exactly like "sometimes the kernel shows
up, sometimes it doesn't," entirely independent of any genuine Module
Federation singleton-identity issue. This reframes the whole night's
"upstream jupyterlite-core bug, not our problem" framing -- it may
actually be traceable to the SAME class of Emscripten dlopen/Asyncify
issue documented throughout this file, just surfacing earlier (at kernel
*registration* time) than where this session mostly investigated it (at
cell *execution* time). Not yet proven -- would need to correlate several
kernel-connection attempts against whether `Bg.initialize()` throws each
time -- but a strong, parsimonious unifying explanation.

### BREAKTHROUGH 2026-09-13 (autonomous overnight session): root cause
### narrowed to `-sASYNCIFY` on xpython's own MAIN_MODULE -- not rclpy,
### not package count, not anything ROS-specific at all

Per the user's explicit instruction ("start with the vanilla non-ROS
stuff, see if the bug is there, then stepwise add functionality"), built
a pure `xeus-python` + `numpy` vanilla environment (`jupyter lite build`,
31 stock emscripten-forge-4x packages, no local patches/builds at all,
served on port 8879) and tested it with the exact same real-kernel-path
Node harness technique (`Module.xkernel()` -> `.start()` ->
`server.notify_listener()` with real `execute_request` messages, matching
what `jupyterlite-xeus`'s own JS does for every cell).

**Result: the vanilla environment has ZERO trace of this bug.**
`kernel.start()` didn't throw, a real `execute_request` cell executed
cleanly with `status: "ok"`, and -- critically -- a SECOND, separate
`notify_listener()` call (the same cross-top-level-call shape that broke
everything in our own build) saw the identical `pyjs.webloop.WebLoop`
object survive from cell 1 (`asyncio.get_running_loop()` succeeded,
returning the very same `<pyjs.webloop.WebLoop object at 0x2d1e580>`
constructed during `kernel.start()`), plain Python global state (`x`)
persisted, and `async`/`await` worked normally across the separate call.
**This directly falsifies the "fundamental, unfixable Emscripten Asyncify
limitation" conclusion this file drew earlier in the marathon** -- the
underlying mechanism (Asyncify + pyjs + embind + xeus-lite) is NOT
inherently incapable of preserving cross-call state; something specific
to *our* build breaks it.

Next, bisected whether it's about ROS/rclpy specifically or "too many
packages" in general, using our own project's real, already-built
`demo_env` kernel (145 packages, our own patches, port 8880) run through
the identical harness:

- **Same 145-package ROS build, deliberately never touching `rclpy` at
  all** (just `x = 1+1` / asyncio in cell 1, same cross-call asyncio test
  in cell 2): the `init_phase_2` bootstrap crash (`RuntimeError: null
  function or function signature mismatch`, same `dynCall_vii`/
  `invoke_vii` signature as everything else in this file) reproduces
  **during kernel construction itself**, before cell 1 even runs --
  proving this has nothing to do with which Python code a cell executes.
- **Same build, but with a hand-trimmed `empack_env_meta.json` stripping
  every single `ros2-*`-prefixed package** (145 -> 58 packages, serving
  the trimmed manifest from a throwaway local `http.server` on port 8881
  while still fetching real tarballs from the ROS build's own
  `kernel_packages/`): **the crash still reproduces, identically.**
  Zero ROS packages loaded, same crash. This rules out rclpy's dlopen
  chain, rclpy's package count, and "too many total packages" as the
  trigger -- the only thing left in common across every failing test is
  **our own compiled `xpython.js`/`xpython.wasm` binary itself**, versus
  vanilla's stock, unmodified emscripten-forge-4x build.

Diffing our `xeus-python` recipe against upstream
(`extra_recipes/xeus-python/patches/0001-add-asyncify-to-xpython-main-module.patch`,
recipe.yaml's own header comment) shows exactly one substantive
difference: **we add `-s ASYNCIFY` (+ `ASYNCIFY_STACK_SIZE=131072`) to
xpython's own MAIN_MODULE link step**, purely so that rclpy's
Asyncify-enabled SIDE_MODULE (`_rclpy_pybind11...so`) can `dlopen()`
without hitting `LinkError: ... Import #71 "env" "__asyncify_state":
imported mutable global must be a WebAssembly.Global object` -- Asyncify's
dynamic-linking support requires a shared `__asyncify_state` global that
only exists when the *hosting* MAIN_MODULE also has Asyncify enabled.
Vanilla's stock xeus-python has no Asyncify on its main module at all
(and never loads anything that needs it). **This lines up exactly** with
the web-researched known bug class (Embind + `dlopen` + Asyncify
indirect-function-table corruption, e.g.
`emscripten-core/emscripten#13026`) -- except now the trigger looks like
it's simply *"xpython's own compiled code is Asyncify-instrumented at
all,"* independent of whether any Asyncify SIDE_MODULE is ever actually
dlopen'd.

**In progress at time of writing**: kicked off an isolated single-package
diagnostic build (`scratch_test_recipes/xeus-python-noasyncify/`, package
renamed `xeus-python-noasyncify-test` to avoid cache collision with the
real `xeus-python` build) -- identical to our real recipe except the
`-s ASYNCIFY`/`ASYNCIFY_STACK_SIZE` block is removed from xpython's link
options (the `-fexceptions`-vs-`-fwasm-exceptions` fix is kept, since
that's unrelated and needed regardless). Building via a direct
`rattler-build build -r <recipe>` (not the full vinca pipeline) against
the existing `output/` local channel + the same remote channels the real
build uses, logged to `/tmp/xeus_python_noasyncify_build.log`. Once built,
the plan is to re-run the same trimmed-meta (no-rclpy) harness test
against this new binary: if the crash disappears, this is definitively
confirmed as the root cause, and the real fix becomes "find a way to
satisfy rclpy's SIDE_MODULE `__asyncify_state` import requirement WITHOUT
Asyncify-instrumenting xpython's own MAIN_MODULE" (e.g. hand-supplying a
dummy `__asyncify_state` WebAssembly.Global via a small pre-js shim,
rather than a real `-sASYNCIFY` compile) -- a much narrower, more
tractable problem than "Asyncify+Embind+dlopen is fundamentally broken."

**RETRACTED same session**: the isolated no-Asyncify diagnostic build
(`xeus-python-noasyncify-test`) finished and was tested against the same
trimmed (no-`ros2-*`) 145->58-package harness. **The crash still
happens** -- different surface error
(`TypeError: getWasmTableEntry(...) is not a function`, thrown from a
plain `invoke_vii` wrapper instead of Asyncify's `dynCall_vii`), but
confirmed to be the exact same underlying phenomenon: `xpython.js`'s own
`getWasmTableEntry = funcPtr => { ... wasmTable.get(funcPtr) ... }`
returns `undefined` when the table slot is empty, and calling `undefined
(...)` produces exactly this message -- i.e. this is still "indirect call
landed on a null/unpopulated wasm table slot," just observed via the
codepath Emscripten uses when Asyncify is off instead of the
Asyncify-specific `dynCall_*` path used when it's on. **This falsifies
"-sASYNCIFY on xpython's own MAIN_MODULE is the root cause"** -- removing
it did not fix anything, it just changed which JS wrapper reports the
same table-corruption symptom. Downstream behavior was also identical
(cell1/cell2 still hit `ModuleNotFoundError: No module named 'js'` from
the same defensive-loop-runner fallback, for the same reason: whatever
broke during `init_phase_2` still leaves `pyjs.webloop` never properly
cached).

**Corrected next hypothesis**: the differentiator is NOT the Asyncify
flag specifically -- it's something about *this project's own locally
rebuilt* `xeus`/`xeus-lite`/`pyjs-dev`/`pyjs-rt`/`python` packages (all
required host/run deps of xeus-python, all locally recompiled through
this project's own recipes, none of them stock emscripten-forge-4x
binaries) versus vanilla's 100% stock, unmodified upstream build of the
same stack. The next most suspicious remaining difference: `xeus`'s own
`WasmBuildOptions.cmake` is patched project-wide (see `extra_recipes/xeus`)
to swap the hardcoded `-fwasm-exceptions` for the JS-based `-fexceptions`
mechanism (`DISABLE_EXCEPTION_CATCHING=0`, `SUPPORT_LONGJMP=emscripten`) --
originally justified as "Asyncify can't handle wasm-native exceptions,"
but xpython's own patch applies this SAME swap to itself independent of
Asyncify, and it was left in place in the no-Asyncify test build above
(deliberately, thinking it was "unrelated"). Since the crash persisted
even with Asyncify fully removed, this exception-handling-mechanism swap
(rather than Asyncify) is now the leading suspect -- it changes which
system libc++abi/libunwind/compiler-rt variant every C++ object in the
whole chain links against, a much more fundamentally invasive ABI-level
change than a single link flag, and is applied project-wide (via vinca's
`EMCC_CFLAGS` override), not just to xpython. Next diagnostic step:
build xeus-python with NEITHER `-sASYNCIFY` NOR the `-fexceptions` swap
(i.e. as close to true stock upstream recipe as this project's own
locally-rebuilt `xeus`/`xeus-lite`/`pyjs-dev` host deps allow) and re-run
the same trimmed-meta harness test. If that also still crashes, the bug
lives in `xeus`/`xeus-lite`/`pyjs-dev`'s own local rebuild itself (a
toolchain/version/config difference from whatever vanilla's `jupyter
lite build` actually downloaded), not in xeus-python's patch at all --
worth diffing `extra_recipes/xeus`'s patch and confirming vanilla's exact
`xeus`/`xeus-lite` build+version match ours before going further.

**Further update, same session**: the "no source patches at all" diagnostic build
(`xeus-python-nopatch-test`) produced **byte-identical compiled output** to the
no-Asyncify build (same `wasm://wasm/03da3316` hash, same crashing function offsets) --
i.e. xeus-python's own patch is provably inert/redundant once xeus's own (locally
rebuilt) `WasmBuildOptions.cmake` macro already applies the `-fexceptions` swap
project-wide. This means neither of xeus-python's own two patch mechanisms
(Asyncify, or its own redundant exceptions-flag-stripping) is the differentiator --
confirming the true difference has to be inside `xeus`/`xeus-lite`/`pyjs-dev`'s own
locally-rebuilt binaries (all three are HOST/build-time deps of xeus-python; `xeus`
specifically also ships as a standalone dlopen'd `libxeus.so` sitting loose in the
kernel root next to `xpython.js`, confirmed present in both vanilla's and our own
build's output directories, different file sizes: 289KB stock vs 372KB ours).

Attempted a zero-recompile test: served vanilla's own (working) `xpython.js`/`.wasm`
unchanged, but substituted **our own locally-rebuilt `libxeus.so`** in place of
vanilla's stock one (same runtime-fetch mechanism, no meta.json involvement since
`libxeus.so` is dlopen'd from a fixed relative path, not part of the empack package
list). Result: a DIFFERENT failure again --
`Dynamic linking error: cannot resolve symbol invoke_ii`, thrown immediately inside
`new Module.xkernel()`'s C++ constructor (`__ZN4xeus30make_in_memory_history_managerEv`).
This is a straightforward ABI mismatch, not the same table-corruption bug: our
`libxeus.so` was compiled expecting the exception-safe `invoke_ii` JS runtime helper
(from the `-fexceptions`/`DISABLE_EXCEPTION_CATCHING=0` swap), which vanilla's own
MAIN_MODULE (built without that swap) never generates/exports. **This specific
cross-build `.so` swap test is invalid/inconclusive** -- the host main module and a
dlopen'd `.so` must share the same exception-handling ABI configuration to link at
all, so this only proves the two builds use incompatible ABI configurations, not
which one causes the original crash.

To get a valid, apples-to-apples comparison, forced `rattler-build` to resolve
**genuinely stock, unmodified upstream `xeus`/`xeus-lite`/`pyjs-dev`/`python`** as
xeus-python's host deps (rattler-build was, by default, implicitly treating its own
`./output` directory as a searchable local channel even when not passed via `-c`,
so every previous "diagnostic" build had silently kept re-resolving our own local
rebuilds regardless of intent -- fixed by passing `--output-dir <fresh empty dir>`,
which stopped the implicit local-channel pickup and let the remote
`emscripten-forge-4x` stock builds win the solve: confirmed `xeus 6.0.5 h0b0027f_0`,
`xeus-lite 5.0.0 h0b0027f_0`, `pyjs-dev 4.0.6 py313h06ab7c0_0`,
`python 3.13.1 h_2efca29_11_cp313` -- all matching vanilla's exact build strings).
This new build (`xeus-python-stockdeps-test`, recipe under
`scratch_test_recipes/xeus-python-stockdeps/`, same zero-source-patch CMakeLists.txt
as the `-nopatch-test` build) is the first real test of "is it xeus-python's own
code/config, or is it xeus/xeus-lite/pyjs-dev's own rebuild" with a truly controlled
comparison. In progress at time of writing (log:
`/tmp/xeus_python_stockdeps_build2.log`) -- check the result and update this section
accordingly. If it builds clean and the crash disappears when tested via the same
trimmed-meta harness, that pins the bug definitively on our own `xeus`/`xeus-lite`/
`pyjs-dev` rebuild (worth then bisecting those three individually the same way); if
it still crashes, that would mean even xeus-python compiled with zero patches AND
against genuinely stock host deps still breaks merely by being recompiled fresh
(pointing at something in the *toolchain/environment* -- e.g. a different emscripten
patch version, a non-reproducible codegen difference, or a compiler-flag/environment
variable this project's build sets globally that vanilla's `jupyter lite build` never
sees -- worth checking vinca's/this repo's global `EMCC_CFLAGS`/`CXXFLAGS` exports
that apply to every build in this environment, not just recipe-level patches).

**Further update, same session (this is now the leading hypothesis)**: the
`xeus-python-stockdeps-test` build (zero xeus-python patches, genuinely stock
`xeus`/`xeus-lite`/`pyjs-dev`/`python` host deps) **still crashed**, identical
"null function or function signature mismatch" signature, this time with a
very telling frame in the trace: `_PyEM_TrampolineCall_JavaScript` -- a
CPython/Emscripten Python<->JS trampoline detail, not xeus-specific at all.

While chasing this, ran a genuinely clean zero-recompile control test: took
vanilla's own WORKING `xpython.js`/`.wasm` completely unchanged, and
substituted ONLY the runtime `python` package (the empack-fetched
interpreter+stdlib tarball) for **our own locally-rebuilt one**
(`python-3.13.1-h_0e8c188_101_cp313`, same build used in every ROS-side test
throughout this file). **Result: no crash at all** -- `init_phase_2` bootstrap
completed cleanly, cell1 and cell2 both executed with `status: "ok"`, and the
exact same `pyjs.webloop.WebLoop` object survived the separate `notify_listener()`
call (cross-cell asyncio persistence intact). This clears our own "python"
runtime package as a suspect too, and -- combined with the stockdeps-test
result above -- means the differentiator is not any *package* at all (not
rclpy, not python, not xeus/xeus-lite/pyjs-dev's *precompiled binaries*), but
something in how xeus-python's own **compile step** happens in this project,
even independent of any recipe.yaml patch.

Root-caused (pending final confirmation) to `extra_recipes/xeus-python/build.sh`
itself -- specifically this line, present unconditionally (i.e. NOT part of
the now-proven-irrelevant CMakeLists.txt patch, and copied verbatim into every
scratch diagnostic recipe used in this file so far, meaning **every single
diagnostic build in this file up to and including `stockdeps-test` was
unknowingly still affected by it**):
```
export EMCC_CFLAGS="${EM_FORGE_CFLAGS_BASE:-}"
```
`EM_FORGE_CFLAGS_BASE` is never actually defined anywhere in this project (grep
confirms zero matches outside this exact line and its 3 sibling copies in
`xeus`/`xeus-lite`/`pyjs-dev`'s own `build.sh` files -- see AGENTS.md's earlier
"xeus" package fix section, ~line 411). So `"${EM_FORGE_CFLAGS_BASE:-}"` always
evaluates to the **empty string**, silently wiping the emscripten-forge
toolchain's own default `EMCC_CFLAGS="... -fwasm-exceptions"` for every
compilation unit in the package -- not "resetting to a project base" as the
surrounding comments imply, but unconditionally disabling exception handling
codegen project-wide across all four locally-rebuilt packages. Every one of
this session's "controlled" tests recompiled xeus-python fresh each time
(since that's the package under direct test), so every one of them silently
carried this same override regardless of which CMakeLists.txt patch was
present or absent -- explaining why removing Asyncify, removing the redundant
exceptions patch, and even using stock host deps all failed to fix anything:
none of those tests ever restored real exception-handling codegen to
xpython.wasm's own compile, which is the one thing genuinely different from
vanilla's true stock build in every test run so far.

Kicked off `xeus-python-truestock-test` (`scratch_test_recipes/xeus-python-truestock/`):
identical to `xeus-python-stockdeps-test` (zero CMakeLists patch, stock host
deps via `--output-dir`) but with the `export EMCC_CFLAGS=...` line deleted
from `build.sh` entirely, letting the toolchain's real default
(`-fwasm-exceptions`) flow through untouched -- as close to vanilla's true
stock build as this project's own build.sh can get. In progress at time of
writing (log `/tmp/xeus_python_truestock_build.log`); check the result and
update this section. If this build's crash disappears, that's the real,
final root cause: **not a source patch at all**, but an environment-variable
override in `build.sh` (present in FOUR packages: xeus, xeus-lite, pyjs-dev,
xeus-python) that was clearly *intended* to reset `EMCC_CFLAGS` to some
"project base" value but, due to `EM_FORGE_CFLAGS_BASE` never being defined,
actually just deletes it -- and this in turn means all four locally-rebuilt
packages have been compiled with inconsistent/absent exception-handling
codegen this whole time, most likely producing the subtle indirect-call
dynamic-linking table corruption seen throughout this file. The real fix
would then be startlingly simple compared to everything explored above:
either define `EM_FORGE_CFLAGS_BASE` properly (to whatever the toolchain
activation script actually sets, i.e. effectively a no-op reset), or simply
delete these four redundant/broken `export EMCC_CFLAGS=...` lines outright,
and separately re-solve the ACTUAL problem the exceptions patch was trying to
fix (Asyncify vs wasm-native-EH incompatibility for the `xpython` MAIN_MODULE
specifically, which is a real, narrower, already-well-understood issue --
see the very first patch comment in
`extra_recipes/xeus-python/patches/0001-...`) as a properly-scoped,
target-specific fix instead of a project-wide environment-variable stomp.

**RETRACTED again, same session**: the `xeus-python-truestock-test` build (stock
host deps + `build.sh`'s `EMCC_CFLAGS` override deleted entirely) produced a
**byte-identical wasm hash** (`03c355f6`) to `stockdeps-test` and hit the exact
same crash. Deleting that line changed *nothing* -- directly disproving the
`EMCC_CFLAGS`/`EM_FORGE_CFLAGS_BASE` hypothesis. In hindsight this makes sense:
that env var only affects flags CMake doesn't already set explicitly per-target,
and apparently doesn't reach xeus-python-wasm's own compile units in a way that
changes codegen either way in this toolchain.

**New, cleaner zero-recompile control tests, same session**: swapped OUR
locally-rebuilt `pyjs-rt` package (and separately, earlier, `python`) into
vanilla's completely unmodified, working `xpython.js`/`.wasm` + vanilla's own
meta.json (only the one package entry changed each time). **Neither reproduces
the crash** -- both work perfectly, cross-cell state persists correctly. So
`python`, `pyjs-rt`, and (separately) the absence/presence of ROS/rclpy
packages are now ALL cleared. The one earlier "positive" swap
(`libxeus.so`) was invalid/inconclusive (ABI mismatch: our `libxeus.so` expects
`invoke_ii`, an exception-safe JS helper vanilla's own main-module runtime
never generates -- a straightforward link-time ABI incompatibility between
main module and side module exception-handling configuration, not evidence of
the actual table-corruption bug).

Stepping back: **five separate local recompiles of xeus-python this session**
(original w/ Asyncify+patches, no-Asyncify, no-patch, stock-host-deps,
stock-host-deps+no-EMCC_CFLAGS-override) **ALL reproduce the identical crash**
-- two of them (`stockdeps-test`/`truestock-test`) even compiled to
byte-identical wasm. Meanwhile **every zero-recompile runtime-package swap
into vanilla's untouched, remotely-built binary succeeds**. The common thread
across all five failing builds: every one was compiled fresh, locally, by
*this machine's own emscripten-forge-4x toolchain install* -- none of them
tested whether merely recompiling xeus-python's own C++ sources locally
(with an otherwise 100% byte-for-byte-identical upstream recipe) reproduces
the bug regardless of any of this project's modifications at all. That's the
one variable never yet isolated: **local recompilation itself**, independent
of source changes.

Fetched the ACTUAL, current `emscripten-forge/recipes` upstream `xeus-python`
recipe.yaml + build.sh verbatim via `gh api` (not this project's copy) to run
that exact test. Found one more real, previously unexamined difference in the
process: upstream's real `build.sh` does `rm -f $PREFIX/bin/python*` ("remove
all the fake pythons") with NO `-DPYTHON_EXECUTABLE`/`-DPython_EXECUTABLE`
hints at all, while our `build.sh` explicitly skips that deletion and adds
those hints instead (per our build.sh's own comment, reasoning the deletion
would break subsequent `emcc`/`em++` wrapper scripts that need `$PREFIX/bin/
python` to exist) -- genuinely different CMake python-resolution code paths,
never controlled for in any test so far. Neither upstream's nor our build.sh
touches `LDFLAGS`/`EMCC_CFLAGS` in this pure-upstream version (further
confirming the earlier `EMCC_CFLAGS` theory was a dead end).

Kicked off `xeus-python-pureupstream-test`
(`scratch_test_recipes/xeus-python-pureupstream/`): the verbatim upstream
recipe.yaml + build.sh (only the package name changed, to avoid a cache
collision, and `pyjs >=4.0.6` -> `pyjs-dev >=4.0.6` since this project's local
channel never built the aggregating `pyjs` meta-package, only `pyjs-rt`/
`pyjs-dev` separately -- an inert substitution, same underlying dev package
either way), built with `--output-dir <fresh dir>` to force genuinely stock
host deps, exactly as done for `stockdeps-test`/`truestock-test`. In progress
at time of writing (log `/tmp/xeus_python_pureupstream_build.log`) -- this is
the cleanest possible test of "is this project's build even the problem, or
does simply recompiling xeus-python locally on this machine's toolchain
reproduce the bug regardless of any of our own recipe changes." If this ALSO
crashes, the conclusion becomes: **the bug is not caused by anything in this
project's recipes/patches at all** -- it's either a genuine non-determinism in
this specific compiler-optimization-sensitive Emscripten bug class (matching
the "intermittent"/"optimization-level-sensitive" reports from the
web-researched upstream issues earlier this marathon), or a difference between
this machine's exact local emscripten-forge-4x toolchain snapshot and whatever
snapshot emscripten-forge's own CI used the one time it produced the
currently-published stock `xeus-python-0.19.0-py313he5686da_3` binary. In that
scenario, the realistic path forward is probably NOT more bisection of this
project's own patches (already proven innocent five times over) but one of:
(a) accepting the currently-published stock binary as the one known-good
artifact and finding a way to reuse ITS compiled xpython.wasm/js directly
while only swapping in rclpy-specific packages at the empack/runtime level
(no recompilation of xeus-python itself), if rclpy's own `.so` can be made to
dlopen into it without needing MAIN_MODULE Asyncify (this may still hit the
original `__asyncify_state` LinkError, unresolved); or (b) trying a full clean
rebuild from a freshly-fetched emscripten-forge-4x toolchain snapshot to see
if non-determinism is the explanation (re-running the exact same recipe twice
and diffing wasm hashes would settle this quickly).

**Result, and where this line of investigation stops for now**: the verbatim
upstream `build.sh`, completely unmodified, **fails to even configure** on
this machine --
`CMake Error ... Python config failure: Python is 64-bit, chosen compiler is
32-bit` (`$PREFIX/share/cmake/pybind11/FindPythonLibsNew.cmake:224`) -- the
exact bug this project's own `-DPYTHON_EXECUTABLE`/`-DPython_EXECUTABLE`
hints exist to fix. This **confirms this machine's local cross-compilation
environment genuinely differs** from whatever environment emscripten-forge's
CI used to produce the currently-published, working stock `xeus-python`
binary -- our hints are a real, necessary workaround here, not a stylistic
difference, and re-adding them to get a build that actually compiles would
just reproduce `stockdeps-test`/`truestock-test` a third time.

**Consolidated conclusion after 6 local recompiles + 2 zero-recompile
control swaps this session**:
1. Original build (Asyncify + both patches) -- crashes.
2. No-Asyncify -- crashes, byte-identical crash class.
3. No xeus-python patches at all, still against our own xeus/xeus-lite/pyjs-dev -- crashes, wasm byte-identical to #2.
4. Zero patches + genuinely stock xeus/xeus-lite/pyjs-dev/python host deps -- crashes.
5. Same as #4 minus the `EMCC_CFLAGS`-clearing env override -- crashes, wasm byte-identical to #4.
6. Verbatim upstream recipe.yaml+build.sh -- doesn't even configure without reintroducing our own hints (would reproduce #4/#5 again).
- Meanwhile: vanilla's own remotely-built stock binary, untouched, combined
  one-at-a-time with our own locally-rebuilt `python` package, and separately
  our own locally-rebuilt `pyjs-rt` package (both swapped into vanilla's
  otherwise-100%-stock 31-package environment) -- **both succeed perfectly**,
  full cross-cell asyncio/webloop persistence intact.

Every plausible *recipe-content* culprit (Asyncify, the exceptions-mechanism
patch, host-dependency selection, an environment-variable override, upstream
vs. modified build.sh) has now been individually falsified. The only
remaining common factor distinguishing every failing case from every passing
case is: **the failing binary was compiled fresh, locally, by this specific
machine's emscripten-forge-4x toolchain install**, vs. the passing binary
being the one already-published artifact from emscripten-forge's own CI.
This strongly suggests the true root cause is either (a) a real
non-determinism/environment-sensitivity in this well-documented "Embind +
`dlopen` + indirect-call-table" Emscripten bug class (the web research done
earlier this marathon already found multiple upstream issues describing it as
intermittent/optimization-level-sensitive) manifesting differently across
toolchain snapshots, or (b) something genuinely different/stale about this
machine's local emscripten-forge-4x toolchain install (a different exact
emsdk/Binaryen/LLVM point-release than whatever produced the currently
cached, working stock binary) that isn't captured by the nominal version
pins (`emscripten 4.0.9`, etc.) in `conda_build_config.yaml`.

**Recommended next steps for when the user is back** (not pursued further
autonomously -- this has reached the point of needing either a decision from
the user or a fundamentally different kind of evidence than more bisection
builds can provide):
1. **Test toolchain staleness directly**: build the *exact same* recipe
   (e.g. `xeus-python-stockdeps-test`) twice in a row and diff the resulting
   wasm hashes -- if they're non-deterministic run-to-run even with
   completely unchanged inputs, that confirms genuine compiler/optimizer
   non-determinism as the mechanism (matching the "intermittent" reports from
   the earlier web research) rather than something fixed about this
   machine's toolchain specifically.
2. **Try a clean/updated local emsdk**: purge and re-fetch the
   `emscripten-forge-4x` toolchain packages (`emscripten`, `binaryen` if
   pinned separately) fresh, in case the currently-cached local install is
   stale, corrupted, or was itself built from a slightly different upstream
   commit than what's live on the channel today, and re-run
   `stockdeps-test`.
3. **Pragmatic workaround, sidesteps the whole question**: stop trying to
   recompile `xeus-python` locally at all. Use the currently-published,
   working stock `xeus-python-0.19.0-py313he5686da_3` binary directly
   (already confirmed compatible with our own `python`/`pyjs-rt` runtime
   packages), and solve rclpy's dlopen requirement WITHOUT touching
   xpython's own MAIN_MODULE compile: e.g. investigate whether a small
   hand-written pre-js shim can define a dummy `__asyncify_state`
   `WebAssembly.Global` directly (satisfying the SIDE_MODULE's import without
   ever Asyncify-instrumenting xpython's own code), or whether rclpy's own
   `.so` can be linked without needing `-sASYNCIFY` at all if the specific
   code paths JupyterLite actually exercises never hit a genuine blocking
   `rmw_wait` (may be fine for simple init/pub/sub patterns even if
   long-running `spin()` still needs it) -- this was the ORIGINAL, much
   narrower problem before this whole investigation, and may be more
   tractable than continuing to fight local-recompile non-determinism.
4. If neither of the above resolves it, consider filing/searching further
   in the specific upstream `emscripten-core/emscripten` issues already
   identified (#13026 et al.) for anything describing toolchain-version- or
   machine-specific reproducibility, since that would validate hypothesis
   (a) directly.

**Determinism check, final result this session**: rebuilt the exact same
`xeus-python-stockdeps-test` recipe a second time (identical recipe.yaml,
identical `--output-dir`-forced stock host deps, same machine, back to back).
Compared the two artifacts BEFORE any Node-shim patching, via `shasum -a 256`
and `cmp` on the raw extracted files:
- `bin/xpython.js`: **identical** sha256 both runs (the JS glue/runtime
  code is fully deterministic).
- `bin/xpython.wasm`: **different** sha256, and `cmp` finds the first
  byte difference at offset 1,057,813 -- i.e. compilation of the wasm binary
  itself is NOT fully deterministic on this machine/toolchain (expected:
  parallel `ninja`/LLVM link ordering, symbol-table ordering, etc. are common
  non-determinism sources and don't necessarily indicate a problem by
  themselves).
- **Correction to earlier claims in this file**: the `wasm://wasm/03c355f6`
  -style hash string that Node/V8 prints in stack traces is NOT a reliable
  full-content hash -- this second build's `xpython.wasm` differs byte-for-byte
  from the first (confirmed above) yet V8 printed the exact same
  `wasm://wasm/03c355f6` identifier for both. Every earlier claim in this file
  of "byte-identical wasm" based solely on matching `wasm://wasm/...` strings
  (e.g. comparing `no-patch-test` vs `no-asyncify-test`, and `stockdeps-test`
  vs `truestock-test`) should be read as "V8 printed the same identifier,"
  NOT "confirmed byte-identical compiled output" -- those pairs may also have
  differed in bytes elsewhere the same way this pair does. This doesn't
  change the actual conclusions drawn from those tests (all based on the
  crash/no-crash behavior, not the hash matching), but the "byte-identical"
  framing in the write-ups above is not reliably established and should not
  be trusted as strong evidence of anything.
- **The actually decisive part**: ran this second, confirmed-genuinely-different
  compile through the same trimmed-meta (no-rclpy) harness test. **It hits
  the identical crash** -- same `_PyEM_TrampolineCall_JavaScript` frame in the
  `init_phase_2` bootstrap failure, same subsequent `invoke_ii` dynamic-linking
  error when constructing `xkernel`. A build with genuinely different
  compiled bytes elsewhere in the module still reproduces the exact same
  failure mode.

**What this settles**: the crash is NOT simple per-build random luck (if it
were, two builds with confirmed-different codegen would have at least some
chance of landing on opposite sides of working/broken -- instead both broke
identically). This points more toward hypothesis (b) from the recommendations
above: something structurally different between this machine's local
emscripten-forge-4x toolchain (exact emsdk/Binaryen/LLVM commit/build) and
whatever toolchain snapshot emscripten-forge's CI used for the currently-published,
working stock binary -- consistently producing this table-corruption pattern
regardless of the specific (non-deterministic, but immaterial) byte-level
differences elsewhere in each local compile. "Just keep rebuilding until you
get lucky" is NOT a promising workaround based on this evidence (2 for 2
failures with genuinely different binaries) -- pursuing a toolchain-version
comparison/refresh, or the pragmatic "don't recompile xeus-python locally"
workaround, are the more promising remaining options from the recommendations
list above.

**This is where autonomous bisection stops for this session.** Every
recipe-content hypothesis has been individually tested and falsified (7 local
recompiles total now, all crashing; 2 zero-recompile control swaps into
vanilla's stock binary, both succeeding). The remaining open question --
exactly what differs between this machine's toolchain and whatever produced
the working stock binary -- needs either a toolchain-level comparison/refresh
or a decision from the user on which of the recommended next steps to pursue;
further blind local rebuild-and-test cycles are unlikely to add new
information at this point.

### BREAKTHROUGH 2026-09-13 (later the same autonomous session): pursued
### recommendation #2 ("stop recompiling xeus-python, patch the stock
### binary at the JS level instead") to completion -- `import rclpy` and
### `from rclpy.node import Node` now both work against the genuinely
### untouched, remotely-built stock binary, with the "null function" crash
### completely absent

The user's only instruction at this point was "I trust your judgment go for
what you think is best" -- picked recommendation #2 from the list above, on
the reasoning that it sidesteps the whole unresolved toolchain-non-determinism
question entirely rather than trying to diagnose it further.

**Result: this worked, completely.** Bootstrapped the STOCK (never locally
recompiled) `xeus-python-0.19.0-py313he5686da_3` binary with this project's
own REAL, full 145-package ROS2 kernel environment (rclpy, rmw_zenoh_pico,
zenoh-pico, every message-type package, all locally built by this project's
own pipeline) via the real `Module.xkernel`/`notify_listener()` kernel path,
and got a real notebook cell to successfully run:
```python
import os
os.environ['RCL_LOGGING_IMPLEMENTATION'] = 'rcl_logging_noop'
os.environ['RMW_IMPLEMENTATION'] = 'rmw_zenoh_pico'
import rclpy          # -> "rclpy imported OK"
from rclpy.node import Node   # -> "Node imported OK"
```
with **zero trace of the "null function"/table-corruption crash** that
consumed the entire rest of this file's investigation -- confirming, as
strongly suspected, that the crash really was specific to *locally recompiling*
xeus-python on this machine, and had nothing to do with rclpy, ROS2 packages,
or anything about this project's own recipes/patches.

Getting there needed four small, well-understood JS-level patches applied
directly to the stock `xpython.js` (NOT a recompile -- the `.wasm` binary
itself is never touched, only its JS glue code), now packaged as a reusable,
documented script:
**`~/robot/ros2-emscripten-zenoh-demo/patches/patch_stock_xpython_js.mjs`**
(run as `node patch_stock_xpython_js.mjs <path-to-stock-xpython.js>`, edits
in place; read the file's own top-of-file comment for the full rationale of
each patch, condensed here):

1. **Fake `__asyncify_state`/`__asyncify_data` globals.** rclpy's own
   compiled extension (`_rclpy_pybind11...so`) is an Asyncify SIDE_MODULE
   (needed elsewhere in this project for `rmw_wait`'s cooperative-polling
   fix) and its wasm import table literally requires
   `env.__asyncify_state`/`env.__asyncify_data` as real
   `WebAssembly.Global` objects at link time (confirmed via `wasm-objdump -x`
   on the .so directly: both are `i32 mutable=1`). The stock main module has
   no Asyncify support at all, so these normally don't exist -- the dynamic
   linker's existing `env` import Proxy (`proxyHandler` in `xpython.js`)
   only auto-synthesizes *function* stubs for missing symbols, not globals,
   which is exactly why the original `LinkError: ... imported mutable global
   must be a WebAssembly.Global object` happened days ago in this
   investigation. Patched the proxy to special-case these two symbols and
   hand back real (dummy, always-zero) globals instead. **This is safe as
   long as the code that would actually need to observe real Asyncify state
   transitions (unwind/rewind across a real cooperative sleep, i.e. the
   deep-blocking-wait path inside `rmw_wait`) is never reached** -- true for
   everything tested so far (import, init, Node construction); would need
   real revisiting before ever relying on genuine blocking `spin()`/`wait()`
   behavior.

2. **Hooked up the real `dlerror` wasm export**, present in the compiled
   binary but never wired to `Module` by the stock build (a harmless,
   narrow fix, used only for readable error messages).

3. **Replaced the eager/bootstrap-time shared-library preload mechanism.**
   The stock build's JS glue calls `Module._emscripten_dlopen_promise` for
   this, which genuinely exists as a raw wasm export (confirmed via
   `WebAssembly.Module.exports()`) but is not wired to `Module` either --
   and, critically, **must not be hooked up the same way `dlerror` was**:
   this function internally relies on real Asyncify unwind/rewind to
   suspend a C call stack across an async fetch, and actually calling it
   on a non-Asyncify host causes a silent, uncatchable hard crash (proven
   by trying exactly that -- the harness process just vanished mid-log,
   `exit 0`, no JS exception at all). Instead, replaced the whole preload
   loop to go through the SAFE, already-correct
   `Module.loadDynamicLibrary()` JS function (used natively by this stock
   build for lazy/on-demand dlopen, which already worked correctly for
   `_rclpy_pybind11.so` and `libmicrocdr.so` before this patch even
   existed) -- with two refinements found empirically:
   - Libraries `libraryType()` classifies as `"local"` (Python
     C-extensions, e.g. any `*.cpython-313-wasm32-emscripten.so`) are
     skipped during eager preload entirely: `loadDynamicLibrary` needs a
     `localScope` object to receive a local library's exports into, which
     the generic per-package preload loop has no way to provide -- routing
     these through it anyway silently discards their exports, leaving a
     stale, symbol-less cache entry that later breaks Python's own
     (separately-working) lazy import of the exact same file with
     `ImportError: dynamic module does not define module export function
     (PyInit_..)`.
   - Libraries classified `"global"` are retried across multiple passes
     (`Module._retryFailedEagerPreloads`, added by the same patch): ROS2's
     typesupport/introspection C++ libraries have circular/cross-package
     template-instantiation dependencies (e.g. `geometry_msgs`'s
     introspection lib needs `builtin_interfaces`'s `Time_<...>` template
     instantiation, `unique_identifier_msgs`'s for `rclpy` itself, etc.)
     and are discovered in arbitrary file-tree order per package, not true
     dependency order -- a single top-to-bottom pass leaves ~10-12 of ~150
     libraries unresolved; repeated passes (the harness calls this with
     `maxPasses=6`) converge to zero failures every time tested.

4. **Extended `readBinary`'s synchronous fallback with a bounded recursive
   virtual-filesystem search** (layered on top of whatever Node-specific
   readAsync/readBinary shim the deployment already needs -- real browsers
   never need this, since they support synchronous XHR natively for this
   exact code path). Needed because some locally-built conda packages (e.g.
   `microcdr`) keep their own versioned top-level directory in the extracted
   tarball (`/microcdr-2.0.2/lib/libmicrocdr.so.2.0.2`) instead of being
   flattened to a standard `$PREFIX` layout (`/lib/libmicrocdr.so.2.0.2`) --
   `loadDynamicLibrary`'s lazy-fetch fallback for a not-yet-preloaded
   dependency doesn't know to look there. Not included in the checked-in
   script (kept as a documented snippet here) since it's Node-harness/test
   -specific plumbing, not part of the actual browser deployment fix.

**New, separate, much narrower next blocker**: `rclpy.init()` (with or
without `signal_handler_options=SignalHandlerOptions.NO`, tried both) now
fails with `thread constructor failed: Resource temporarily unavailable` --
confirmed via `strings` on `_rclpy_pybind11...so` directly that this exact
message and a `pthread_create` reference are baked into **rclpy's own
compiled extension itself**, not zenoh-pico (already correctly built with
`Z_FEATURE_MULTI_THREAD=0`, confirmed by grepping
`extra_recipes/zenoh-pico/build.sh`) or rcl/rmw. This is a real
`std::thread` construction attempt inside `_rclpy_pybind11`'s own C++ code
(most likely something like a graph-change-listener or wait-set
implementation detail -- not yet identified precisely) failing because this
build has no real pthreads support at all, matching this whole project's
original, deliberate architectural choice (see this file's very first
section: pthreads were dropped project-wide in favor of Asyncify-based
cooperative polling). **This is a new, well-scoped, narrow follow-up task**
squarely in this project's own existing pattern of work (c.f. the already
-existing `ros2-emscripten-zenoh-demo/patches/rclpy-node-rmw_zenoh_pico-workarounds.patch`,
a Python-source patch to `rclpy/node.py` that already disables one other
problematic default, `TypeDescriptionService`) -- NOT a continuation of the
Emscripten-toolchain mystery this file spent all night chasing. **Root cause pinned down precisely** (fetched rclpy's actual upstream source
via `gh api repos/ros2/rclpy/contents/rclpy/src/rclpy/signal_handler.cpp`):
`setup_deferred_signal_handler()` (rclpy's C++ `signal_handler.cpp`,
~line 118) unconditionally does
`g_deferred_signal_handling_thread = std::thread([]{ ... });` -- a real
background thread whose job is to `sem_wait()`/block waiting for a
deferred-signal semaphore to be posted from an actual OS signal handler
(SIGINT/SIGTERM), then trigger guard conditions and call
`rclpy::shutdown_contexts()`. Critically, **this thread gets created
regardless of the `signal_handler_options` value passed to `rclpy.init()`**:
`install_signal_handlers(SignalHandlerOptions options)` (~line 582) calls
`setup_deferred_signal_handler()` unconditionally as its very first
statement, and only the SUBSEQUENT `switch(options)` decides which actual
POSIX signals get hooked to notify it -- `SignalHandlerOptions::No` skips
installing any signal, but never skips spawning the background thread that
would have served them. This is exactly why passing
`signal_handler_options=rclpy.signals.SignalHandlerOptions.NO` (tried
explicitly, tested above) made no difference at all.

There is no existing Python- or C++-level API to skip this entirely --
fixing it needs a real source patch to `signal_handler.cpp` itself, in the
same spirit as this project's existing
`ros2-emscripten-zenoh-demo/patches/rclpy-node-rmw_zenoh_pico-workarounds.patch`
(which already disables one other problematic rclpy default,
`TypeDescriptionService`, at the Python level) and as `extra_recipes/zenoh-pico`'s
own `#if Z_FEATURE_MULTI_THREAD==0` conditional-compilation pattern for the
exact same class of problem one layer down the stack. The natural fix: guard
`setup_deferred_signal_handler()`'s body (or the whole function) with
`#if !defined(__EMSCRIPTEN__)` (or a narrower "no real OS signals ever reach
a wasm binary in a browser tab, so this entire subsystem is meaningless
here" argument) so it becomes a no-op on this target, matching how the rest
of this project already treats real OS-level concurrency primitives as
simply unavailable/unnecessary in this environment. This DOES need a real
recompile of `ros2-rclpy` -- but unlike xeus-python, there is currently no
evidence rclpy's own compile is affected by tonight's mysterious
non-determinism (every crash chased all night was specifically about
xeus-python's own compiled output; rclpy's compiled `.so` has behaved
consistently and correctly throughout every test in this file), so a normal
local rebuild of just this one package should be safe.

### BREAKTHROUGH 2026-09-13 (continued, next session): the `signal_handler.cpp`
### patch was written, built, and deployed -- `rclpy.init()` now succeeds --
### and this uncovered the TRUE remaining limit of the "patch the stock
### binary" strategy: a real, unavoidable Asyncify requirement in
### Emscripten's own socket layer, not a bug

User said "Continue, remember to bump the build number." Wrote the patch
exactly as planned above: guarded `setup_deferred_signal_handler()`/
`teardown_deferred_signal_handler()` (in
`~/robot/ros-rolling-emscripten-zenoh/patch/ros-rolling-rclpy.emscripten.patch`,
appended as a third hunk to the existing patch) with `#if defined(__EMSCRIPTEN__)`
to make both complete no-ops on this target. Verified against a pristine
checkout of the exact pinned source (`git show
release/rolling/rclpy/11.0.3-1:src/rclpy/signal_handler.cpp`, from the
already-cached `output/src_cache/rclpy-release.git`) before touching anything
real. Bumped the build number the RIGHT way for a vinca-generated recipe
(NOT by hand-editing `recipes/ros2-rclpy/recipe.yaml`, which is
machine-generated and gets wiped by `pixi run generate-recipes-emscripten`) --
vinca reads a real per-package override from
`~/robot/ros-rolling-emscripten-zenoh/pkg_additional_info.yaml`
(`get_pkg_build_number()` in `vinca/vinca/utils.py`, backed by
`configuration.py`'s load of `pkg_additional_info.yaml`), which already had an
`rclpy: {build_number: 26}` entry from an earlier pthreads-era bump -- bumped
to 27, then regenerated (`pixi run generate-recipes-emscripten`, safe: `recipes/`
is gitignored and fully machine-generated). Verified via this project's own
`check_patches_clean_apply.py --recipe ros2-rclpy` before doing a real build.

First real build attempt failed at CMake CONFIGURE time (`Could not find ROS
middleware implementation 'rmw_wasm_cpp'`) -- unrelated to the patch;
`build_ament_cmake.sh`'s generic vinca template defaults
`RMW_IMPLEMENTATION` to `${VINCA_EMSCRIPTEN_RMW_IMPLEMENTATION:-rmw_wasm_cpp}`,
and invoking `rattler-build` directly on a single recipe (rather than through
`pixi run build-emscripten`) skips the env vars that task's own `[activation]`
section sets. Found the right values in `pixi.toml`'s activation env
(`VINCA_EMSCRIPTEN_RMW_IMPLEMENTATION=rmw_zenoh_pico`,
`VINCA_EMSCRIPTEN_STATIC_TYPESUPPORT_C=rosidl_typesupport_microxrcedds_c`,
`VINCA_EMSCRIPTEN_STATIC_TYPESUPPORT_CPP=rosidl_typesupport_microxrcedds_cpp`),
exported them, and the real build succeeded:
`ros2-rclpy-11.0.3-np2py313hbace3f5_27.tar.bz2`. (Side note: the solver picked
zenoh-pico 1.10.1 from the remote channel this time rather than matching the
deployed environment's own locally-built 1.7.0 -- believed harmless since
rclpy only calls the generic `rmw_*` C API, never zenoh-pico directly; not
yet an issue in testing below, but worth remembering if anything zenoh
-version-sensitive ever misbehaves.)

**Validated the fix directly**: re-ran the same stock-xpython.js +
`patch_stock_xpython_js.mjs` harness from earlier, this time with the new
`ros2-rclpy` build substituted in for the old one (swapped via the same
"edit one `empack_env_meta.json` package entry, serve from a small merged
tarball directory" technique used earlier for the `python`/`pyjs-rt` control
tests) and using the PLAIN `rclpy.init(args=[])` call (no
`signal_handler_options` override needed this time). **Result: `rclpy
imported OK`, `Node imported OK`, and -- for the first time all
session -- `rclpy.init() OK`** with zero trace of the `std::thread`
crash. The patch works exactly as intended.

**New finding, right at the next line (`Node(...)` construction)**: hit
`TypeError: peer.socket.on is not a function` inside Emscripten's own
Node.js WebSocket `SOCKFS.websocket_sock_ops` glue -- a Node-test-harness
-only gap (this build's socket code just references the ambient `WebSocket`
global directly with no `ENVIRONMENT_IS_NODE`-specific handling of its own;
Node 24's *native* global `WebSocket` exists but is browser-style
(`addEventListener`), while this code expects the `ws` npm package's
EventEmitter-style (`.on(...)`) API -- irrelevant for the real deployment,
since real browsers only ever have the browser-style WebSocket this code
is actually written for). Fixed for **testing purposes only** by installing
`ws` (`npm install ws` inside
`~/robot/ros2-emscripten-zenoh-demo/scratch/rclpy_on_stock/`) and setting
`globalThis.WebSocket = (await import('ws')).default` at the top of the
harness before instantiating the module.

**With that Node-only shim in place, hit the TRUE remaining limit**:
```
Please compile your program with async support in order to use asynchronous
operations like emscripten_sleep
```
This is thrown from deep inside Emscripten's own socket-emulation layer
during the real POSIX `connect()` syscall emulation (`___syscall_connect` in
the earlier stack trace) -- **this is a genuine, documented Emscripten
requirement, not a bug in any of this session's patches or in zenoh-pico's
own application-level code**: Emscripten's userspace-socket support
implements a *blocking* `connect()` (as C code expects) by internally
suspending execution until the underlying WebSocket's `open` event fires,
which requires REAL Asyncify support (genuine unwind/rewind across the
suspended C call stack) -- not just the linker-satisfying dummy
`__asyncify_state`/`__asyncify_data` globals this session's
`patch_stock_xpython_js.mjs` supplies. Node()'s constructor sets up a real
zenoh-pico session, which needs to actually open a WebSocket connection to
a router -- there is no way around hitting this specific code path for any
demo that does real pub/sub, unlike everything tested successfully up to
this point (import, init, Node construction itself all complete without
ever needing a real blocking socket operation).

**This is the natural, previously-anticipated limit of the whole "patch the
stock binary instead of recompiling" strategy** (explicitly flagged as a
caveat when the `__asyncify_state` stub was first introduced: "safe as long
as the code that would actually need to observe real Asyncify state
transitions... is never reached... would need real revisiting before ever
relying on genuine blocking spin()/wait() behavior") -- we now know exactly
where that boundary is (real Asyncify is needed as soon as a genuine
blocking socket `connect()`/read happens, i.e. as soon as a Node actually
talks to a zenoh router), and it is NOT one that a JS-level patch can work
around: this specific need is baked into Emscripten's own C-runtime/socket
implementation, not into any Python or ROS2 code this project controls.
Getting a real, working zenoh connection therefore requires xpython's own
MAIN_MODULE to have genuine, functioning Asyncify support -- which loops
back to the still-unsolved core mystery from earlier this session (every
local recompile of xeus-python, Asyncify-enabled or not, hits the "null
function"/table-corruption bug; only the untouched, remotely-built stock
binary is known to work, and it has no Asyncify at all).

**Where this actually leaves the project**: this is genuine, substantial,
validated progress -- `import rclpy`, `rclpy.init()`, and `Node()`
construction (right up to, but not including, opening its zenoh session's
network connection) all work end-to-end against the real, deployed package
set, with zero xeus-python recompilation and a real, upstream-quality rclpy
source patch. The remaining gap is precisely bounded: making a genuine
network-connected ROS2 demo work in this browser/JupyterLite target
requires SOMETHING to provide working Asyncify semantics in xpython's own
MAIN_MODULE (recompiling xeus-python locally still hits the unresolved
non-determinism from earlier this session; that mystery was never solved,
only avoided). Concrete options for a future session, in rough order of
promise: (1) revisit the toolchain-non-determinism angle now that there's a
SPECIFIC, concrete payoff for solving it (a full working pub/sub demo, not
just avoiding a crash) -- e.g. try building on a different machine/fresh
container to see if the crash is truly machine-specific; (2) investigate
whether zenoh-pico's OWN emscripten WS transport (`_z_ws_emscripten_read`
et al., see this file's very first section) could be changed to avoid the
libc-level blocking `connect()`/read path entirely -- e.g. a non-blocking
connect + manual readiness poll driven from JS/Python, sidestepping
Emscripten's own Asyncify-dependent socket emulation layer altogether,
matching the "cooperative polling from application code" approach already
used for zenoh-pico's ongoing read loop; (3) accept partial functionality
(rclpy usable for everything that doesn't need a live network session --
message type introspection, offline testing, local-only demos) as a
reasonable interim milestone while (1) or (2) are pursued.

**Housekeeping note**: partway through this session the user corrected the
use of `/private/tmp/.../scratchpad` for test harnesses and merged
`kernel_packages` copies ("stop using these temporary checkouts... keep
everything in the robot directory") -- all Node.js test harnesses and
patch-validation scratch work now live under
`~/robot/ros2-emscripten-zenoh-demo/scratch/` (gitignored, added to that
repo's own `.gitignore`), not under `/tmp` or the session scratchpad. See
[[feedback_scratch_work_placement]] (memory) for the durable version of this
guidance.

**How to reproduce/continue from here**: see
`~/robot/ros2-emscripten-zenoh-demo/patches/patch_stock_xpython_js.mjs`'s own
header comment for the exact patch mechanics. To re-run the validating test:
copy a stock `xpython.js`/`.wasm` (e.g. from a fresh `jupyter lite build`
with a plain `xeus-python` environment, or extract them from the
`emscripten-forge-4x` channel's own published `xeus-python-0.19.0` package),
run the patch script on the `.js` file, layer a Node
readAsync/readBinary shim on top (base URL pointing at this project's real
`jupyterlite-content/_output/xeus/demo_env/` server) plus the FS-search
`readBinary` extension from point 4 above, then drive it exactly like every
other harness in this file (`Module.xkernel()` -> `.start()` ->
`server.notify_listener()` with a real `execute_request` running the CELL1
content shown above). For a real browser deployment (not just this Node
test harness), the equivalent integration point would be
`jupyterlite-xeus`'s own build/bundling step -- swap in the stock
`xeus-python` conda package instead of this project's own locally-rebuilt
one, and apply `patch_stock_xpython_js.mjs` to its `xpython.js` as a
post-processing step before publishing to `jupyterlite-content`. Not yet
wired into the real `demo_env_build`/`jupyterlite-content` pipeline --
that's the natural next integration task once the remaining `std::thread`
issue is also resolved (no point rewiring the deploy pipeline for a binary
that still can't complete `rclpy.init()`).

**How to reproduce/continue this test**:
- Vanilla harness: `/tmp/vanilla_jupyterlite_test` (port 8879, `jupyter
  lite build --XeusAddon.environment_file=environment.yml`, pure
  xeus-python+numpy, no local patches) + a Node harness copying
  `_output/xeus/xeus-python-kernel/bin/{xpython.js,xpython.wasm}`,
  patching the Node `readAsync`/`readBinary` shim to point at
  `http://127.0.0.1:8879/xeus/xeus-python-kernel/`, and calling
  `Module.xkernel()`/`.start()`/`server.notify_listener()` directly
  (see any of this session's `test_real_kernel*.mjs` harnesses for the
  exact pattern -- construct `execute_request` messages, stub
  `self.postMessage`/`self.get_stdin`).
- ROS-build harness: same pattern, `xpython.js`/`.wasm` copied from
  `~/robot/ros2-emscripten-zenoh-demo/jupyterlite-content/_output/xeus/demo_env/`
  (served on port 8880 by `site/_serve_local.py`), trimmed
  `empack_env_meta.json` (strip `packages` entries whose `name` starts
  with `ros2-`) served from a throwaway `python3 -m http.server` on a free
  port, `package_tarballs_root_url` left pointing at the real build's own
  `kernel_packages/` (tarball filenames are unaffected by the trim).

## BREAKTHROUGH 2026-09-13 (cont'd) -- pybind11 pin CONFIRMED not the (sole)
remaining blocker; NEW root cause isolated to CPython's own `_PyEM_Trampo-
lineCall_JavaScript` mechanism vs. real-Asyncify synchronous `dlopen()`

Context: after the `pybind11 <3` pin (see the "ROOT CAUSE FOUND 2026-09-13"
section above, and `extra_recipes/xeus-python/recipe.yaml`'s own comment)
fixed the "null function or function signature mismatch" crash for
xeus-python itself, the same pin was applied to `ros2-rclpy` (whose own
`_rclpy_pybind11...so` also links pybind11 unpinned by default) via a
scratch test package `ros2-rclpy-pybind11pin-test` (built locally on this
Mac, `pkg_additional_info.yaml`'s rclpy entry not yet bumped since this
was a throwaway "-test"-suffixed package name, see
`scratch_test_recipes/ros2-rclpy-pybind11pin/recipe.yaml`). Verified via
`strings ... | grep pybind11_internals`: unpinned build 27 uses
`__pybind11_internals_v12_system_libcpp_abi2__` (pybind11 3.x's newer
internals layout); the pinned test build uses
`__pybind11_internals_v5_clang_libcpp_cxxabi1002__` (matches xeus-python's
own now-pinned pybind11 2.13.x) -- so the pin genuinely took effect.

Swapped into the real, fully-fixed xeus-python build 104 test harness
(`~/robot/ros2-emscripten-zenoh-demo/scratch/real_xeuspython_v3/`) and
re-ran the full `import rclpy` CELL1 test: **the `RuntimeError: unreachable`
trap during CELL1, with zero Python output before the crash, was
COMPLETELY UNCHANGED** -- the pybind11 pin for rclpy has no effect on this
specific crash. This means the two pybind11 pins are both independently
correct/necessary (matching ABIs is still the right fix for what it fixes),
but they were never the cause of *this* crash.

**Isolating the real cause** (bisection harness:
`scratch/real_xeuspython_v3/test_rclpy_bisect.mjs`, sends one Python
statement per `execute_request` cell with an explicit
`sys.stdout.flush()` after every print, and installs
`process.on('unhandledRejection'/'uncaughtException', ...)` handlers that
log-and-continue instead of letting Node hard-crash, so subsequent cells
can still run and the harness doesn't need to guess where output was
merely buffered):

1. The crash is not "no output at all" -- CPython's stdout is genuinely
   block-buffered under wasm even mid-statement; the real xeus iopub
   `stream` messages (`self.postMessage`) are the reliable place to check
   for printed output, not the harness's own low-level `Module.print`
   hookup (which is NOT what carries Python's `print()` output in this
   build -- that goes through xeus's own C++-side stdout capture /
   iopub streaming instead). Always check `[kernel->frontend]` /
   `msg_type":"stream"` lines, not `[stdout]` lines, when debugging cell
   output in this harness family from now on.
2. Splitting `import rclpy` into a standalone cell, THEN into an even
   more minimal reproduction (`import ctypes; h =
   ctypes.CDLL('/lib/python3.13/site-packages/rclpy/_rclpy_pybind11...so')`)
   confirmed the trap is specifically at the `dlopen()` call itself (via
   ctypes, which uses the exact same libc `dlopen()` CPython's own
   extension-module import machinery uses) -- not at any later pybind11
   method-call/runtime-ABI issue, since we never get that far.
3. Ruled out "missing shared library on the search path" as the cause:
   built a full `needed_dynlibs` list from the target `.so`'s own
   `dylink.0` custom section (`wasm-objdump -x <so> | grep -A80
   needed_dynlibs`, 71 entries for `_rclpy_pybind11...so`) and diffed
   against a full (unfiltered -- watch for `.endsWith('.so')` filter bugs
   dropping versioned `.so.N.N.N` names, which produced a false-positive
   "missing" result the first time around) `Module.FS.readdir('/lib')`
   dump. All 71 needed libraries are present in `/lib` once the diff is
   done correctly. (Along the way, noticed `microcdr`'s own conda tarball
   -- built by this project's own `extra_recipes/microcdr` -- installs to
   a versioned subdir `$PREFIX/microcdr-2.0.2/lib/...` instead of the flat
   `$PREFIX/lib/...` every other package here uses, unlike e.g.
   `browser_demo/build.sh`'s native/non-jupyter demo path which explicitly
   copies `libmicrocdr.so*` into its flat output dir as a separate step.
   This is a real latent packaging inconsistency worth fixing eventually
   for cleanliness/robustness, but empirically confirmed NOT the cause of
   this crash -- flattening it into `/lib` via a patched test tarball made
   zero difference to the trap.)
4. Ruled out "the async dlopen/Asyncify-unwind machinery is fundamentally
   broken in this build" -- calling `Module.loadDynamicLibrary(path,
   {global:true, nodelete:true})` directly from JS (bypassing
   ctypes/Python entirely) for BOTH `libmicrocdr.so` (a "global"-type
   library) AND `_rclpy_pybind11...so` itself (a "local"/Python-C-
   extension-type library, normally skipped by empack's eager bootstrap
   preload and left for Python's own lazy import) **succeeds cleanly**.
   Real Asyncify-based async dlopen genuinely works when driven from JS.
5. Pre-loading `_rclpy_pybind11...so` via the (working) JS-level
   `Module.loadDynamicLibrary()` call BEFORE any Python code runs, then
   trying `ctypes.CDLL()` on the SAME already-resident path from Python
   afterward, **still traps identically** -- so this isn't about needing
   to suspend/await a fetch at all (the library is already fully loaded
   and linked by the time Python's `dlopen()` call happens); the trap
   fires even for what should be a synchronous cache-hit.
6. Captured the full JS exception object (not just `.message`) via the
   `unhandledRejection`/`uncaughtException` handlers above. The stack
   trace's only non-wasm, symbol-named frame is:
   ```
   RuntimeError: unreachable
       at wasm://.../wasm-function[19026]:...
       at _PyEM_TrampolineCall_JavaScript (xpython.js:...)
       at wasm://.../wasm-function[17953]:...
       ...
   ```
   `_PyEM_TrampolineCall_JavaScript` is CPython's own Emscripten-specific
   "call an arbitrary native function pointer whose signature isn't known
   until runtime" trampoline mechanism (the Pyodide-style patch that lets
   `ctypes` foreign-function calls -- and extension-module `PyInit_*`
   entry points obtained via `dlsym` -- work despite wasm's strict
   `call_indirect` signature checking). This is the SAME general
   mechanism implicated in the original "null function or function
   signature mismatch" mystery earlier this session (also routed through
   an indirect-call/signature-dispatch path), but this is a **distinct**
   crash: it happens even for `ctypes.CDLL('/lib/libmicrocdr.so')` alone
   (a plain C library with zero Python/pybind11 content), so it is not
   pybind11-ABI-related at all. The common thread across both bugs is
   CPython-on-Emscripten's function-pointer-dispatch machinery being
   fragile to *some* mismatch between how the calling host (`xpython.wasm`)
   and the thing it's calling into were each built/configured.

**Current best hypothesis (NOT yet confirmed)**: CPython's own Emscripten
patches for `ctypes`/dynamic-loading (the `_PyEM_TrampolineCall_JavaScript`
mechanism, part of `python`/`libpython`'s own build -- a stock
emscripten-forge package this project has never rebuilt or patched) may
themselves need to be Asyncify-aware/matching in a way the currently-
consumed stock `python`/`libpython` conda package isn't, mirroring this
whole session's recurring "stock package built against different
assumptions than our custom real-Asyncify host" pattern (pybind11 3.x vs
2.13.x for xeus-python/rclpy; native-wasm-exceptions vs JS-exceptions for
pyjs-dev). If so, the fix would require rebuilding `python`/`libpython`
itself for emscripten-wasm32 with Asyncify-compatible trampoline handling
-- a substantially bigger undertaking than anything touched so far this
session (CPython has never been part of this project's own recipe set;
it's always been consumed as a stock upstream package). This has NOT been
investigated yet (haven't looked at what conda channel/recipe currently
provides `python`/`libpython` for emscripten-wasm32, nor whether upstream
Pyodide/emscripten-forge has a newer or differently-configured build that
already handles this). **This is the natural next investigation step**,
but is flagged here as a scope escalation worth confirming with the user
before sinking further build time into it, since it means rebuilding a
foundational interpreter package this project has so far only ever
consumed pre-built.

**UPDATE 2026-09-13, later same session -- hypothesis TESTED AND DISPROVEN.**
Added `--enable-wasm-dynamic-linking` to `extra_recipes/python/Makefile`'s
`./configure` invocation (confirmed via CPython's own `configure.ac` that
this flag gates `BLDSHARED`/`ac_cv_func_dlopen`/`-sMAIN_MODULE` for
Emscripten -- a real, previously-never-enabled flag, independently named
in this project's own PR history, `Tobias-Fischer/ros-rolling#46`, while
chasing the earlier pthreads-era rclpy work). Rebuilt `python` (build
102) and `xeus-python` against it (build 105, since it statically links
`libpython3.13.a`). Result: **the exact same `RuntimeError: unreachable`
trap, in the exact same place** (`_PyEM_TrampolineCall_JavaScript`, same
function-index shape) on the identical `ctypes.CDLL('/lib/libmicrocdr.so')`
repro. One real, incidental behavior change did surface: with the flag
enabled, `xpython.wasm`'s own direct dependency on `libxeus.so` now goes
through a genuine async `dlopen()`/`loadDynamicLibrary` at module-init
time (previously it apparently didn't reach this code path at all) --
needed patching the Node test harness with a `locateFile` override
mapping `libxeus.so` -> its serve URL, and fixing this build's `xpython.js`
glue's otherwise-empty `else{}` branch for `readAsync`/`readBinary` under
Node (that glue only wires up fetch-based readAsync for
`ENVIRONMENT_IS_WEB`/`WORKER`, never for Node -- harmless for a real
browser deployment, but blocks Node-based testing of any dlopen path
that wasn't already fully resident in the FS). Neither of those changes
affected the actual crash.

**Reconsidered from first principles**: `_PyEM_TrampolineCall_JavaScript`'s
signature (`PyCFunctionWithKeywords func, PyObject *arg1/2/3`) means it is
ONLY ever used to invoke a `PyCFunction`-shaped Python built-in/extension
method -- it is CPython's generic "call a C-implemented Python function"
dispatch, used for literally every built-in call in the interpreter (and
proven working correctly thousands of times already in every test this
session). It is NOT used to call `dlopen()` itself (a plain C function with
an unrelated signature). So the trap is not "dlopen() traps" -- it's some
specific `PyCFunction` (almost certainly inside `_ctypes`'s own C
implementation, e.g. whatever `ctypes.CDLL.__init__` calls internally to
open the library) whose function-pointer dispatch via this trampoline
fails, for reasons still unknown. `--enable-wasm-dynamic-linking` was a
reasonable, concretely-justified hypothesis (and is arguably still correct
to keep/ship regardless, since it fixed the `libxeus.so` load-time
behavior to be more correct), but it does not address whatever is actually
broken here. **Not yet re-investigated further** -- this is a natural
checkpoint to get user input again before continuing to sink build time
into blind hypotheses; see the project's memory file
([[project_emscripten_zenoh_jupyterlite]]) for the corresponding summary.

**UPDATE 2026-09-13, still later same session -- narrowed further via a
`time.sleep()` control test, second hypothesis ALSO tested and DISPROVEN.**

Reasoned from first principles that since `_PyEM_TrampolineCall_JavaScript`
is used for EVERY C-implemented Python function call (proven working
thousands of times already), the trap must be specific to what happens
*inside* whichever function gets dispatched at the crash site, not the
dispatch mechanism itself. Added a `time.sleep(0.05)` cell to the bisect
harness as a control: `time.sleep()`'s C implementation (`pysleep()` in
`Modules/timemodule.c`) also does a genuinely Asyncify-suspending blocking
call (`nanosleep`/`select`), dispatched through the exact same
`_PyEM_TrampolineCall_JavaScript` mechanism ctypes.CDLL() uses (confirmed
`time_sleep` is `METH_O`, `py_dl_open` is `METH_VARARGS` -- both get cast
through the same 3-arg trampoline via
`_PyCFunction_TrampolineCall`/`_PyCFunctionWithKeywords_TrampolineCall`
macros in `pycore_emscripten_trampoline.h`). **Result: `time.sleep() OK`
prints successfully** -- real Asyncify suspend/resume through the ceval
loop, through this exact trampoline mechanism, genuinely works in general.
This rules out "the trampoline/ceval loop can't be unwound by Asyncify" as
a blanket explanation.

Also checked (via `typeof Module.PyEM_CountArgs` and
`'Function' in WebAssembly`) whether Node 24 actually uses the
type-reflection-based trampoline variant (`_PyEM_TrampolineCall_Reflection`,
a real wasm `call_indirect` Binaryen CAN statically analyze) instead of the
JS-mediated one (`_PyEM_TrampolineCall_JavaScript`, using
`wasmTable.get(func)(...)` from JS -- invisible to Binaryen's static
Asyncify call-graph analysis, since the target isn't resolved via any
wasm-level `call_indirect` instruction). **Confirmed Node 24's own
`WebAssembly` global does not expose `WebAssembly.Function`/type
reflection at all** (`'Function' in WebAssembly` is `false`), so this
build always uses the JS-mediated trampoline for both `time_sleep` and
`py_dl_open` -- ruling out "one uses a Binaryen-visible path and the other
doesn't" as the explanation, since both go through the identical
mechanism.

Compared `time_sleep`'s and `py_dl_open`'s actual C source side by side:
`pysleep()` wraps its blocking call in
`Py_BEGIN_ALLOW_THREADS`/`Py_END_ALLOW_THREADS` (releases/reacquires the
GIL around the call); `py_dl_open()` (`Modules/_ctypes/callproc.c`) calls
`dlopen(name_str, mode)` completely bare, with no GIL release at all --
the one concrete, real difference found between the two call sites.
Hypothesized this GIL-release/interpreter-thread-state bookkeeping might
be what a real Asyncify suspend-through-this-call-chain needs. Wrote and
shipped a real patch to test it:
`extra_recipes/python/patches/0006-ctypes-dlopen-release-gil-for-asyncify.patch`
(wraps `py_dl_open`'s `dlopen()` call in the same
`Py_BEGIN_ALLOW_THREADS`/`END` pair, matching `pysleep()`'s own pattern;
verified applies cleanly via the usual git-diff-against-pristine-source
technique). Rebuilt `python` (build 103) and `xeus-python` against it
(build 106).

**Result: DISPROVEN again -- the exact same `RuntimeError: unreachable`
trap, at the exact same function-index shape, in the exact same place.**
GIL release around `dlopen()` has no effect on this crash either.

**Where this leaves things**: two concrete, source-grounded hypotheses
(missing `--enable-wasm-dynamic-linking`; missing GIL release around
`dlopen()`) have now been built and tested end-to-end, and both are
conclusively ruled out. The `time.sleep()` control test is a genuinely
useful, permanent addition to this bisection harness -- it proves real
Asyncify suspend/resume through the interpreter works in general, so
whatever's wrong is specific to the `dlopen()`/`ctypes.CDLL()` call chain
itself, not a general ceval/Asyncify incompatibility. Further progress
likely needs either (a) actual low-level wasm/Binaryen debugging tools
(e.g. inspecting the Asyncify instrumentation lists that were actually
baked into this specific `xpython.wasm` build, or single-stepping the
trap in a wasm debugger) rather than reasoning from C source alone, or (b)
searching Emscripten's own issue tracker for prior reports of
"ctypes.CDLL/dlopen traps under Asyncify" specifically, since this may be
a known, documented limitation rather than something fixable via a small
CPython patch. This is a natural checkpoint -- see the project's memory
file for the corresponding summary and status going into any future
session.

**UPDATE 2026-09-13, still later same session -- disassembled the actual
trap site, found the true shape of the bug, and CONFIRMED via upstream
sources this is a known, unresolved Emscripten/Pyodide limitation.**

Ran `wasm-objdump -d` on the built `xpython.wasm` and located the exact
trap instruction (matching the reported byte offset precisely). The
compiled code at the trap site has this exact, repeating shape (same in
both the original METH_VARARGS build and, as it turned out, structurally
identical in spirit after the METH_FASTCALL conversion below):
```
  ... call the async-suspending function ...
  global.get $__asyncify_state
  i32.eqz
  if
    ... restore stack, return the real result ...
  end
  unreachable        <-- the actual trap
```
This is Binaryen's own Asyncify instrumentation pattern: "if we're back to
normal execution, return the result; this point should be unreachable
otherwise." It fires whenever the function is reached with
`__asyncify_state != 0` at exactly this point without an earlier
`br_if`-based propagation catching it first -- i.e. exactly what happens
when Asyncify's unwind/rewind bookkeeping doesn't correctly propagate
through this specific call.

**Tested the METH_VARARGS-vs-METH_FASTCALL hypothesis for real** (the
patch from the previous update,
`patches/0007-ctypes-dlopen-methfastcall.patch`, converting
`_ctypes.dlopen()`'s calling convention): confirmed via a `strings` check
on the new `xpython.wasm` that the patch's own new error string
(`"dlopen() takes 1 or 2 arguments"`) is present, i.e. the patch really is
compiled in. Result: **the crash's exact stack trace changed** (no longer
routes through `_PyEM_TrampolineCall_JavaScript` at all -- now traps
inside `_PyObject_MakeTpCall`, called from `PyObject_Vectorcall`, called
from `_PyEval_EvalFrameDefault`), confirming the calling-convention change
genuinely took effect and changed the dispatch path -- **but the crash
itself is unchanged**: same "unreachable after an async call, no
propagation" shape, just in a different generic CPython dispatch function.
Also confirmed via a direct `_ctypes.dlopen()` call (bypassing
`ctypes.CDLL` entirely) that the trap is specifically at the `dlopen()`
call itself, not something later in `CDLL.__init__`.

This means the bug is NOT specific to any one CPython dispatch function
(trampoline vs `MakeTpCall` vs vectorcall) -- it reproduces through
*every* generic "call a C-implemented Python function" path CPython has,
whenever that call reaches a genuinely Asyncify-suspending operation
(`dlopen()` via `__dlopen_js`/`Asyncify.handleSleep`).

**Confirmed via web search this is a known, longstanding, unresolved
upstream limitation, not something specific to this project or fixable
via a CPython patch:**
- [emscripten-core/emscripten#13049](https://github.com/emscripten-core/emscripten/issues/13049)
  ("Invalid Asyncify stack when using dlopen() with SIDE_MODULE and
  asyncify imports") -- root cause described as an invalid Asyncify call
  stack when combining `dlopen()` + `SIDE_MODULE`/`MAIN_MODULE` +
  `ASYNCIFY` + JS library functions with asyncify imports; the *only*
  documented workaround is to avoid `dlopen()` at runtime entirely (link
  the library statically/as a regular callable module and use `ccall()`
  instead). No fix as of the issue's content.
- [emscripten-core/emscripten#15594](https://github.com/emscripten-core/emscripten/issues/15594)
  ("emscripten_sleep in side module corrupts stack") -- same family: an
  Asyncify-suspending call made through a dynamically-loaded side module
  doesn't correctly resume; no confirmed fix.
- [pyodide/pyodide#4087](https://github.com/pyodide/pyodide/discussions/4087)
  ("Using Asyncify from C/C++ Python module") -- **this is essentially the
  exact bug, reported against Pyodide's own CPython fork**: calling
  `emscripten_sleep()` from inside a pybind11-based Python C extension
  (i.e. through CPython's own PyCFunction call trampoline --
  `_PyCFunctionWithKeywords_TrampolineCall`/`_PyEM_TrampolineCall_JavaScript`,
  the EXACT mechanism at the heart of this whole investigation) traps with
  `RuntimeError: unreachable` in `$cfunction_call`. Described as a
  "known limitation without a straightforward solution." **The only
  workaround identified is pushing the async operation onto a real OS
  thread (`std::async`)** -- i.e. genuine pthreads, which is precisely
  what this whole project deliberately moved away from (see the
  "MAJOR PIVOT" / pthreads-to-Asyncify sections earlier in this file) for
  unrelated, equally solid reasons (pthreads' viral shared-memory
  requirement blocking rclpy from loading into non-pthreads xeus-python,
  and xeus-python's own thread model deadlocking under pthreads).

**Bottom line**: this is not a bug in this project's own code, in
CPython's `_ctypes` module specifically, or in anything a source patch to
`_ctypes`/`dynload_shlib.c` can realistically fix -- it's Emscripten's
Asyncify transform itself having a fundamental, still-unresolved
incompatibility with invoking a *dynamically dlopen()'d* module (or, per
the Pyodide report, even just calling an async-suspending function through
CPython's own generic C-function-call dispatch) from inside compiled C
code, as opposed to driving the exact same `Module.loadDynamicLibrary()`
call directly from JS (which has been proven to work reliably, repeatedly,
throughout this investigation). Two concrete, well-targeted CPython
patches (`0006`, GIL release; `0007`, METH_FASTCALL conversion) were
written, built, and tested against this exact hypothesis space and both
confirm the same conclusion from different angles: the problem is at the
Emscripten/Binaryen Asyncify layer, not in how CPython calls into it.

**Where this leaves the project**: getting `import rclpy` (which needs a
real, lazy, Python-triggered `dlopen()` of `_rclpy_pybind11.so`) to work
under a genuinely non-pthreads, real-Asyncify `xeus-python` host appears
to require one of:
1. Avoid ever triggering a C-level/Python-level `dlopen()` for Python
   C-extensions at runtime at all -- i.e. statically link `rclpy`'s
   compiled extension (and everything else Python would otherwise
   `import`) directly into `xpython.wasm`'s own `MAIN_MODULE` at build
   time, matching issue #13049's own documented workaround ("build the
   library as a regular callable module... instead of dlopen()"). This is
   a substantial build-system change (would mean building a CUSTOM
   xeus-python binary with `_rclpy_pybind11` and its ~71 transitive `.so`
   dependencies baked in directly, rather than dlopen'd at runtime) but is
   the only approach with a real, working precedent (`ccall()`-style
   static linking is explicitly called out as the working alternative).
2. Accept pthreads specifically for this one narrow purpose (the
   `std::async`-based workaround from the Pyodide discussion) -- almost
   certainly reintroduces the shared-memory viral-dependency problem this
   project spent real effort eliminating project-wide, so likely a
   net-negative trade unless scoped extremely narrowly (e.g. a tiny,
   isolated pthread pool JUST for dlopen calls, never touching xeus-python
   itself) -- unexplored, uncertain feasibility.
3. Ship the JupyterLite `rclpy` integration WITHOUT dynamic/lazy import of
   its own C extension -- e.g. pre-populate ALL of rclpy's own
   dependencies (including `_rclpy_pybind11.so` itself) via the
   JS-level `Module.loadDynamicLibrary()` eager-preload mechanism BEFORE
   Python starts, then patch CPython's/rclpy's own import machinery (or
   the compiled extension's own init path) to skip the C-level `dlopen()`
   call and treat the module as already-resolved -- effectively
   Pyodide's own actual solution for its "load packages with compiled
   extensions at runtime" feature, likely requiring Pyodide-specific
   CPython patches this project doesn't currently have (not investigated
   this session -- Pyodide's own micropip/`pyodide.loadPackage()`
   mechanism is the natural reference implementation to study for this,
   since Pyodide DOES successfully load compiled numpy/scipy-style
   extensions at runtime in production under real Asyncify).

None of these have been attempted yet. This is a natural, real
architectural decision point -- not a "keep guessing at CPython patches"
situation -- given three independent hypotheses (missing
`--enable-wasm-dynamic-linking`, missing GIL release, wrong calling
convention) have each been built, tested, and disproven, and external
sources now confirm why: this is Emscripten's own documented, unresolved
limitation, not a bug in this project's code.

**MAJOR PIVOT 2026-09-13, still later same session -- Asyncify dropped
project-wide; back to plain stock packages + runtime dlopen().**

User pushed back on the whole Asyncify-for-dlopen chase with the right
question: "why do we need asyncify? Can't we do without? We did it back
then [pthreads/humble era], what's different now?" This led to checking
two things that changed the whole picture:

1. **`Tobias-Fischer/ros-humble`'s own working emscripten-wasm32 port**
   (a genuinely separate, working, *published* build, "ros-humble"
   channel) uses `RoboStack/vinca`'s own upstream `build_ament_cmake.sh.in`
   template directly (pinned commit `b5e03d1f...`), which has
   `USE_PTHREADS=0` and its own Asyncify variant **commented out** --
   confirming dlopen() of a SIDE_MODULE into a MAIN_MODULE works fine on
   its own; it's specifically Asyncify combined with dlopen() that's
   broken (matching emscripten-core/emscripten#13049's own title
   precisely).
2. **The actual "how do you wait for a message without Asyncify" trick**,
   found by digging into `ros2wasm`'s own real, published, working
   JupyterLite demo (`ros2wasm/pixi-ros2-wasm`'s `RosLibJs.ipynb`, and its
   own `rmw_wasm` middleware, `ros2wasm/rmw_wasm`) -- its `xpython.js` has
   **no Asyncify at all** (`grep` for `__asyncify_state`: absent). The demo
   never calls blocking `rclpy.spin()`; it does:
   ```python
   async def spin_subscriber(sub):
     while running:
       rclpy.spin_once(sub, timeout_sec=0)
       await asyncio.sleep(0.01)
   ```
   `rclpy.spin_once(..., timeout_sec=0)` triggers `rcl_wait()`'s own
   `is_non_blocking` fast path (confirmed by reading `rcl`'s own
   `src/rcl/wait.c`: `bool is_non_blocking = timeout == 0;`, which forces
   a `{0,0}` timeout down into `rmw_wait()`) -- and **this project's own
   `rmw_zenoh_pico` patch already special-cases exactly this**: its
   single-threaded poll loop breaks out immediately when
   `timeout_ms == 0`, *before* ever reaching the `z_sleep_ms()` call that
   needs Asyncify. No zenoh/rmw patch was needed at all -- the fast path
   already existed; the demo just needed to be restructured to use it. The
   "keep checking periodically" cadence lives entirely in Python's own
   `asyncio.sleep()`, bridged to the browser's JS event loop via `pyjs`'s
   webloop -- not Asyncify.

**Consequence**: since Asyncify was the whole reason this project ever
needed its own custom `python`/`xeus`/`xeus-lite`/`xeus-python`/`pyjs`/
`numpy` recipes (every one of `extra_recipes/{python,xeus,xeus-lite,
xeus-python,numpy,pyjs}`'s own header comment says so explicitly, in
those exact words, once re-read with this in mind), **all of those are
now deleted**. This project now consumes stock, unmodified
`emscripten-forge-4x` packages for all of them -- confirmed via the
actually-published `xeus-python-0.19.0-py313he5686da_3`'s own
`rendered_recipe.yaml` (zero patches, bare unpinned `pybind11` that
happened to resolve `<3` at its own build time) and by downloading and
inspecting the *current* stock `pyjs-rt-4.0.6` package directly (already
has real `lib/python3.13/site-packages/pyjs/webloop.py` content -- the
"pyjs-rt ships an empty package" bug this project found and fixed
locally earlier in the marathon is now fixed upstream too, independently).

Also **dropped `-sASYNCIFY`/`ASYNCIFY_IMPORTS`/`ASYNCIFY_STACK_SIZE`
entirely from `vinca`'s own `build_ament_cmake.sh.in` template**
(`~/robot/vinca`, this project's fork) -- it was applied globally to
*every* emscripten-wasm32 ROS package (not just rclpy-adjacent ones), so
this affects the whole ~230-package closure, including `browser_demo`'s
own rclc/rclcpp C++ demo, which still uses a real blocking
`rclcpp::spin()`/`rclc_executor_spin()` today. User explicitly chose (over
keeping two build variants) to unify on no-Asyncify everywhere: this means
`browser_demo`'s own C++ demo will need restructuring too, to the same
"non-blocking `spin_some`/poll-once + externally-driven tick" pattern (a
JS-side `setInterval`-equivalent calling a small exported tick function,
analogous to Python's `asyncio.sleep()` loop) -- **not yet done, tracked as
a follow-up** once the Python/JupyterLite side is confirmed working.
`pixi.toml`'s own `vinca` dependency is temporarily pointed at a local
path (`../vinca`, editable) for fast iteration while this settles --
remember to re-pin to a pushed commit once it does.

Rebuilding now: identified and deleted the specific ~40 stale
Asyncify-built artifacts in `output/emscripten-wasm32/` that are part of
rclpy's own transitive `.so` closure (matched by scanning each existing
`.tar.bz2`'s file list against the previously-computed 77-file closure --
see the "disassembled the actual trap site" section above for how that
list was built), then kicked off the project's own standard
`pixi run build-emscripten` to rebuild exactly those (everything
unaffected gets skipped via rattler-build's own existing-package check).

**Reproduction**: `~/robot/ros2-emscripten-zenoh-demo/scratch/real_xeuspython_v3/test_rclpy_bisect.mjs`
against the real build-104 `xpython.js`/`.wasm` (patched in that same
scratch dir with the `_dlerror` JS hookup from
`patches/patch_stock_xpython_js.mjs`'s "hook-up-dlerror-export" patch,
otherwise unmodified -- that hookup is itself a separate, confirmed-real
gap in build 104's JS glue: `Module["_dlerror"]` is never wired to the
compiled wasm export, so any exception path that tries to report a real
`dlopen()` failure via `dlerror()` throws `TypeError: Module._dlerror is
not a function` and masks the original error -- worth fixing upstream in
`extra_recipes/xeus-python`'s own patch too, independent of this
trampoline investigation).

## Practical triage order

1. Build a failing package directly.
2. Apply smallest viable source or recipe fix.
3. Update package patch file (package-named).
4. Rebuild same package.
5. Move on immediately if it becomes complex; prioritize easy wins.
6. Revisit hard failures after reducing the failure queue.

## UPDATE 2026-09-13, later same session -- rclpy.init() OK end-to-end; Node() creation blocked on a NEW, deeper Asyncify-shaped hole (zenoh session-open handshake)

Picking back up after the "MAJOR PIVOT" above: rebuilt `rmw_zenoh_pico`
(build 27) with a real fix for the `ament_target_dependencies()` CMake
shim (this project's own patch macro never actually called
`target_link_libraries()` for `zenohpico` because its modern
`Config.cmake` only exports the namespaced imported target
`zenohpico::zenohpico_shared`, no legacy `zenohpico_LIBRARIES` var --
added an `elseif(TARGET ${_dep}::${_dep}_shared)` fallback branch).
Confirmed via `wasm-objdump -x librmw_zenoh_pico.so | grep needed_dynlibs`
that `libzenohpico.so` is now correctly declared, fixing the
`cannot resolve symbol z_malloc` crash.

Also fixed, all in `scratch/noasyncify_test/xpython.js` (hand-patched
copy of the *stock*, unmodified emscripten-forge `xeus-python` JS glue --
these are test-harness-local patches, not yet upstreamed anywhere, kept
here purely to unblock iteration):
- Node harness: `readBinary`/`readAsync`'s Node-only `else` branch only
  tried the literal dlopen path (e.g. bare `librcl_logging_noop.so`),
  never `/lib/<basename>` -- added that fallback so a bare-name runtime
  `dlopen()` (as done by `rcutils_shared_library_load` for
  `RCL_LOGGING_IMPLEMENTATION`) can find a file bootstrap already
  extracted into FS.
- **Real browser** (not just the Node harness) has the exact same class
  of bug, worse: stock Emscripten's main-thread (non-Worker) browser
  build **never defines `readBinary` at all** (there is no way to
  block-wait on a real fetch from the main thread without Asyncify).
  Added a `readBinary` for that branch too, checking the in-memory FS
  cache (literal path, then `/lib/<basename>`) -- since
  `bootstrap_from_empack_packed_environment` already extracted every
  package into MEMFS up front, this needs no real I/O and works
  synchronously on the main thread.
- `loadDynlibsFromPackage` (empack's bulk per-package dylib eager-preload
  helper) calls `Module._emscripten_dlopen_promise`, which this stock
  build's JS glue never actually binds onto `Module` (confirmed via
  `wasm-objdump`: `emscripten_dlopen_promise` *is* a real wasm export,
  but no `Module._emscripten_dlopen_promise = ...` assignment exists
  anywhere in `xpython.js` -- this bulk-preload feature appears to
  require JSPI, which this build wasn't compiled with). Made this
  function a no-op: regular Python-import-triggered `dlopen()` (the
  plain sync path) already works correctly and is all that's actually
  needed -- confirmed by testing `import rclpy` and friends fully
  succeed with this preload step skipped entirely.
- Root-caused the "WebSocket connection to 'ws://127.0.0.1:7447/' failed"
  (browser devtools shows code 1006, immediate abnormal close):
  Emscripten's *stock* SOCKFS `websocket_sock_ops.createPeer()` defaults
  to requesting the `"binary"` WebSocket subprotocol
  (`SOCKFS.websocketArgs`, sourced from `Module["websocket"]` at FS-mount
  time) -- meant for Emscripten's own websockify-style TCP-over-WS relay,
  not a generic WS server. `zenohd`'s own `-l ws/...` listener doesn't
  support it and the handshake is rejected outright. Fix: pass
  `websocket: { subprotocol: null }` in the `Module` config object passed
  to `createXeusModule({...})` -- this is a real, standard, documented
  Emscripten networking config knob, not a source patch. Confirmed via a
  manual `new WebSocket('ws://127.0.0.1:7447/')` (no protocols) opening
  fine, vs the same call with `['binary']` failing with code 1006.

With all of the above applied, `rclpy imported OK` / `Node class imported
OK` / **`rclpy.init() OK`** now print successfully end-to-end, in both the
Node test harness (`scratch/noasyncify_test/test_rclpy_noasyncify.mjs`)
and a new real-browser test page
(`scratch/noasyncify_test/browser_test.html`, driven via the
Claude-Code-in-desktop Browser pane tool against the same
`merged_kernel_packages`/`empack_env_meta_patched.json` served over
`python -m http.server`). **This is real progress the browser side alone
would never have surfaced without the Node harness's much faster iteration
loop -- keep using the Node harness first, browser only to confirm/root-
cause things that are Node-harness-specific (see below) or genuinely
browser-only.**

**The Node.js test harness's own "async hook stack has become corrupted"
crash (seen repeatedly, always right around `Node()` construction) is
confirmed to be a pure Node.js-harness artifact, NOT a real bug**: the
identical `Node()`-construction failure reproduces in the real browser
(via `browser_test.html`) as a normal, non-fatal `RuntimeWarning`
(`Failed to fini node: guard_condition argument is null`) with no crash
at all. `async_hooks` doesn't exist in browsers, so this specific crash
class cannot occur there. Lesson: when the Node harness crashes
mysteriously around exception/traceback-heavy code paths, don't chase it
further in Node -- switch to the real browser (cheap via the Browser pane
tool) to see the *actual* underlying behavior.

### THE CURRENT BLOCKER: `Node()` construction never completes -- zenoh
### session/link *establishment* still silently depends on Asyncify

After `rclpy.init() OK`, `node = Node('wasm_rclpy_jupyter', ...)` never
prints `Node created: ...` -- it fails inside `_rclpy.Node(...)`
construction, producing a cascade of secondary rcutils errors (each
overwriting the last, so the *original* root cause is never shown):
`'map is not initialized'` (hash_map.c) -> `'Unable to fini type cache
for node.'` (rcl/node.c:362) -> `'node argument is null'`
(rmw_zenoh_pico's rmw_node.c:271, i.e. `rmw_destroy_node()` being handed
a NULL node because `rmw_create_node()` upstream of it returned NULL) ->
`'guard_condition argument is null'` (rcl/guard_condition.c:120). No
Python-level traceback or `execute_reply` error message is ever produced
for CELL1 -- it just silently never finishes.

Root-caused via `zenohd`'s own debug log (`RUST_LOG=debug`, see
`~/robot/ros-rolling-emscripten-zenoh/zenoh_router/`, a locally-running
test-only `zenohd -l ws/127.0.0.1:7447 ... -P storage_manager` fixture --
there's no config issue with it, its REST admin space at
`http://127.0.0.1:8000/@/**` is a handy way to check `sessions: []` /
`subscriber/**` live state going forward):

```
09:01:34.880170 zenoh_link_ws::unicast: Accepted TCP (WebSocket) connection on 127.0.0.1:7447: ...
09:01:34.880383 tungstenite::handshake::server: Server handshake done.
09:01:44.883652 zenoh_transport::unicast::manager: Failed to accept link before deadline (10000ms)
```

The raw WebSocket **transport** opens fine (confirmed independently: a
manual `new WebSocket('ws://127.0.0.1:7447/')` from the same browser tab
opens immediately). But **zenohd never receives a single byte of the
actual zenoh protocol handshake** (Init/Open messages) in the full
10-second `accept_timeout` window -- our wasm client's WS transport opens,
and then nothing is ever sent.

**Root cause, confirmed by reading zenoh-pico's own source
(`src/system/emscripten/system.c`)**:

```c
z_result_t z_sleep_us(size_t time) { emscripten_sleep((time/1000)+...); return 0; }
z_result_t z_sleep_ms(size_t time) { emscripten_sleep(time); return 0; }
```

`z_sleep_ms()`/`z_sleep_us()` on the emscripten platform port are
implemented via **`emscripten_sleep()`, which is itself an Asyncify-only
primitive** -- it requires the Binaryen Asyncify transform to actually
suspend/resume the wasm call stack while yielding control back to the
browser's event loop. Now that Asyncify has been dropped project-wide
(the whole point of the "MAJOR PIVOT" above), `emscripten_sleep()` can no
longer do what it used to: it does *not* genuinely yield, so nothing ever
gives the browser's own event loop a turn to actually finish the
WebSocket handshake / deliver queued send-buffer flushes before the
calling C code barrels on and tries to write the zenoh Init message --
onto a socket that, from the JS side, may still be in `CONNECTING` state.
There's already a prior-session patch
(`extra_recipes/zenoh-pico/emscripten-longer-ws-open-wait.patch`) that
bumped this exact call site's delay from 100ms to 2000ms -- that fix only
ever worked because Asyncify was still enabled at the time it was
written; it is now silently a no-op (or near-no-op) and needs to be
revisited.

**Why this can't be patched the same lightweight way as `rmw_wait`'s
`timeout_ms==0` fast path**: `rmw_wait()`'s fast path works because a
*zero* timeout genuinely means "one single non-blocking poll, then
return" -- no waiting is semantically required at all. Session/link/node
*establishment*, by contrast, inherently requires waiting for a real
network round-trip (the browser must complete the WS handshake, then the
Init/OpenAck exchange with the router) before it can succeed --  there is
no zero-timeout fast path available for it, because the work hasn't
happened yet, period. And a synchronous busy-spin (checking
`readyState`/re-attempting `recv()` in a tight C loop with no real delay)
categorically cannot substitute for real waiting, because a JS
macrotask (which is what a WebSocket `open`/`message` event is) can only
run once the JS call stack has *actually returned* to the browser's own
event-loop dispatcher -- there is no way to reenter/pump it from inside a
still-running synchronous WASM call, with or without an artificial delay,
short of Asyncify, JSPI (WebAssembly Promise Integration -- unavailable:
already confirmed in this exact build, `Module._emscripten_dlopen_promise`
is a dead, unwired export, meaning this build has no working JSPI-driven
async primitive at all), or a real OS thread (pthreads/Workers -- already
tried project-wide earlier in the marathon and reverted, both for the
Asyncify+dlopen SIDE_MODULE crash *and*, independently, because
xeus-python's own thread model deadlocked hard under real pthreads).
Re-adding Asyncify **only** to zenoh-pico/rmw_zenoh_pico's own `.so`
files would not help either: Asyncify's unwind/rewind mechanism needs
*every* frame between the suspend point and the original Python-level
entry point instrumented consistently, and that unwind path necessarily
crosses back up through several OTHER separately-`dlopen()`'d
SIDE_MODULEs (`_rclpy_pybind11.so`, `librcl.so`, ...) that would need
Asyncify too -- i.e. it reduces right back to the exact Asyncify+dlopen
combination this whole pivot exists to avoid.

**The only architecturally-consistent fix**: restructure zenoh-pico's
session/transport-*open* handshake (not just the already-fixed
read/wait side) into an explicit, externally-driven, resumable state
machine -- mirroring the *pattern* already proven for `rmw_wait`, but a
meaningfully bigger lift because (unlike `rmw_wait`) there is no existing
non-blocking code path to route through; one has to be built:
1. `_z_open_ws()` (network.c) needs to stop trying to wait for the
   socket to reach `OPEN` internally at all -- issue `connect()`, check
   `readyState` once, and return a "not yet, call me again" status
   immediately if it isn't open, rather than sleeping.
2. Whatever sends the zenoh Init message and awaits InitAck/OpenAck
   (deeper in zenoh-pico's `src/transport/unicast/...` session-open
   sequence) needs the same treatment: attempt one non-blocking
   send/recv step per call, track progress across calls in a persistent
   state struct, and return "still connecting" vs "established" vs
   "failed" rather than blocking to completion.
3. `rmw_init()` (rmw_zenoh_pico) needs to expose this as something
   retriable rather than a single one-shot blocking call -- likely a new
   low-level "pump the connection" entry point that Python-level code
   calls repeatedly inside an `await asyncio.sleep(...)` loop, the same
   shape as the already-working `spin_subscriber()`/`spin_once(timeout_sec=0)`
   pattern in CELL2 -- meaning `rclpy.init()` itself may need to become
   async-retriable at the Python level too (not a trivial, purely-C-side
   fix).

This is a materially bigger undertaking than everything fixed so far in
this pivot (all of which were narrowly-scoped, single-symptom patches).
Paused here to discuss direction with the user before investing in it,
per this project's standing "confirm before large architecture
decisions" pattern (matches how the original Asyncify-removal pivot
itself started from the user's own question rather than an autonomous
guess).

**Test fixtures now in place, reusable for whatever comes next**:
- `~/robot/ros-rolling-emscripten-zenoh/zenoh_router/zenohd` -- run with
  `RUST_LOG=debug` and `> /tmp/zenohd_debug.log 2>&1 &` to see exactly
  what the router observes per connection attempt; its REST admin space
  (`--rest-http-port 8000`, `curl http://127.0.0.1:8000/@/**`) shows live
  `sessions`/`subscriber` state, handy for checking whether a session
  ever actually registers without needing to grep debug logs.
- `~/robot/ros2-emscripten-zenoh-demo/scratch/noasyncify_test/browser_test.html`
  -- real-browser equivalent of `test_rclpy_noasyncify.mjs`, served via
  the same `python -m http.server` on port 8887 (alongside
  `merged_kernel_packages/`, `empack_env_meta_patched.json`,
  `libxeus.so`), driven via the Claude-Code-in-desktop Browser pane tool.
  Includes a `WebSocket` constructor monkeypatch (logs every
  `[ws#N] constructing/OPEN/ERROR/CLOSE`) that was essential for
  root-causing the subprotocol bug above -- keep it in place, it's cheap
  and has already paid for itself twice.

## MAJOR BREAKTHROUGH 2026-09-13, still later same session -- the zenoh session-open handshake is now genuinely resumable without Asyncify, and `Node()` construction succeeds end-to-end

Continuing directly from "THE CURRENT BLOCKER" section above: built the full non-blocking,
resumable client-handshake state machine the user asked for. **It works.** Confirmed via the
real browser test harness (`scratch/noasyncify_test/browser_test.html`):

```
rclpy.init() OK after 1 attempt(s)
Node() attempt 1 failed: RCLError(...)   <- expected, handshake still in progress
Node() attempt 2 failed: RCLError(...)   <- expected, handshake still in progress
Node() OK after 3 attempt(s)
Node created: wasm_rclpy_jupyter
```

### What actually shipped

1. **`zenoh-pico` (`extra_recipes/zenoh-pico/`, now build 12)**:
   - `emscripten-nonblocking-io.patch`: `_z_open_ws()` no longer waits at all after `connect()`
     (that wait relied on the now-dead `emscripten_sleep()`); `_z_read_ws()`/`_z_send_ws()` each
     make exactly ONE non-blocking `recv()`/`send()` attempt per call instead of an internal
     retry-with-sleep loop. Also adds a **persistent fd cache**
     (`static int _z_ws_persistent_fd`): `_z_open_ws()` returns this cached fd on every call
     after the first (skipping `socket()`/`connect()` entirely), and `_z_close_ws()` is a
     deliberate no-op -- the underlying WebSocket must survive across separate Python-driven
     retries, or every retry would open a doomed brand-new connection that can never progress
     within its own single synchronous call either (see the reasoning trail below).
   - `emscripten-nonblocking-sleep.patch`: `z_sleep_us()`/`z_sleep_ms()` are now true no-ops
     (no `emscripten_sleep()` call at all) -- see the "why this can't be patched the same
     lightweight way as rmw_wait" reasoning in the previous section; the short version is that
     nothing can synchronously wait for browser-side network progress without Asyncify/JSPI/
     threads, so don't even try -- let the caller's own retry cadence (Python `await
     asyncio.sleep()`) be the only "wait a bit" mechanism anywhere in this whole path.
   - `emscripten-resumable-handshake.patch`: the big one. Adds
     `_z_unicast_handshake_open_client_resumable()` (`src/transport/unicast/transport.c`,
     `#ifdef __EMSCRIPTEN__`), a phase-tracked (`NOT_STARTED` / `INIT_SENT` / `OPEN_SENT`)
     rewrite of the existing (portable, untouched-for-every-other-platform)
     `_z_unicast_handshake_open()`, wired in via `_z_unicast_open_client()`. Each call does AT
     MOST one non-blocking step (send whatever hasn't been sent yet, then try once to receive
     whatever's next expected) and returns immediately -- critically, it does NOT resend a
     message a prior call already sent, reusing a single static `_z_hs_state` (this project only
     ever has one zenoh session in flight). **A naive "just retry the whole call from scratch"
     approach was tried FIRST and empirically proven broken**, via `zenohd`'s own `RUST_LOG=debug`
     log: `Received invalid message instead of an OpenSyn ... InitSyn(...)` -- a retry that
     resends InitSyn on a connection zenohd is already past that stage on is a genuine protocol
     violation from the server's perspective, not a fresh session (exactly because the
     persistent-fd cache above means it really is the same underlying connection).
   - **The trickiest bug, found only via raw byte-level tracing**: WS links use
     `Z_LINK_CAP_FLOW_DATAGRAM` (`_z_link_recv_t_msg` in `transport/common/rx.c`), whose read
     path only treats a raw `SIZE_MAX` return as a hard failure -- a clean "nothing available
     yet" (0 bytes, from our new single-attempt `_z_read_ws`) is NOT specially handled at all; it
     falls through to attempting to decode an EMPTY buffer, which
     `_z_transport_message_decode()` correctly rejects with
     `_Z_ERR_MESSAGE_DESERIALIZATION_FAILED` (-119) -- NOT the `_Z_ERR_TRANSPORT_RX_FAILED` (-99)
     this patch originally (incorrectly) assumed was the only "try again" signal, borrowed from
     the STREAM-flow code path's semantics without checking DATAGRAM-flow's own. Confirmed via
     temporary `printf`-based tracing (raw `recv()`/`errno` values, raw received bytes, decode
     return codes -- all now removed, see below) showing a "no data yet" attempt hitting
     `recv()==-1, errno=ENXIO` correctly, yet still reaching `decode()` with a genuinely empty
     zbuf and getting -119. Fixed: the resumable handshake now treats **both** -99 and -119 as
     "still in progress, call again later" (safe here because a WS message is always delivered
     as one complete atomic unit against a trusted local `zenohd` -- a non-empty read that still
     fails to decode would be a real, different bug, not something this fast path needs to mask).
   - `emscripten-rx-debug.patch`: temporary diagnostic tracing in `_z_link_recv_t_msg`
     (`transport/common/rx.c`) -- dumps raw received bytes + decode result on every call. **Still
     present in the build as of this writing (build 12) -- remove once the remaining CELL2 issue
     below is fully resolved**, along with the `printf` tracing left inside
     `emscripten-resumable-handshake.patch`'s handshake function and `emscripten-nonblocking-io.patch`'s `_z_read_ws`.

2. **`rmw_zenoh_pico` (build 28)**: `session_connect()` (`src/zenoh_pico/zenoh_pico_session.c`)
   now clones a **fresh** `z_owned_config_t` for each `z_open()` attempt instead of `z_move()`ing
   `session->config` directly -- `z_open()` consumes (moves-from) its config argument whether or
   not it succeeds, so a naive retry would hand it an already-invalidated config on the second
   and every later call. This keeps the session's own original config alive and valid across
   however many retries `session_connect()` takes.

3. **`rclpy` (build 28)**: ported `ros2-emscripten-zenoh-demo/patches/
   rclpy-node-rmw_zenoh_pico-workarounds.patch` (previously only ever applied in the SEPARATE
   `demo_env_build` deployment path, never folded into this project's own rattler-build recipe
   pipeline) into this repo's own `patch/ros-rolling-rclpy.emscripten.patch`. Once `Node()`
   construction could finally get far enough to reach it (i.e. after the handshake fix above),
   it hit a NEW, narrower, already-known issue:
   `RCLError('failed to create publisher event: Publisher implementation identifier not from
   this implementation, ... rmw_event.c:242')` -- `Node.__init__()` unconditionally creates a
   `/parameter_events` publisher with default QoS event callbacks and a `TypeDescriptionService`,
   neither of which rmw_zenoh_pico (a prototype/incomplete RMW implementation) fully supports.
   Fix (ported verbatim from the demo repo's own patch): pass
   `event_callbacks=PublisherEventCallbacks(use_default_callbacks=False)` to that publisher, and
   set `self._type_description_service = None` instead of constructing a real one.

### The retry pattern, Python-side

`rclpy.init()` and `Node()` construction are no longer guaranteed to succeed on the first call --
both need to be wrapped in a retry loop with a real `await asyncio.sleep()` between attempts
(mirroring the already-established `rclpy.spin_once(timeout_sec=0)` pattern for the read/wait
side). See `scratch/noasyncify_test/browser_test.html`'s `init_with_retry()` helper for the
reference implementation: catch the exception, sleep, retry, up to a bounded attempt count.
**This is now a real, permanent part of this project's rclpy usage pattern for JupyterLite** --
`rclpy.init()`/`Node()` (and likely other zenoh-session-dependent calls made before the session
is confirmed fully open) must be called this way from any real notebook cell going forward, not
just this test harness.

### Remaining work (not yet done)

- **CELL2 (creating a SECOND node + subscriber, then actually publishing/receiving messages)
  hangs the whole browser tab** -- after `tasks scheduled` prints, the page becomes fully
  unresponsive (even a trivial `javascript_exec` call times out), suggesting a tight busy-loop
  somewhere (possibly an unhandled-exception flood in the `spin_once`/`asyncio.sleep()` loop, or
  the SECOND `Node()`'s own retry loop spinning faster than expected). Not yet root-caused --
  next step, in a fresh, unfrozen tab: reduce `init_with_retry`'s `max_attempts` for a faster
  fail-fast, wrap `setup_and_spin()`'s body in its own try/except to surface whatever's actually
  throwing instead of silently flooding, and check whether the SECOND node's session-connect
  call path (reusing the already-open `_zenohSession` singleton, refcounted from the first node)
  behaves differently now that a session already exists.
- Remove all temporary diagnostic `printf` tracing once CELL2 is fully working (see the
  `emscripten-rx-debug.patch` note above, plus the `[HS_DEBUG]`/`[READ_WS_DEBUG]` prints still in
  `emscripten-resumable-handshake.patch`/`emscripten-nonblocking-io.patch`).
- Once JupyterLite/Python pub-sub is fully confirmed end-to-end, restructure `browser_demo`'s C++
  rclc/rclcpp demo (still uses blocking `spin()`) to the same non-blocking + Python-retry-style
  pattern -- likely needs an analogous "pump this from a JS `setInterval`" driver since there's no
  Python/asyncio layer there.
- Re-pin `pixi.toml`'s `vinca` dependency back to a real pushed git commit (currently a local path
  override) once the vinca template changes are committed and pushed.

### CELL2 hang root-caused (partially): NOT the session-open path -- a SECOND Node() truly hangs (not a clean retry-able failure)

Confirmed via the harness's own added print markers: `setup_and_spin: creating sub_node...`
prints, then the entire browser tab goes fully unresponsive (even a trivial `javascript_exec`
call times out) -- no `Node() attempt N failed` prints ever appear, unlike the FIRST node's
construction (which cleanly failed-and-retried 2 times before succeeding). This means the second
`Node()` call is not hitting our new retry-able exception path at all -- it's a genuine, silent,
uninterruptible native hang, most likely a real blocking wait somewhere we haven't patched.

Ruled out via source inspection (`rmw_zenoh_pico/src/rmw_node.c`'s `rmw_create_node()` and
`declaration_node_data()`):
- `session_connect()` should return `RMW_RET_OK` immediately for the second node -- the
  `_zenohSession` singleton (ref-counted in `zenoh_pico_generate_session()`) is already
  connected from the first node, so `if (session->enable_session) return RMW_RET_OK;` should
  short-circuit before ever touching `z_open()`/our resumable handshake again.
- `declaration_node_data()`'s `z_liveliness_declare_token()` → `_z_declare_liveliness_token()`
  (`zenoh-pico/src/net/liveliness.c`) is a fire-and-forget `_z_send_declare()` (write-only, no
  reply wait) -- confirmed by reading its source, not just assumed.

**Not yet root-caused**: something else, most likely a graph-discovery/query-reply operation
triggered specifically by having a SECOND node coexist with the first (e.g. rclpy eagerly
populating its graph cache, or some other component querying the OTHER node's TypeDescription
or similar), that involves a genuine query+wait-for-reply round trip -- the same fundamental
class of problem as the session-open handshake (a real network round trip inside one synchronous
call, no Asyncify to yield), but in a DIFFERENT code path we haven't identified precisely yet.
Zenohd's own debug log around this point shows it processing a `send_close` for the FIRST node's
session/resources (liveliness token unpropagation, parameter_events resource cleanup) -- worth
investigating whether this close is a stray/leftover artifact from one of the two intentionally-
failed early attempts, or something actually torn down the working first session.

**Next steps for whoever picks this back up**: reproduce in a way that doesn't freeze the whole
tab (e.g. run the sub_node creation in a Web Worker, or add a hard wall-clock watchdog around the
call using `Promise.race` with a timeout at the JS level before assuming a hang vs. just slow);
grep `rclpy`'s own `Node.__init__` and `rmw_zenoh_pico`'s remaining `rmw_*` entry points called
during node creation (parameter services, `rcl_node_init`'s own graph-info bookkeeping) for
anything doing a query-and-wait; consider whether this needs the SAME resumable/retry treatment
as session-open, applied to whatever this new blocking call turns out to be.

This is a **separate, narrower** problem from "THE CURRENT BLOCKER" section above, which is now
fully solved and confirmed working (`rclpy.init()` + first `Node()` construction succeed
end-to-end via the resumable handshake). Reported to the user as a natural checkpoint before
continuing further, since the specific thing they asked to be built (the non-blocking
session-open state machine) is done.

### CELL2 hang, ROOT-CAUSED: not a new blocker at all -- the test harness's own idle sleeps let the zenoh session lease expire

Confirmed via a controlled experiment: shortened the gap between CELL1 (first `Node()`) and a
diagnostic cell (constructing a second, raw `_rclpy.Node()` directly) from 15 seconds down to 2
seconds. **The second node construction succeeded instantly, no hang at all.** With the 15-second
gap, it hung solid every time.

Root cause: `Z_TRANSPORT_LEASE` is 10000ms (`zenoh-pico/include/zenoh-pico/config.h`) --
zenohd expects periodic keep-alive traffic from a client to consider its session alive. This
project's whole single-threaded (`Z_FEATURE_MULTI_THREAD=0`) architecture relies on the
*application* pumping `zp_send_keep_alive()`/`zp_read()` manually (that's what `rmw_wait()`'s
poll loop already does whenever something calls `rclpy.spin_once()`) -- there is no background
thread doing this automatically, by design. The test harness's own artificial `await
sleep(15000)` gaps between cells, with nothing calling `spin_once()` in between, let the session
go quiet long enough for zenohd to expire and close it server-side -- so the SECOND node's
construction attempt was genuinely trying to use an already-dead connection, hanging forever
waiting for a reply that could never arrive (our client-side code never even noticed the
server-initiated close, since nothing was polling `recv()` during the idle gap either).

**This is not a new architectural gap** -- it's a consequence of test-harness sleeps being far
longer and less representative than real interactive notebook usage (where a user runs cells in
reasonably close succession, and any `spin_once()`/`spin()` call along the way keeps the lease
alive). Fixed by shortening the harness's inter-cell sleeps to realistic values. **For genuine
long-idle robustness** (a notebook cell that sits untouched for a long time before the next one
runs), a background keep-alive pump would be needed eventually -- noted as a real, but separate
and much lower-priority, follow-up; not a blocker for the core pub/sub demo working.

### CELL2 continued: node hang was a red herring (lease expiry from harness sleeps); pub/sub now runs cleanly but only 1 of 20 published messages reaches the router

Two fixes landed since the last update:
1. Confirmed via a controlled experiment that the "second Node() hangs" symptom was purely a
   test-harness artifact: shortening the gap between cells from 15s to 2s made the second
   `Node()` succeed instantly. Root cause: `Z_TRANSPORT_LEASE` (10000ms) requires periodic
   keep-alive traffic, which only happens when something calls `rclpy.spin_once()` -- our
   harness's own long idle `await sleep()` gaps between cells (with nothing spinning) let
   zenohd expire and close the session, so the second node tried to use an already-dead
   connection. Not a new architectural gap.
2. `create_publisher()`/`create_subscription()` (unlike the one internal `/parameter_events`
   publisher already patched) still default to `PublisherEventCallbacks()`/
   `SubscriptionEventCallbacks()` **with** default callbacks enabled, hitting the same
   `rmw_event.c:242` "Publisher implementation identifier not from this implementation" error
   as before. Fixed in the test harness by passing `use_default_callbacks=False` explicitly to
   both -- **this is a real, general limitation of rmw_zenoh_pico for ANY real notebook usage
   going forward, not just this test**: any `create_publisher()`/`create_subscription()` call
   needs this passed explicitly (or rclpy's own defaults need patching project-wide, not yet
   done -- consider whether to change `create_publisher`/`create_subscription`'s OWN default in
   the rclpy patch, rather than requiring every call site to remember this).
3. Also found: the spin loop was only pumping `sub_node` via `rclpy.spin_once()` -- adding a
   second `rclpy.spin_once(node, timeout_sec=0)` call (for the PUBLISHER's own node) was needed
   too, since each rmw "node" has its own wait-set/dispatch bookkeeping even though both nodes
   share the same underlying zenoh session.

With all of the above, the full CELL2 lifecycle now runs end-to-end with **zero exceptions**:
sub_node construction, publisher/subscription creation, a 4-second spin+publish loop, and clean
shutdown all complete normally. **But `received count: 0`** -- the subscriber's `on_msg` callback
never actually fires, even though a publisher and subscriber both exist for the same topic.

Root-caused (partially) via `zenohd`'s debug log: `declare_subscriber` for `chatter` DOES appear
(confirms the subscription was properly registered with the router this time, thanks to fix #3
above) and exactly ONE `send_push`/`compute_data_route` event appears, WITH a valid computed
route (`return=[Direction{dst=...}]`) -- meaning the very first `pub.publish()` call's data
genuinely reached the router and was routed correctly. But messages 2 through 20 never produced
another `send_push` log line, and ~14 seconds after that first successful push, the log shows
`RX task failed: ... expired after 10000 milliseconds` -- the session died again from pure
inactivity, meaning nothing (no further publishes, no keep-alives) reached the wire after that
first message.

**Leading hypothesis, not yet confirmed**: zenoh-pico's write path may batch outgoing messages
(`Z_FEATURE_BATCHING`, referenced in `transport/unicast/transport.c`'s
`_z_transport_start_batching`/`_z_transport_stop_batching`) and only actually flush the batch to
the socket via a mechanism this project's single-threaded (`Z_FEATURE_MULTI_THREAD=0`)
architecture never triggers -- normally a background thread's job. If so, `pub.publish()` calls
2-20 may be silently accumulating in an internal buffer that nothing ever flushes, while only the
first call (or some threshold-triggered flush) actually reached the socket. Also worth checking:
whether `_z_send_ws`'s new single-attempt, non-blocking design has a related but DISTINCT bug --
DATAGRAM-flow callers (`_z_link_send_wbuf` in `link.c`) only treat a write as failed when it
returns `SIZE_MAX`; a send that silently transmits **zero** bytes (which our rewritten
`_z_send_ws` can now return, unlike a real blocking send that either fully succeeds or hard-fails)
would NOT be caught as an error there, silently dropping data with no retry -- worth checking
whether `_z_send_ws` should return `SIZE_MAX` rather than 0 when the underlying `send()` sends
nothing at all, to make that failure mode visible to callers that already know how to handle it.

Not yet resolved -- next session should check `Z_FEATURE_BATCHING`'s actual state in this
project's zenoh-pico build config, and audit `_z_send_ws`'s zero-vs-SIZE_MAX return semantics
against every DATAGRAM-flow caller, before assuming which of the two (or something else) is the
real cause.

**Follow-up: ruled out both leading hypotheses for "only 1 of 20 messages reaches the router".**
Checked via source: `Z_FEATURE_BATCHING` IS enabled by default in this build
(`zenoh-pico/include/zenoh-pico/config.h`), but batching is opt-in at runtime
(`zp_batch_start()`/`zp_batch_stop()`, public API functions) -- confirmed rmw_zenoh_pico never
calls them, so `_batch_state` stays `_Z_BATCHING_IDLE` and every write should flush immediately,
un-batched. Also checked `_z_transport_tx_mutex_lock()` (`transport/transport.h`): under
`Z_FEATURE_MULTI_THREAD == 0` (this project's config) it's an unconditional no-op returning
`_Z_RES_OK` regardless of the `block`/congestion-control argument -- no drop-on-congestion path
is actually reachable here either. So the write path should be unconditional and immediate for
every single `_z_send_n_msg` call; neither batching nor congestion-control/mutex logic explains
why messages 2-20 never produced a `send_push` log line.

**Not yet investigated**: whether ROS2's default RELIABLE QoS introduces a sliding-window /
sequence-number-based flow-control mechanism in zenoh-pico's reliability layer that requires an
ACK (arriving via the read/`zp_read()` path) before advancing to send further messages -- this
would fit the observed symptom (first message goes out fine, subsequent ones stall) if the
ACK-processing side has its own gap. Worth checking `_z_transport_tx_send_n_msg_inner` and
whatever sequence-number/retransmission bookkeeping exists in the reliability path for a
non-blocking-compatibility gap, following the same root-cause-via-zenohd-log-plus-source-reading
approach that resolved every previous layer of this investigation.

**Follow-up: BEST_EFFORT QoS ruled out too -- same symptom persists regardless of reliability.**
Switched both publisher and subscription to explicit `BEST_EFFORT` QoS (sidestepping any
reliable-QoS ACK/retransmission machinery entirely) and gave the test much more runway (8s
publish window, 39 messages actually attempted this run). **Identical result**: `zenohd`'s debug
log shows exactly one `send_push`/`compute_data_route` event, no matter how many `pub.publish()`
calls happen or which QoS reliability is used. Also noticed the router's own log line still says
`is_reliable=true` for that one push regardless of the BEST_EFFORT QoS setting -- rmw_zenoh_pico
apparently never maps ROS QoS reliability down to a real zenoh-level distinction here, which is
consistent with "changing QoS made zero difference."

**New leading hypothesis, more specific, not yet confirmed**: zenoh-pico's own client-side
"write filter" optimization (`src/net/filtering.c`, gated by `Z_FEATURE_INTEREST`) exists
specifically to suppress `z_put()`/publish calls when the client believes there are no matching
subscribers, to avoid wasting bandwidth. Its state (`ctx->state`, `WRITE_FILTER_ACTIVE` = suppress
vs `WRITE_FILTER_OFF` = allow) is computed as `(ctx->targets == NULL && ctx->local_targets == 0)`
-- i.e. it *actively drops writes* unless it has at least one known target. `ctx->targets` is a
list populated when the ROUTER sends back an "interest" declaration in response to our own
subscriber's declaration (this project's own subscriber declaring itself IS visible in zenohd's
log, and interest/token propagation IS logged happening) -- meaning the filter almost certainly
was legitimately OFF (allowing writes) for exactly long enough to let that first message out, then
flipped back to ACTIVE afterward, silently dropping every later `publish()` call with no error
surfaced to Python at all (this call path doesn't return an error even when the filter drops the
write -- confirmed indirectly: `pub.publish()` never raised an exception in any test run).

**Not yet found**: the actual code path that would cause `ctx->targets`/`ctx->local_targets` to
revert to empty shortly after being populated. Candidates for next session to check, roughly in
order of suspicion:
1. Whether the same class of problem that hit session keep-alives (nothing pumping
   `zp_read()`/`zp_send_keep_alive()` frequently/promptly enough without a real background
   thread) also starves whatever incoming message keeps this target list alive/refreshed -- i.e.
   maybe the "interest" registration itself needs to be periodically refreshed/re-affirmed by an
   incoming message that our polling cadence (`rclpy.spin_once(..., timeout_sec=0)` in a 50ms
   Python loop) isn't delivering promptly enough, and it expires similarly to the session lease.
2. Whether `_z_write_filter_ctx_remove_local_match`/target-removal logic
   (`Z_FEATURE_LOCAL_SUBSCRIBER`-gated) fires incorrectly for this project's specific "publisher
   and subscriber share one session, no real separate local-process dispatch" topology -- worth
   checking whether `Z_FEATURE_LOCAL_SUBSCRIBER` is even enabled in this build
   (`extra_recipes/zenoh-pico/build.sh` doesn't set it explicitly; check `config.h`'s default).
3. Whether some OTHER unrelated event (e.g. the same kind of spurious "session looks idle, tear
   something down" logic already found and fixed once for the session-open handshake) is
   incorrectly interpreting normal idle time between publishes as a signal to drop the write
   filter's targets.

Same investigative pattern that resolved every earlier layer should work here too: add targeted
`printf` tracing directly in `_z_write_filter_ctx_update_state`/`_z_write_filter_push_target`/
`_z_write_filter_ctx_remove_local_match` to see exactly when and why `ctx->state` flips back to
`WRITE_FILTER_ACTIVE`, cross-referenced against `zenohd`'s own debug log timeline (the
`RUST_LOG=debug` + REST admin space + `WebSocket` constructor monkeypatch tooling built up this
session in `scratch/noasyncify_test/browser_test.html` all remain in place and are still the
fastest way to root-cause this class of bug).

### Session status summary (for whoever picks this up next)

**Fully working, confirmed end-to-end**: `import rclpy`, `rclpy.init()` (with retry),
`Node()` construction (with retry, including a second node reusing the same session), publisher/
subscriber object creation (with the `use_default_callbacks=False` workaround), and a full
spin/publish loop running for 8+ seconds with zero crashes or exceptions anywhere in the stack.
This is the architectural goal the user asked for this session ("build the non-blocking state
machine") -- done, and confirmed via a real browser test, not just reasoning.

**Not yet working**: actual message delivery beyond the very first publish -- subscriber's
`on_msg` callback never fires (`received count: 0` every run so far), even though the very first
`pub.publish()` call after subscriber registration does get routed correctly by `zenohd`. This is
now narrowed to zenoh-pico's own client-side write-filter optimization silently suppressing later
writes, not a browser/Asyncify/threading issue -- a genuinely different, narrower class of bug
than everything else fixed this session, likely fixable with the same tracing-driven approach.

**Follow-up: pub/sub creation ORDER ruled out too** (creating the subscription before the
publisher made no difference -- still exactly one `send_push` per run, confirmed via `zenohd`'s
log). **Found the precise mechanism that flips the write filter back to blocking**, via
`src/net/filtering.c`'s `_z_write_filter_callback()`: it handles four interest-message types --
`DECL_SUBSCRIBER`/`DECL_QUERYABLE` (adds a target), `UNDECL_SUBSCRIBER`/`UNDECL_QUERYABLE`
(removes one target), and **`_Z_INTEREST_MSG_TYPE_CONNECTION_DROPPED`, which wipes ALL targets
for that peer at once** (`_z_filter_target_slist_drop_all_filter(..., _z_filter_target_peer_eq,
...)`). Given this whole investigation has already found multiple cases of this project's
single-threaded, no-Asyncify architecture producing spurious "connection looks dead" signals
(the session-lease-expiry issue fixed a few sections up is the clearest precedent), a
`CONNECTION_DROPPED` interest message firing shortly after the one real subscriber declaration
arrives -- even though the connection is still nominally alive -- would exactly explain "exactly
one write gets through, then every later one is silently dropped with no error," matching every
run's observed behavior regardless of QoS or creation order.

**This is the concrete next thing to check**, with `printf` tracing directly in
`_z_write_filter_callback()` (log `msg->type` and the peer/connection identity on every call) to
confirm whether a spurious `CONNECTION_DROPPED` event is really what's firing, and if so, trace
backward to find what's synthesizing it. Not confirmed this session -- ran out of session budget
to chase it further, but the exact file, function, and mechanism are now pinned down precisely
enough that this should be a fast, bounded fix for whoever picks it up next (same
`printf`-tracing-plus-`zenohd`-log-cross-reference technique used for every other layer this
session).
