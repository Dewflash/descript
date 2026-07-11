#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
export COPYFILE_DISABLE=1

echo "==> [1/3] Typecheck app sources"
swiftc -typecheck -parse-as-library \
  Sources/DescriptApp.swift \
  Sources/DescriptModel.swift \
  Sources/TranscriptServices.swift

echo "==> [2/3] Build app bundle and release artifacts"
./build.sh

echo "==> [3/3] YouTube transcript smoke (network)"
if [[ "${DESCRIPT_SKIP_NETWORK:-0}" == "1" ]]; then
  echo "SKIPPED network smoke (DESCRIPT_SKIP_NETWORK=1) — gates require the full run"
else
  swiftc -O -parse-as-library \
    -o build/smoke-youtube \
    SmokeYouTube.swift \
    Sources/TranscriptServices.swift \
    -framework AVFoundation \
    -framework Speech \
    -framework UniformTypeIdentifiers
  ./build/smoke-youtube
fi

echo "VERIFY OK"
