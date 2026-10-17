# Mac Screenshots and Visual Verification

This fork has no mobile simulator screenshot harness or App Store screenshot
pipeline. The inherited mobile/TV marketing images and `screenshots/` directory
have been removed; they are not evidence of the current Mac UI or this fork's
store availability.

For an explicitly requested visual check, use the native `Dusk-macOS` app on the
Mac and inspect light/dark appearance, window resizing, sidebar/search, details,
and player controls. Use a local demonstration library or avoid exposing account,
server or private media details in published captures.

Default agent verification is compile-only and does not launch the app. The
removed platform harness is documented only in `upstream/screenshots.md`.
