# Seerr Integration

Seerr is an optional discovery-and-request companion to Plex. It never provides
playback, watch state, downloads, or library ownership; Plex remains the source
of truth for all playable media.

## Ownership

- `SeerrService/` owns URL validation, Plex-token sign-in, cookie sessions,
  endpoint calls, request status mapping, and Seerr image-proxy URLs.
- `Models/SeerrModels.swift` mirrors only the Seerr response fields Cinerama uses.
- `Features/Settings/SeerrSettings*` owns opt-in setup.
- `Features/Search/SearchMediaResult.swift` is the presentation union used to
  place Plex and Seerr cards in the same search groups.
- `Features/Seerr/` owns request-only movie, show, and season screens.
- `ShowDetailViewModel` may add missing Seerr seasons to an online Plex show.

Do not introduce a generic media-provider abstraction. Seerr is not a playback
backend and must stay a focused optional integration.

## Connection Flow

The user enters one Seerr base URL in Settings. An address without a scheme is
probed over HTTPS first and HTTP second; an explicit `https://` or `http://`
address is used exactly as entered. Cinerama resolves the public endpoint before
asking the user to confirm that it may send the active Plex credential to the
resolved host. Cinerama then:

1. fetches `/api/v1/settings/public`;
2. requires an initialized Plex-backed Seerr with media-server login enabled;
3. posts the active Plex Home account token to `/api/v1/auth/plex`;
4. stores the returned session cookies in Keychain;
5. verifies/restores sessions through `/api/v1/auth/me`.

The native Mac setup uses the Seerr settings form and active Plex identity;
there is no separate Seerr password/API-key mode. HTTP is allowed for local
servers, but probes never send credentials and confirmation warns when the
resolved host uses unencrypted transport. Preserve the explicit host consent.

## Search And Detail Flow

Search starts Plex and Seerr work together but publishes Plex results as soon as
they arrive. A Seerr timeout or error is silent and cannot replace a successful
Plex result set with an error. Supported Seerr movie/show hits are appended to
the native Movies/Shows groups and deduplicated by TMDB GUID, with normalized
title/type/year only as a fallback.

External cards use the standard poster primitive with a small request-state
badge. Their routes open dedicated request-only details: no play, download,
watched, or context-menu actions are present. Status is resolved from Seerr's
media, request, and per-season records and is refreshed after a request and when
returning to the foreground.
Search suppresses media Seerr marks fully available or blocklisted; partial,
pending, processing, and otherwise requestable records remain visible.

TV requests respect Seerr's partial-request setting. A season route requests
only that season when partial requests are enabled; otherwise it requests all
missing seasons. Whole-show detail always offers all missing seasons.

## Missing Seasons On Plex Shows

Online Plex show details request GUIDs. Missing-season enrichment runs only when:

- Seerr is connected for the current Plex profile and its bound server;
- live Plex metadata is in use, not cached offline metadata; and
- the Plex show has an exact `tmdb://` GUID.

Cinerama fetches that exact Seerr TV record, removes season numbers already present
in Plex, and sorts the remaining request-only seasons into the same grid.
Never use fuzzy title matching here: a false match could submit a request for the
wrong series. Seerr failures are ignored so Plex detail loading remains intact.

## Invariants And Traps

- Never send the Plex token before the user confirms the exact normalized host.
- Redirects are accepted only within the same origin to prevent credential or
  session-cookie leakage.
- Keep session cookies in Keychain and the non-secret base URL/server binding in
  UserDefaults.
- A 401 refreshes the session once through Plex sign-in; a real 403 remains a
  permission/quota error and must not be mistaken for an expired session.
- Never pass Seerr items into playback, download, offline-sync, or Plex
  watch-state code.
- Never let Seerr availability suppress a Plex item; Plex wins deduplication.
- Use Seerr's `/imageproxy/tmdb/...` endpoint rather than direct third-party image
  hosts.
- Preserve reverse-proxy subpaths when building endpoints.

## Verification

Run the signed Mac compile after changes. Explicitly authorized runtime checks should
cover a Plex-enabled Seerr, an unauthorized Plex Home member, reconnect after a
session expires, pending/approved/available states, partial TV requests, an
offline Plex show, and a show with an exact TMDB GUID plus missing seasons.
