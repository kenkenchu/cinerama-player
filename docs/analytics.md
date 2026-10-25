# Analytics

Cinerama has no analytics endpoint or site ID configured. `AnalyticsClient` is
inactive in both Debug and Release and does not send usage events, generate an
install identifier, or advance the daily reporting marker. Settings states that
reporting is disabled rather than offering an ineffective consent toggle.

The inherited event vocabulary and no-queue/no-retry transport remain internal
implementation details. Any future reporting requires a separate product change
with a Cinerama-owned endpoint, explicit consent and matching privacy docs.
No traffic is sent to infrastructure owned by the original project. Existing
local analytics preferences do not enable reporting without that configuration.
