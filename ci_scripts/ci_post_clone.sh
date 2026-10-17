#!/bin/bash
set -euo pipefail
# Bootstrap the native macOS app on CI. Never launches the app or runs tests.
ROOT_DIR="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
"${ROOT_DIR}/ci_scripts/install_macos_vlckit.sh"
"${ROOT_DIR}/ci_scripts/install_dusk_dovi.sh"

# Xcode 26 and later ship the Metal compiler as a separate component that is not
# installed in the Xcode Cloud images. Without it, compiling
# VideoEnhancementShaders.metal fails with "cannot execute tool 'metal' due to
# missing Metal Toolchain" (preceded by a red herring: a warning that the
# shader's .dia diagnostics file does not exist, because metal never ran).
#
# The images do carry the component, but only as an *exported bundle* staged in
# DVTDownloads and never imported, which is the trap: `-downloadComponent` sees
# that bundle, reports "Metal Toolchain is already imported", and exits non-zero
# without installing anything. The bundle has to be imported explicitly. Local
# machines have no such bundle and just download it.
metal_is_usable() {
    xcrun --sdk macosx metal --version >/dev/null 2>&1
}

if metal_is_usable; then
    echo "Metal toolchain already installed."
else
    # The image stages the bundle in the build user's home; search the other home
    # directories too, in case the build runs as someone else.
    staged_bundle="$(ls -d \
        "${HOME}"/Library/Developer/DVTDownloads/Assets/MetalToolchain/*.exportedBundle \
        /Users/*/Library/Developer/DVTDownloads/Assets/MetalToolchain/*.exportedBundle \
        2>/dev/null | head -1 || true)"

    if [ -n "${staged_bundle}" ]; then
        echo "Importing the staged Metal toolchain from ${staged_bundle}"
        xcodebuild -importComponent MetalToolchain -importPath "${staged_bundle}" || true
    fi

    # Last resort: move the staged bundle aside, since its mere presence is what
    # makes `-downloadComponent` bail out instead of installing the component.
    if [ -n "${staged_bundle}" ] && ! metal_is_usable; then
        echo "Import did not take; moving ${staged_bundle} aside so it can be downloaded."
        mv "${staged_bundle}" "${TMPDIR:-/tmp}/$(basename "${staged_bundle}").unused" || true
    fi

    if ! metal_is_usable; then
        echo "Downloading the Metal toolchain."
        xcodebuild -downloadComponent MetalToolchain || true
    fi
fi

# Fail here rather than 10 minutes later in CompileMetalFile, where the error is
# buried under the .dia warning.
if ! metal_is_usable; then
    echo "error: the Metal toolchain is unavailable, so the shaders cannot compile." >&2
    xcodebuild -showComponent MetalToolchain >&2 || true
    exit 1
fi

echo "Metal toolchain ready; VideoEnhancementShaders.metal can compile."
