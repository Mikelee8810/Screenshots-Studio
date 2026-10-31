#!/bin/bash
# Compile and run Gottr's logic tests (all Sources except main.swift, plus the test harness).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
MIN_OS="14.0"
mkdir -p "$ROOT/build"

SRCS=$(find "$ROOT/Sources" -name '*.swift' ! -name 'main.swift')

# shellcheck disable=SC2086
swiftc -swift-version 5 \
    -parse-as-library \
    -target "arm64-apple-macosx${MIN_OS}" \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework Cocoa -framework ScreenCaptureKit -framework CoreMedia \
    -framework Carbon -framework UniformTypeIdentifiers \
    "$ROOT/Tests/ScreenshotsTests.swift" $SRCS \
    -o "$ROOT/build/screenshots_tests"

"$ROOT/build/screenshots_tests"
