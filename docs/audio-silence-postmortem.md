# Historical Mobile VLC Audio Postmortem

The original postmortem is preserved in `upstream/audio-silence-postmortem.md`.
It describes removed mobile audio-session/rendering code. The native Mac app
uses desktop VLCKit and Core Audio; those workarounds are not current runtime
requirements or evidence of a desktop bug.

For current engine ownership, routing and verification, read `playback.md`.
