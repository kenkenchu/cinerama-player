# Cinerama Mac Design System

## Native Mac Controls and Neutral UI

This document governs the native macOS interface. The maintained tvOS target
has its own layout/input rules in `docs/tvos-ui.md`. The Mac interface should
feel at home
with a resizable window, keyboard and pointer input, standard menus,
and native fullscreen.

1. Use system `List`, `Form`, `Toggle`, `Picker`, `Slider`, menus, toolbars and
   navigation. Use materials and Liquid Glass as supplied by macOS.
2. Keep the palette neutral. Show selection and progress through system
   treatment, weight, opacity, or neutral fills. Semantic status colors retain
   their meaning: destructive/error red, rating yellow, normal system toggle.
3. No app-wide custom tint. Never tint active UI states with `Color.cineramaAccent`.
4. Sunset Coral is reserved for the logo/icon. The Mac app has no purchase page
   or alternate icon picker.
5. Let artwork lead. Keep controls clear and metadata readable in the fixed metallic-blue theme.

## Colors

Cinerama uses its own **Cinematic Metal Blue** theme, independent of macOS light,
dark or automatic appearance. `CineramaApp` sets Dark Aqua for native AppKit
windows/menus and `.preferredColorScheme(.dark)` for SwiftUI presentations.
`Shared/MacPlatform.swift` supplies fixed sRGB colors; do not add adaptive
light variants or restore the System/Light/Dark preference. Legacy saved
`appearanceMode` values are ignored.

| Token | Value | Purpose |
| --- | --- | --- |
| `cineramaBackground` | `#1D2D40` | Soft metallic-blue page/deck background |
| `cineramaSurface` | `#2D455F` | Raised metallic-blue cards, rows and bays |
| `cineramaTextPrimary` | `#F2F2F7` | Titles and emphasized labels |
| `cineramaTextSecondary` | `#B2C5D9` | Metadata and captions |
| `cineramaAccent` | `#FF6B4A` | Logo/icon only |

True black remains appropriate for video, letterboxing and cinematic backdrop
scrims. The catalog uses softer metallic-blue rather than an all-black appearance.

`cineramaPrimaryActionLabel` supplies a metallic-blue label over the light neutral
primary-action glass fill.
`cineramaPrimaryButtonTint` is translucent primary, not the brand color. The global
`AccentColor` asset is neutral: black in light appearance and charcoal
(`#4A4A4E`) in dark appearance. The accent can fill native selected controls,
so its dark variant must contrast
with the system's light selected text; do not use near-white there. The cockpit
console uses regular Liquid Glass with light neutral markings and a dark
color environment, without a brand-colored selection.
New color rules require updating this document.

## Typography and Geometry

Use system text styles through the semantic roles in `CineramaTypography.swift`:

```swift
.font(CineramaFont.sectionHeader(style: .title3.bold()))
.font(CineramaFont.metadata(style: .subheadline).monospacedDigit())
```

Roles preserve the provided native style. Respect inherited fonts; use fixed
sizes only where the artwork/layout genuinely requires them. Technical metadata
and time readouts can use monospaced digits.

- Posters: 16pt corner radius.
- Cards/sheets/player control surfaces: 28pt corner radius.
- Actions: native Liquid Glass controls (`.glassProminent` for primary actions,
  `.glass` for secondary actions); capsules where the shared hero
  helpers use them. Keep the default system control sizing.
- Borders: thin, neutral, low-opacity strokes.
- Layout: generous whitespace, consistent `CineramaPosterMetrics` spacing, and grids
  sized from the actual window content width. Do not use mobile device idioms.

## Screens and Interaction

Navigation uses a pinned bottom instrument console of native buttons, with
icons for all eight destinations, hover labels for names/shortcuts,
and accessibility labels. Flat translucent plates,
bright markings and a short steady white lamp identify the selected instrument
in the fixed appearance. Keep native
keyboard focus, the Navigate menu shortcuts and the full-width destination
NavigationStacks. Details remain backdrop-led without an
extra poster in the hero. Shared primary/secondary action helpers keep Play,
Resume, watched, and download controls consistent. A small quiet checkmark marks
watched items; partial progress is neutral over artwork.

