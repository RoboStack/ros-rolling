#!/usr/bin/env bash
# See pixi.toml's sync-native-bootstrap-mirror task for why this mirror
# exists at all. The mirror directory has to be named after *this
# machine's own* native platform -- rattler-build's solver only ever
# looks at the channel subdirectory matching build_platform, which is
# wherever this script actually runs (osx-arm64 on an Apple Silicon Mac,
# linux-64 on the ubuntu-latest GitHub Actions runner this repo's own CI
# uses, etc.) -- a hardcoded platform name here silently mirrors into a
# directory the solver never looks at on any other machine, so nothing
# fails loudly, entire closure just never gets past its native-bootstrap
# bottleneck. Confirmed missing exactly this way on CI, 2026-09-10: it
# was hardcoded to osx-arm64 (right for local dev on this project's own
# Mac, wrong for the ubuntu-latest runner CI actually uses).
set -euo pipefail

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) NATIVE_PLATFORM=linux-64 ;;
  Linux-aarch64|Linux-arm64) NATIVE_PLATFORM=linux-aarch64 ;;
  Darwin-arm64) NATIVE_PLATFORM=osx-arm64 ;;
  Darwin-x86_64) NATIVE_PLATFORM=osx-64 ;;
  *)
    echo "sync_native_bootstrap_mirror.sh: unrecognized platform '$(uname -s)-$(uname -m)' -- add a case for it (see pixi.toml's own [workspace] platforms list for the full set this repo targets)." >&2
    exit 1
    ;;
esac

mkdir -p "output/emscripten-wasm32" "output/$NATIVE_PLATFORM"
find "output/emscripten-wasm32" -maxdepth 1 -name '*.tar.bz2' -exec cp {} "output/$NATIVE_PLATFORM/" \;
rattler-index fs output --force
