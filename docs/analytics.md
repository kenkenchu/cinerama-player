# Analytics

The Mac fork retains anonymous app-open reporting to the **upstream Rybbit
instance at `stats.marvinvr.ch`**. This fork does not operate that endpoint or
getdusk.app. Reporting is disabled in Debug and can be disabled in Mac Settings.

It exists to answer one class of question — *does this feature actually work for
anyone?* — and nothing else.

The published privacy policy at getdusk.app/privacy describes this behaviour to
users. Anything in this document that changes needs the policy changed with it.

## Rules

These are not style preferences. Each one is load-bearing for a claim the
privacy policy makes:

- **Closed vocabulary.** Only `AnalyticsEventName` cases can be reported.
  `AnalyticsEvent` cannot be constructed from a free-form string, so the set of
  things Dusk *can* say is reviewable in one file.
- **Nothing Plex-derived, ever.** No titles, ratings keys, library names, server
  identifiers, search terms, playback positions, or download state. This is the
  rule most likely to be broken by accident when adding an event.
- **No retry, no queue, no disk buffer.** A failed send is dropped. A persistent
  outbox would gradually become a device history on disk.
- **Nothing is ever shown to the user.** No error state, no spinner, no toast,
  no log. A failure to report is invisible by design.
- **Debug builds report nothing**, so development never pollutes counters.
- **Opt-out is real.** With the Settings toggle off, nothing is sent at all, and
  the install identifier is deleted.

## Where things live

```text
Dusk/Sources/Analytics/
  AnalyticsEvent.swift    Event vocabulary, pageview/path mapping, property values
  AnalyticsClient.swift   Install identifier, daily gating, Rybbit payload, transport
```

`AnalyticsClient` is constructed in `DuskApp.init` and injected into the
environment. Views read it as an **optional** environment value
(`@Environment(AnalyticsClient.self) private var analytics: AnalyticsClient?`)
so a view rendered without it in scope silently skips reporting instead of
trapping. Keep it optional at every view call site.

## The Rybbit wire format

`POST https://stats.marvinvr.ch/api/track`, site `e76b9d7b1558`. Traps worth
knowing, all of them things Rybbit does differently from a normal JSON API:

- **`properties` is a JSON-encoded *string*, not an object.** Nesting is not
  supported, values may only be strings or numbers (no booleans — hence
  `AnalyticsValue` has no bool case), and the whole bag is capped at 2 KB.
- **Event names cap at 256 characters.**
- **`user_id` is supplied by us.** Left unset, Rybbit derives identity by
  hashing IP + User-Agent; passing our own random install identifier means it
  never has to. `app_version`, `platform` and `language` ride along as
  properties on every event.
- **`user_agent` is sent explicitly** (`Dusk/1.8.0 (macOS …)`) rather than
  letting URLSession's CFNetwork default through, which reads as neither a
  browser nor a known client.
- **An API key is optional.** Rybbit accepts events from any origin without one.
  `Configuration.apiKey` exists for the case where bot detection starts eating
  events — generate one in the Rybbit site's Settings → API Key and it is sent
  as `Authorization: Bearer`.

Rybbit uses the request IP transiently to resolve country/region and does not
store the raw address. That coarse geolocation is the one thing the app reports
without meaning to, and the privacy policy says so.

## Events

The only reportable Mac event is `app_opened`, sent as a pageview at `/app`.
It is daily-gated. It includes the existing app version, `platform=macos` and
language properties, with the same random install identifier and transport.
Purchase, prompt and icon events were removed with their unsupported UI.
No Plex-derived data is reported.

## Adding an event

1. Add a case to `AnalyticsEventName` with a doc comment explaining it, and give
   it a `path` if `/supporter` is wrong for it.
2. Report it with `analytics?.record(AnalyticsEvent(.case, [...]))`.
3. Check it against the rules above — particularly "nothing Plex-derived".
4. If it reports something the privacy policy does not already cover, update the
   policy and `product-and-scope.md` in the same change.

## Verification

Reporting is compiled out of Debug. A Mac compile only verifies the call sites;
it does not prove release reporting. Do not enable or send diagnostic analytics
as part of routine verification. Preserve opt-out and the no-Plex-data boundary.
