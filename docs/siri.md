# Mac App Intents Status

The fork retains `Siri/` title matching, catalog types, and App Intents. `DuskApp`
registers `SiriPlaybackService`, and intents can request playback through the
shared coordinator using server-scoped identities.

Mac Siri/Shortcuts execution has not been validated. The current sidebar shell
does not run the original automatic title-catalog refresh task, so compilation
alone is not evidence that suggested-title shortcuts are populated or speech
routing works. Do not advertise this as a supported Mac feature yet.

When changing it, preserve Plex Home/session readiness, ambiguity handling,
server binding, and the foreground playback route. Use a Mac build as the agent
gate; actual Siri/Shortcuts checks require an explicitly authorized runtime
session. Original platform-specific routes are in `upstream/siri.md`.
