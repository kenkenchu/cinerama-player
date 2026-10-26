#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
./ci_scripts/install_cinerama_mpeg2.sh tvos
./ci_scripts/install_cinerama_mpeg2.sh tvos-simulator
OUTPUT="$ROOT_DIR/Frameworks/CineramaMPEG2TV.xcframework"
STAMP="$(cat Frameworks/CineramaMPEG2-tvos.xcframework/source.sha256 Frameworks/CineramaMPEG2-tvos-simulator.xcframework/source.sha256 | shasum -a 256 | cut -d ' ' -f 1)"
if [ -f "$OUTPUT/source.sha256" ] && [ "$(cat "$OUTPUT/source.sha256")" = "$STAMP" ]; then exit 0; fi
if [ -d "$OUTPUT" ]; then mv "$OUTPUT" "$ROOT_DIR/.build/metal-mpeg2-tvos/previous-combined-$(date +%s)"; fi
xcodebuild -create-xcframework \
 -framework .build/metal-mpeg2-tvos/flat/CineramaMPEG2.framework \
 -framework .build/metal-mpeg2-tvos-simulator/flat/CineramaMPEG2.framework -output "$OUTPUT"
printf '%s\n' "$STAMP" > "$OUTPUT/source.sha256"
