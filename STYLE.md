# Dusk Mac Design System

## Native Mac Controls and Neutral UI

This document governs the native macOS interface. The maintained tvOS target
has its own layout/input rules in `docs/tvos-ui.md`. The Mac interface should
feel at home
with a sidebar, resizable window, keyboard and pointer input, standard menus,
and native fullscreen.

1. Use system `List`, `Form`, `Toggle`, `Picker`, `Slider`, menus, toolbars and
   navigation. Use materials and Liquid Glass as supplied by macOS.
2. Keep the palette neutral. Show selection and progress through system
   treatment, weight, opacity, or neutral fills. Semantic status colors retain
   their meaning: destructive/error red, rating yellow, normal system toggle.
3. No app-wide custom tint. Never tint active UI states with `Color.duskAccent`.
4. Sunset Coral is reserved for the logo/icon. The Mac app has no purchase page
   or alternate icon picker.
5. Let artwork lead. Keep controls clear and metadata readable in either theme.

## Colors

Dynamic `NSColor` providers in `Dusk/Sources/Shared/MacPlatform.swift` back the
SwiftUI colors. Keep these light/dark values consistent:

| Token | Light | Dark | Purpose |
| --- | --- | --- | --- |
| `duskBackground` | `#F5F7FA` | `#090A0F` | Window/page background |
| `duskSurface` | `#FFFFFF` | `#161824` | Cards, rows, elevated content |
| `duskTextPrimary` | `#1C1C1E` | `#F2F2F7` | Titles and emphasized labels |
| `duskTextSecondary` | `#636366` | `#8E95A8` | Metadata, captions, placeholders |
| `duskAccent` | `#FF6B4A` | `#FF6B4A` | Logo/icon only |

`duskPrimaryActionLabel` supplies the contrasting primary-action label.
`duskPrimaryButtonTint` is translucent primary, not the brand color. The global
`AccentColor` asset is neutral. New color rules require updating this document.

## Typography and Geometry

Use system text styles through the semantic roles in `DuskTypography.swift`:

```swift
.font(DuskFont.sectionHeader(style: .title3.bold()))
.font(DuskFont.metadata(style: .subheadline).monospacedDigit())
```

Roles preserve the provided native style. Respect inherited fonts; use fixed
sizes only where the artwork/layout genuinely requires them. Technical metadata
and time readouts can use monospaced digits.

- Posters: 16pt corner radius.
- Cards/sheets/player control surfaces: 28pt corner radius.
- Actions: native glass or bordered controls; capsules where the shared hero
  helpers use them. Keep the default system control sizing.
- Borders: thin, neutral, low-opacity strokes.
- Layout: generous whitespace, consistent `DuskPosterMetrics` spacing, and grids
  sized from the actual window content width. Do not use mobile device idioms.

## Screens and Interaction

The sidebar uses `NavigationSplitView`. Details remain backdrop-led without an
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

Compile with `scripts/build_macos.sh`. Visual changes also need light/dark and
window-resize inspection when the user authorizes a runtime check; a compiler
check does not prove layout or contrast. Default agent verification does not
launch the app. Historical styling is archived in `docs/upstream/STYLE.md` and
is not the source of truth for this fork.

## Futuristic Mac Presentation

The Mac interface keeps the neutral palette and native
navigation, with a more architectural presentation: a typographic Dusk sidebar
masthead, Discover/Workspace groups, ruled shelf headings, illuminated artwork
edges, and a framed cinematic hero information panel. Hero copy always uses a
dark environment over its black panel for contrast in either app appearance.
Reduce Transparency makes that panel opaque. Artwork hover adds brightness and
shadow without changing card geometry; Reduce Motion disables its animation.
The player retains its native compositing fill with a fine neutral edge.

## Cinerama Icon Identity

The West Coast icon uses a sculpted glass C/lens with sunset coral/amber and
Pacific teal/blue over midnight blue. These colors belong to the icon and
in-app brand artwork only; controls retain the neutral palette. Native Icon
Composer and TV layers supply platform-specific presentation. See
[icon design](docs/icon-design.md) for assets, regeneration and the final prompt.
