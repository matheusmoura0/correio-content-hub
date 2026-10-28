# Reader metadata v2

The Hub tag at `/cm-analytics.js` collects only on pages where it is installed.
Correio article pages already reference that URL; cached pages need to reload.
The home page is not currently tagged, so journeys and placements on untagged
pages are not observable. No historical reader enrichment is invented or backfilled.

## Captured fields

- `occurred_at`: authoritative server receipt time (UTC), unchanged.
- `client_occurred_at`: device UTC timestamp, optional, accepted within seven
  days of server time. `metadata.clock_skew_ms` records the difference; device
  clocks are not trusted for reporting boundaries.
- `page_elapsed_ms`: monotonic elapsed time since navigation, capped at 24 hours.
  Back/forward-cache restorations begin a new page-view segment.
- `event_uuid`: random retry-deduplication ID, unique within a publication.
  `page_view_uuid` groups one page view, scrolls, clicks and reading checkpoints.
- Browser-reported IANA `time_zone`, offset minutes and language (two letters).
  `metadata.local_hour` is derived from SERVER time in the reported zone, not the
  device clock. Offset-only fallback is supported. These are client assertions,
  not proof of physical location.
- Approximate country (`country_code`), region, city and provider marker. These
  come from the public request IP and a local DB-IP City Lite database. Never
  store IPs or latitude/longitude in event enrichment. Unknown geography is null;
  arbitrary CF headers and client-supplied geography are not trusted.
- Browser/OS FAMILY from the Browser library, not full raw user agents, device
  model, installed fonts or fingerprinting signals.
- First-touch source/channel, allowlisted `utm_source`, `utm_medium`, `utm_campaign`;
  no search terms or arbitrary campaign/query parameters. Missing referrers mean
  `direct_or_unknown`, not guaranteed direct access. Existing referrer is now only
  an origin, not a full referring URL.
- Entry and previous TRACKED paths in a per-tab session. Session storage expires
  after 30 minutes without recorded activity. Storage failures use a per-page
  in-memory session. No persistent cross-site visitor identifier is introduced.
- Click placement and internal/external/action/share classification. Semantic
  header/footer/nav/article detection works automatically. More exact positions
  can be marked on the host site using `data-analytics-placement` with one of
  `header`, `footer`, `navigation`, `article_body`, `related`, `homepage_lead`,
  `homepage_grid`, `share`, `other`; optional `data-analytics-label` labels a control.
- Maximum observed scroll depth, plus at most four threshold events per page
  (25/50/75/100). Scrolling is not evidence of completed reading.
- Estimated active seconds: visible, focused tab with activity in the last 30s.
  Five-second samples are capped to prevent background/timer suspension inflation.
  Engagement events report DELTAS every 15s, on hiding and on exit; metadata's
  `active_seconds` is cumulative per page view. SUM engagement `value`, but do NOT
  sum cumulative `active_seconds` across clicks/scrolls. Use MAX per page_view_uuid.
  Old and new engagement measurements differ; comparisons spanning the release
  are mixed methodology. Delivery is best-effort, not an audit log of every click.

Paths, destination/image URLs and referrers drop query strings and fragments;
credentialed URLs, mailto/tel destinations, email-containing/sensitive account
paths and long numeric identifiers are excluded. Control labels redact email and
phone patterns. This is minimization, not a guarantee that all user-generated
text is anonymous. New request parameters are filtered from Rails parameter logs;
reverse-proxy/security logs require separate access and retention controls.

## Privacy and retention

Honor GPC and DNT on the client and server. The client can be disabled by setting
`window.cmAnalyticsConsent = false` before the tag. For consent-required use, add
`data-consent="required"` and dispatch the host consent manager's decision:

```javascript
document.dispatchEvent(new CustomEvent("cm:analytics-consent", {
  detail: { granted: true } // false immediately stops collection and clears session storage
}));
```

The default continues the existing analytics setup, now honoring opt-outs. A
browser's ability to expose a field is not a legal basis to collect it. The
publisher must review lawful basis, disclosures and consent-manager integration
under LGPD. Do not request GPS permission for audience reporting.

The worker removes NEW enrichment and its client timestamps/UUIDs after 90 days,
preserving historical event counts, existing hashes and legacy rows. This is not
a new retention policy for the legacy analytics or operational logs; those still
need a publisher decision. Public dashboards/PDFs do not expose raw events or
this reader-level metadata. Future geographic reports must aggregate and
suppress small groups, and include DB-IP attribution.

## Geo database and deployment

Migration: `20261028170000_add_reader_metadata_to_analytics_events`. Rebuild both
images, populate GeoIP using the new worker image, recreate web (entrypoint runs
migration), then recreate the worker. A dedicated Docker volume is writable by
the worker and read-only to web. Missing/broken GeoIP must never reject events.

`Analytics::UpdateGeoDatabase.call` downloads the current monthly database
directly from DB-IP, verifies that it opens, then replaces it atomically. The
worker checks for updates each cycle, with a six-hour retry cooldown and a
nonblocking filesystem lock. Downloads have size/time limits. Existing data is
preserved on failure. Lookups are local; no visitor IP is sent to DB-IP.

Source/attribution: [IP Geolocation by DB-IP](https://db-ip.com), City Lite,
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Lite data is approximate
and less accurate than the paid product, especially for mobile/VPN networks.

Verification runs only on the VPS: isolated PostgreSQL integration/service tests,
plus `script/check_analytics_tracker.js` in the disposable Playwright container
with the tracker mounted at `/tracker.js`. The browser test intercepts every
request and never inserts synthetic traffic into production.
