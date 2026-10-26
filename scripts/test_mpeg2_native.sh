#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
./ci_scripts/install_cinerama_mpeg2.sh
CACHE="$ROOT_DIR/.build/metal-mpeg2"
PREFIX="$CACHE/install"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun clang++ -isysroot "$SDK" -std=c++17 -O2 -I "$PREFIX/include" Native/CineramaMPEG2/Tests/GenerateFixture.cpp \
    -L "$PREFIX/lib" -lavformat -lavcodec -lavutil -lswresample -lz -liconv -lbz2 \
    -framework Security -framework CoreFoundation -o "$CACHE/generate-fixture"
FRAMEWORK="$ROOT_DIR/Frameworks/CineramaMPEG2.xcframework/macos-arm64"
xcrun clang++ -isysroot "$SDK" -std=c++17 -O2 -fobjc-arc -I Native/CineramaMPEG2/include \
    -F "$FRAMEWORK" -framework CineramaMPEG2 -framework Foundation -framework CoreMedia -framework CoreVideo -framework AudioToolbox \
    Native/CineramaMPEG2/Tests/DecodeTests.mm -Wl,-rpath,"$FRAMEWORK" -o "$CACHE/decode-tests"
mkdir -p "$CACHE/fixtures"
for spec in progressive interlaced bottom-first surround tracks chroma422 hd-interlaced hls; do
    interlaced=0; chroma=0; hd=0; extension=ts; audio=0; channels=2
    case "$spec" in interlaced) interlaced=1;; bottom-first) interlaced=2;; surround) audio=1; channels=6;; tracks) audio=2; channels=6;; chroma422) interlaced=1; chroma=1;; hd-interlaced) interlaced=1; hd=1;; hls) extension=m3u8;; esac
    fixture="$CACHE/fixtures/$spec.$extension"
    "$CACHE/generate-fixture" "$fixture" "$interlaced" "$chroma" "$hd" "$audio"
    expected=90
    if [ "$interlaced" -ne 0 ]; then expected=180; fi
    MTL_DEBUG_LAYER=1 "$CACHE/decode-tests" "$fixture" "$expected" "$channels"
done
MTL_DEBUG_LAYER=1 python3 Native/CineramaMPEG2/Tests/LiveHLSTest.py "$CACHE/fixtures" "$CACHE/decode-tests"
