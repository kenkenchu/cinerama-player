# Cinerama Documentation

These are the active guides for the maintained **macOS and tvOS** clients. Read `AGENTS.md` first,
then `AGENTS.local.md` if present, the codebase map, and the relevant topic.
`STYLE.md` at the repository root is the visual source of truth.

| Guide | Responsibility |
| --- | --- |
| [Product and scope](product-and-scope.md) | Supported Mac/TV hardware, feature scope, privacy, licensing |
| [Codebase map](codebase-map.md) | Source ownership and extension points |
| [Automated testing](testing.md) | Mac/TV test targets, signed commands, coverage and limitations |
| [Development workflow](development-workflow.md) | Mac bootstrap, signing, verification, and independent development |
| [Icon design](icon-design.md) | Cinerama West Coast master, native packaging and generation prompt |
| [UI features](ui-features.md) | Instrument console, native player, reusable UI, and settings |
| [tvOS design](tvos-design.md) | TV target boundaries, Mac UI protection, initial HD scope and verification |
| [tvOS UI](tvos-ui.md) | Native TV shell, artwork, tracks, captions, playback lifecycle and focus |
| [tvOS Home](tvos-home.md) | Mac library Home feature mapping, shared data ownership, remote hero and actions |
| [tvOS device workflow](tvos-prototype.md) | Current scope, pairing, signing, installation and device checks |
| [Live TV pipeline plan](live-tv-pipeline-plan.md) | Resumable Mac MPEG-2 pipeline milestones, progress and verification; DVR and captions excluded |
| [Playback](playback.md) | Engines, source selection, remux, timing, and track selection |
| [Plex data](data-and-plex.md) | Account/session pool, API boundaries, models, merging |
| [Downloads and offline](downloads-and-offline.md) | Queue, local storage, offline state, and sync |
| [Seerr](seerr-integration.md) | Optional request integration and credential boundaries |
| [Privacy](privacy.md) | Cinerama network/data handling and disabled reporting |
| [Analytics](analytics.md) | Disabled reporting and retained internal event vocabulary |
| [Siri](siri.md) | Inherited App Intents and Mac validation limits |
| [Screenshots](screenshots.md) | Mac visual verification and capture limits |

[Historical upstream references](upstream/README.md) preserve old mobile/TV UI,
playback, StoreKit, App Store, and debugging notes. They describe removed code
and are not current feature promises, verification gates, or deployment steps.

Keep active docs concise and operational. Update the owning guide with a
meaningful flow, component, setting, setup, or verification change. Preserve
useful upstream history in the archive rather than mixing platform requirements
into the Mac guides.
