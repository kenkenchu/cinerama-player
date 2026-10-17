# Historical Upstream References

This archive preserves technical context inherited from the original Dusk
project before this fork became macOS-only. Mobile/TV code, deployment tooling,
and purchase/icon flows described here have been removed from this fork.

These files are historical evidence, not active agent instructions or supported
feature lists. Use the active guides in [the documentation index](../README.md)
for current ownership, build commands, verification, and publishing decisions.

- [Playback](playback.md): detailed inherited algorithms and platform history.
- [UI](ui-features.md) and [style](STYLE.md): old platform shells and layouts.
- [Audio postmortem](audio-silence-postmortem.md): mobile VLC audio-session bugs;
  do not transplant their fixes into the desktop Core Audio renderer by default.
- [Supporter](supporter.md): removed purchasing, prompt, and icon flows.
- [Siri](siri.md): original mobile integration and validation notes.
- [Screenshots](screenshots.md), [release 1.7](release-1.7.md), and
  [website reviews](website-reviews.md): original App Store/website material.

The fork does not publish the original App Store listing or upstream website.
The old `website/` and mobile/TV `screenshots/` assets have been removed; paths
to them in these archived guides describe the historical upstream tree.
Source in the original repository and Git history remain the references for
future upstream merges.
