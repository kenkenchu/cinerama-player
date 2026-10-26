#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
: "${CINERAMA_MACOS_SIGNING_IDENTITY:?Set CINERAMA_MACOS_SIGNING_IDENTITY to the installed Apple Development identity.}"
./scripts/test_mpeg2_native.sh --prepare-renderer-fixture
xcodegen generate
python3 scripts/verify_platform_boundaries.py
xcodebuild -project Cinerama.xcodeproj -scheme Cinerama-macOS -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/macos/DerivedData \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
    "CODE_SIGN_IDENTITY=${CINERAMA_MACOS_SIGNING_IDENTITY}" test "$@"
