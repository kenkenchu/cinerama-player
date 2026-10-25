# Cinerama Icon

The West Coast mark combines a sculpted C/cinema-lens silhouette with warm
California sunset coral/amber above Pacific teal/blue. The surrounding UI keeps
its neutral palette. The mark has no wordmark or baked tile/mask.

## Sources and Packaging

- Master: `Dusk/Resources/DuskIcon.icon/Assets/cinerama-west-coast.png`.
- Mac: `DuskIcon.icon/icon.json` places the transparent master at 0.82 scale
  over a midnight-blue automatic gradient. Native Icon Composer supplies the
  icon shape, lighting and appearance handling. The old darken blend override is
  removed so sunset highlights remain visible.
- In-app branding: `LaunchLogo.imageset/cinerama-west-coast.png` is an exact
  copy of the master, used by sign-in and the Mac sidebar masthead.
- TV: `swift scripts/generate_tvos_icon.swift` centers the visible master
  into transparent Front layers and generates opaque midnight-blue Back layers
  at 400 × 240, 800 × 480 and 1280 × 768. Native tvOS supplies masking/parallax.
  Commit the generated layers; `.build/tvos-icon-preview.png` is review-only.

The master was generated with the built-in image generation tool. Packaging
uses the existing AppKit renderer; it does not redraw or recolor the master.
Keep the launch copy and TV layers synchronized when replacing the master.
Run both signed build scripts after asset changes. Inspect the packaged icon
and reduced-size previews; compilation does not validate Dock/Home Screen
registration or device parallax. App launches and installation remain separate
user-authorized steps.

## Final Generation Prompt

```text
Use case: logo-brand
Asset type: final production foreground app icon for Cinerama, a futuristic cinematic Mac and Apple TV app with a WEST COAST CALIFORNIA vibe.
Primary request: One original sculptural C emblem that combines a cinema lens and the sweep of a Pacific coastal wave. A substantial smooth open circular ribbon forms a clearly readable capital C, with its gap at the right. The ribbon is luminous polished optical glass, its upper arc glowing warm California sunset coral, peach and amber, flowing into deep Pacific teal and ocean blue along the lower arc. A hint of soft lilac reflection links warm and cool colors. Warm sunset light, coastal air, luxurious California modernism meets futuristic cinema. The circular negative space stays transparent and clean. Simple bold silhouette, beautiful dimensional bevels and restrained internal reflections, immediately legible at 32 pixels. Front-facing nearly orthographic, balanced and centered within a square canvas, artwork uses 76 percent of canvas width and height. Use a genuinely transparent background: no enclosing tile or rounded square, no environment or scenery. No words, no tiny typography, no palm trees, no sun disk, no extra objects, no film-strip perforations, no play triangle, no stars or particles, no excessive neon bloom, no baked outer shadow. This must be a sophisticated app symbol, not a beach postcard. No resemblance to the historical Cinerama wordmark. High resolution PNG with true alpha transparency.
```