Home uses `HomeCinematicHeroLayout.desktop`; hero sizing responds to the window.
Search, context menus, tooltips and accessibility labels must work with pointer
and keyboard input. Keep empty/error states secondary in color with one clear
native retry/action control. Loading uses a plain `ProgressView()`.

The player uses a dark native video surface. Its compact transport bar uses a
translucent neutral black fill with light controls so the background composites
consistently over native AVPlayer/VLC surfaces and letterboxing; honor Reduce
Transparency with an opaque fill. Other player panels use system materials. Preserve
space/arrow/Escape shortcuts and native fullscreen. Do not add TV focus plates,
remote gesture rules, touch overlays, or status-bar compensation.

## Verification

Compile with `scripts/build_macos.sh`. Visual changes also need system-appearance-switch and
window-resize inspection when the user authorizes a runtime check; a compiler
check does not prove layout or contrast. Default agent verification does not
launch the app. Historical styling is archived in `docs/upstream/STYLE.md` and
is not the source of truth for this fork.

## Futuristic Mac Presentation

The Mac interface keeps the neutral palette and native
navigation, with a more architectural presentation: a Cinerama cockpit instrument
console, ruled shelf headings, illuminated artwork
edges, and a framed cinematic hero information panel. Hero copy always uses a
dark environment over its black panel for contrast.
Reduce Transparency makes that panel opaque. Artwork hover adds brightness and
shadow without changing card geometry; Reduce Motion disables its animation.
The player retains its native compositing fill with a fine neutral edge.

## Cinerama Icon Identity

The West Coast icon uses a sculpted glass C/lens with sunset coral/amber and
Pacific teal/blue over midnight blue. These colors belong to the icon and
in-app brand artwork only; controls retain the neutral palette. Native Icon
Composer and TV layers supply platform-specific presentation. See
[icon design](docs/icon-design.md) for assets, regeneration and the final prompt.

## Home Screening Deck

Home evokes a spacecraft cinema through static architecture: sparse neutral star
points, a fine perspective grid, a Screening deck header and a rounded panoramic
viewport with illuminated corner brackets. Library shelves sit in separate
28pt metallic-blue bays. All decoration is noninteractive and hidden from
accessibility; no decorative animation loop or invented equipment status is used.
The header count and viewport index reflect the actual featured items.

The viewport stays dark; the surrounding deck uses the fixed metallic-blue palette.
The native toolbar remains visible above the full-width destination; the
instrument console reserves a bottom safe-area inset. The hero panel reserves
its internal padding when calculating width,
uses compact typography in smaller windows and preserves native Play/Resume and
pager interaction. Reduce Transparency makes library bays and the hero panel
opaque. The underlying Plex Home content is unchanged. TV uses its own adaptation
of this visual language; see `docs/tvos-ui.md` for its remote/focus rules.

## Cockpit Instrument Finish

Keep the approved strip layout, button dimensions and destination order. Give
the console regular Liquid Glass with chamfered
housing shoulders and fine rails. Reduce Transparency replaces its glass with
an opaque metallic-blue surface. Instruments use flat illuminated glyphs,
subtle 16pt selection plates and a steady white selection lamp. Names appear
only in explicit hover labels above the console and accessibility labels.
Keep hover labels outside the housing clip, noninteractive and accessibility-hidden.
Show the underline only for the selected instrument. Native ButtonStyle
pressed state supplies opacity feedback; pointer hover slightly brightens the
face. Avoid recessed wells, bevels, screws and mechanical key travel. Do not add blinking
lamps, decorative timers or invented system telemetry. All hardware decoration
must ignore hit testing and accessibility. Native focus and button activation
remain intact; these are cosmetic changes to the established navigation.

## Liquid Glass Placement

Use Apple's actual `glassEffect` and native glass button styles for the floating
instrument console and Home/detail actions. Keep glass on the control layer;
library bays use metallic-blue fills so artwork and metadata stay readable without
stacking glass effects. Native glass buttons retain system accessibility behavior;
the custom console explicitly uses an opaque surface under Reduce Transparency.
The player transport keeps its verified compositing fill over native video;
do not replace that fill with a backdrop-sampling effect.
