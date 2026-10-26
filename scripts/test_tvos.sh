#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
./ci_scripts/install_cinerama_mpeg2_tvos.sh
./scripts/test_mpeg2_native.sh --prepare-renderer-fixture
xcodegen generate
python3 scripts/verify_platform_boundaries.py
if [ -n "${CINERAMA_TVOS_DEVICE_ID:-}" ]; then
    : "${CINERAMA_TVOS_TEAM:?Set CINERAMA_TVOS_TEAM to your Apple Development team ID for device tests.}"
    xcodebuild -project Cinerama.xcodeproj -scheme Cinerama-tvOS -configuration Debug \
        -destination "platform=tvOS,id=${CINERAMA_TVOS_DEVICE_ID}" -derivedDataPath .build/tvos/DerivedData \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
        "CINERAMA_TVOS_TEAM=${CINERAMA_TVOS_TEAM}" CODE_SIGNING_ALLOWED=YES test "$@"
else
    TV_TEST_SIMULATOR_ID="${CINERAMA_TVOS_SIMULATOR_ID:-}"
    if [ -z "${TV_TEST_SIMULATOR_ID}" ]; then
        TV_TEST_SIMULATOR_ID="$(python3 - <<'PY'
import json
import subprocess

def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True).strip()

runtimes = [runtime for runtime in json.loads(simctl("list", "runtimes", "--json"))["runtimes"]
            if runtime.get("isAvailable") and ".tvOS-" in runtime["identifier"]
            and runtime["version"].split(".")[0] == "26"]
if not runtimes:
    raise SystemExit("No tvOS 26 simulator runtime installed. Run: xcodebuild -downloadPlatform tvOS -buildVersion 26.0 -architectureVariant arm64")
runtime = max(runtimes, key=lambda value: tuple(int(part) for part in value["version"].split(".")))
devices = json.loads(simctl("list", "devices", "available", "--json"))["devices"]
existing = next((device for device in devices.get(runtime["identifier"], [])
                 if device["name"] == "Cinerama TV Tests"), None)
print(existing["udid"] if existing else simctl(
    "create", "Cinerama TV Tests",
    "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-1080p", runtime["identifier"]))
PY
)"
    fi
    # Simulator tests need neither a connected Apple TV nor a provisioning team.
    # Their products are isolated from signed apps intended for physical devices.
    xcodebuild -project Cinerama.xcodeproj -scheme Cinerama-tvOS -configuration Debug \
        -destination "platform=tvOS Simulator,id=${TV_TEST_SIMULATOR_ID}" \
        -derivedDataPath .build/tvos-simulator/DerivedData CODE_SIGNING_ALLOWED=NO test "$@"
fi
