#!/bin/bash
set -euo pipefail

# Builds Frameworks/CineramaDovi.xcframework (Dolby Vision 7 -> 8.1 conversion,
# Rust) from Native/CineramaDovi. Like VLCKit it is git-ignored: CI runs this via
# ci_scripts/ci_post_clone.sh, and it must be run once locally after cloning.
#
# Idempotent: a hash of every build input is stamped into the xcframework, so
# it is a no-op until the crate, the toolchain pin, the build script or the
# deployment targets change.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK_DIR="${ROOT_DIR}/Frameworks/CineramaDovi.xcframework"
STAMP_PATH="${FRAMEWORK_DIR}/cinerama-dovi-source.sha256"
BUILD_SCRIPT="${ROOT_DIR}/scripts/build_cinerama_dovi_xcframework.sh"
SLICES=(macos-arm64)

source_hash() {
    (
        cd "${ROOT_DIR}"
        {
            find Native/CineramaDovi/Cargo.toml Native/CineramaDovi/Cargo.lock \
                Native/CineramaDovi/rust-toolchain.toml Native/CineramaDovi/src \
                Native/CineramaDovi/include scripts/build_cinerama_dovi_xcframework.sh \
                -type f ! -name .DS_Store -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
            grep -E '^    macOS: ' project.yml
        } | shasum -a 256 | cut -d ' ' -f 1
    )
}

has_current_build() {
    [ -f "${STAMP_PATH}" ] || return 1
    [ "$(cat "${STAMP_PATH}")" = "${EXPECTED_HASH}" ] || return 1
    local slice
    for slice in "${SLICES[@]}"; do
        [ -f "${FRAMEWORK_DIR}/${slice}/libcinerama_dovi.a" ] || return 1
    done
}

EXPECTED_HASH="$(source_hash)"

if has_current_build; then
    echo "CineramaDovi.xcframework is up to date."
    exit 0
fi

rustup_path="${CARGO_HOME:-${HOME}/.cargo}/bin/rustup"
if [ ! -x "${rustup_path}" ] && ! command -v rustup >/dev/null 2>&1; then
    if [ -n "${CI:-}" ] || [ -n "${CI_XCODE_CLOUD:-}" ]; then
        echo "Installing rustup (no default toolchain; the build pins its own)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
            | sh -s -- -y --profile minimal --default-toolchain none --no-modify-path
    else
        cat >&2 <<'EOF'
error: rustup is required to build CineramaDovi.xcframework.
Install it from https://rustup.rs (Homebrew's `rust` formula is not enough:
it has no pinned target standard library), then rerun ./ci_scripts/install_cinerama_dovi.sh.
EOF
        exit 1
    fi
fi

"${BUILD_SCRIPT}"
printf '%s\n' "${EXPECTED_HASH}" > "${STAMP_PATH}"
echo "CineramaDovi.xcframework installed."
