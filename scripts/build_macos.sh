#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo 'error: install XcodeGen with brew install xcodegen.' >&2
    exit 1
fi
xcodebuild -version
if ! xcrun --sdk macosx metal --version >/dev/null 2>&1; then
    echo 'error: install the Metal compiler with xcodebuild -downloadComponent MetalToolchain.' >&2
    exit 1
fi
./ci_scripts/install_macos_vlckit.sh
./ci_scripts/install_cinerama_dovi.sh
xcodegen generate
python3 scripts/verify_platform_boundaries.py
xcodebuild -project Cinerama.xcodeproj -scheme Cinerama-macOS -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .build/macos/DerivedData \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
    "CODE_SIGN_IDENTITY=${CINERAMA_MACOS_SIGNING_IDENTITY:--}" build

APP_PATH="${ROOT_DIR}/.build/macos/DerivedData/Build/Products/Debug/Cinerama.app"
codesign --verify --deep --strict "${APP_PATH}"
echo "Built and locally signed: ${APP_PATH}"
echo 'On first launch, allow Cinerama in System Settings > Privacy & Security > Local Network.'
