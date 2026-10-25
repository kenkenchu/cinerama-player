#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
: "${CINERAMA_TVOS_TEAM:?Set CINERAMA_TVOS_TEAM to your Apple Development team ID.}"
: "${CINERAMA_TVOS_DEVICE_ID:?Set CINERAMA_TVOS_DEVICE_ID to the connected Apple TV Xcode destination ID.}"
xcodegen generate
python3 scripts/verify_platform_boundaries.py
# Runs the hosted unit tests on the paired TV. No simulator or manual app launch.
xcodebuild -project Cinerama.xcodeproj -scheme Cinerama-tvOS -configuration Debug \
    -destination "platform=tvOS,id=${CINERAMA_TVOS_DEVICE_ID}" -derivedDataPath .build/tvos/DerivedData \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    "CINERAMA_TVOS_TEAM=${CINERAMA_TVOS_TEAM}" CODE_SIGNING_ALLOWED=YES test "$@"
