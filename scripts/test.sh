#!/bin/zsh
set -euo pipefail
MINI_ROOT="${0:A:h:h}"
cd "$MINI_ROOT"
export CLANG_MODULE_CACHE_PATH=/tmp/campus-rhythm-mini-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/campus-rhythm-mini-swift-cache
swift test --disable-sandbox --scratch-path /tmp/campus-rhythm-mini-tests --cache-path /tmp/campus-rhythm-mini-spm-cache --config-path /tmp/campus-rhythm-mini-spm-config --security-path /tmp/campus-rhythm-mini-spm-security -debug-info-format none
