#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
: "${DUSK_TVOS_TEAM:?Set DUSK_TVOS_TEAM to your Apple Development team ID.}"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo 'error: install XcodeGen with brew install xcodegen.' >&2
    exit 1
fi
xcodegen generate
python3 scripts/verify_platform_boundaries.py
TV_DESTINATION='generic/platform=tvOS'
if [ -n "${DUSK_TVOS_DEVICE_ID:-}" ]; then
    TV_DESTINATION="platform=tvOS,id=${DUSK_TVOS_DEVICE_ID}"
fi
xcodebuild -project Dusk.xcodeproj -scheme Dusk-tvOS -configuration Debug \
    -destination "${TV_DESTINATION}" -derivedDataPath .build/tvos/DerivedData \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    "DUSK_TVOS_TEAM=${DUSK_TVOS_TEAM}" CODE_SIGNING_ALLOWED=YES build
TV_APP_PATH="${ROOT_DIR}/.build/tvos/DerivedData/Build/Products/Debug-appletvos/DuskTV.app"
if [ ! -f "${TV_APP_PATH}/embedded.mobileprovision" ]; then
    echo 'error: no device provisioning profile was embedded.' >&2
    exit 1
fi
codesign --verify --deep --strict "${TV_APP_PATH}"
echo "Built and signed TV app: ${TV_APP_PATH}"
echo 'Install with xcrun devicectl device install app --device DEVICE_ID followed by the app path.'
