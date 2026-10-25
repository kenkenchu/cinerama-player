#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK_DIR="${ROOT_DIR}/Frameworks/VLCKit.xcframework"
VERSION="3.7.3-319ed2c0-79128878"
SHA256="019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d"
STAMP="${FRAMEWORK_DIR}/cinerama-macos-vlckit.sha256"
CACHE_DIR="${ROOT_DIR}/.build/macos-vlckit"
ARCHIVE="${CACHE_DIR}/VLCKit-${VERSION}.tar.xz"

if [ -f "${STAMP}" ] && [ "$(cat "${STAMP}")" = "${SHA256}" ] &&
   [ -f "${FRAMEWORK_DIR}/macos-arm64_x86_64/VLCKit.framework/VLCKit" ]; then
    echo "Desktop VLCKit ${VERSION} is installed."
    exit 0
fi
mkdir -p "${CACHE_DIR}"
if [ ! -f "${ARCHIVE}" ]; then
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
        "https://download.videolan.org/pub/cocoapods/prod/VLCKit-${VERSION}.tar.xz" \
        --output "${ARCHIVE}.partial"
    mv "${ARCHIVE}.partial" "${ARCHIVE}"
fi
printf '%s  %s\n' "${SHA256}" "${ARCHIVE}" | shasum -a 256 --check
STAGE_DIR="$(mktemp -d "${CACHE_DIR}/stage.XXXXXX")"
trap 'rm -rf "${STAGE_DIR}"' EXIT
tar -xf "${ARCHIVE}" -C "${STAGE_DIR}" 'VLCKit - binary package/VLCKit.xcframework'
mkdir -p "${ROOT_DIR}/Frameworks"
rm -rf "${FRAMEWORK_DIR}"
mv "${STAGE_DIR}/VLCKit - binary package/VLCKit.xcframework" "${FRAMEWORK_DIR}"
printf '%s\n' "${SHA256}" > "${STAMP}"
echo "Desktop VLCKit ${VERSION} installed (stock VideoLAN build)."
