# Editorial analytics, phase 1

The authenticated `/metricas` dashboard adds article, byline and category analyses.
Click a row to drill down. Date, publication, exact author/category, text search,
sort and article filters persist in navigation and CSV/JSON/PDF exports.
Screen results are paginated in groups of 50; CSV/JSON contain all filtered groups.
The Correio PDF combines the top 10 individual columnists and top 10 most-viewed
articles, independent of the open tab and selected sort. Dates and explicit content
filters apply to both rankings and the overview. Other publications retain their
single-dimension top-10 PDF.

## Measurement contract

- Only `page_view` events with `content_key` identify accessed articles. This is
  not the number of articles published in the CMS. Missing IDs are excluded.
- Dates are complete UTC days (end date inclusive in UI, exclusive internally).
  Default: seven days ending yesterday. Comparisons use an adjacent period of
  equal duration, with the same filters. Zero baseline yields no percentage.
- The existing visitor hash rotates each day. Labels explicitly describe daily
  visitor identifiers, not unique people across the entire reporting period.
- Authors are reported using the received byline. Collective and multiple-author
  bylines remain a single group until a stable author-ID schema is integrated.
- The separate `columnists` dimension uses active individual profiles from the
  official Correio directory. It matches only complete individual bylines after
  case/accent/whitespace normalization and removal of a leading "Por". It does not
  attribute a column's other reporters, blank bylines or shared signatures to its
  owner. Legacy events are not rewritten. Filtering by `columnist` applies that
  exact identity consistently to article drill-downs, summaries, comparisons and
  all exports. An accessed article contributes once to the identity's article
  count regardless of the number of recorded visits.
- Median views per accessed article complements volume; this is not a score of
  journalistic quality. Articles without visits are not included in the median.
- Engagement is summed recorded seconds from the legacy tracker, not validated
  active reading. General clicks are not labeled as CTR.
- Known metadata may be absent for older events; nothing is retroactively invented.

## Deployment

The public dashboard adds migration `20261028120000_create_analytics_shares`.
Rebuild and recreate the web service using the existing production Compose
configuration; its entrypoint runs migrations. The PDF release adds the Prawn gem
and DejaVu fonts in the Docker image. No new migration, environment variable or
tracker change is required for PDF export. Do not modify the ERP.

The columnist release adds migration `20261028150000_create_analytics_author_profiles`.
The existing VPS worker refreshes the official profile catalog at most daily,
outside request handling, under an advisory lock and a time budget. Run
`Correio::SyncColumnists.call(force: true, max_duration: 120)` in a production Rails
runner after deployment for initial population. Only official profile-avatar
elements supply portraits; article images and arbitrary OG images are not used.
Failures preserve existing portraits and known identities. Collective columns
are excluded from the individual ranking. The tracker no longer selects the
first unrelated JSON-LD author photo when the received byline has no match.

## Shared Reporter Dashboard

Only the active Correio da Manha source can currently be shared. On `/metricas`,
select that publication as an administrator and open "Compartilhar com a redacao".
Create a link, then distribute its full URL to reporters. It works without login,
including on mobile. A replacement invalidates the previous link immediately;
disabling sharing invalidates all links for that share. Links are bearer access:
anyone who receives one can read the publication's aggregated audience.

The shared dashboard is phone-first: 7/30/90-day shortcuts and a single search are
always visible; exact filters and custom UTC dates expand on demand. Mobile tabs
stick to the viewport top. A safe-area-aware bottom bar links to the summary,
ranking and the same filtered PDF export. Rankings become two-column metric lists
with readable story/author images; the desktop table remains intact. Measurement
definitions and publication isolation are unchanged.
`script/check_public_analytics_layout.js` provides VPS-only Chromium checks at
320, 390, 430, 768 and 1280px, including expanded filters, ranking navigation,
author/category layouts, empty results and PDF filter persistence. Run it in a
disposable official Playwright container with the matching Playwright npm version,
`HUB_PUBLIC_ANALYTICS_URL` set to the share URL, and a writable `/review` directory
for screenshots. This is a verification dependency, not part of the Ruby app.

The `/audiencia/:token` dashboard shares the existing report calculations, images,
bylines, category/article drill-downs, comparison, search and pagination. Requests
are scoped to the link's site, ignoring `site_id` overrides, with at most 90 full
UTC days per query. It exposes no visitor/session identifiers, click target URLs,
team activity, raw CSV/JSON exports, CMS configuration or editing actions. Its PDF
button downloads a combined branded report: an overview of all filtered articles,
daily comparison chart, top individual columnists with embedded portraits, then
the most-viewed stories with embedded thumbnails and clickable official story
links. It shows views, previous-period views and change. It lists eligible totals;
the full ranking remains available in the dashboard. Long titles are abbreviated
at 180 characters. It preserves the same share scope and revocation checks. PDF generation
uses Prawn, embedded DejaVu fonts and libvips thumbnails provided by the Docker
image. Image requests accept only official Correio HTTPS hosts, validate and pin
public DNS addresses on every redirect, stream at most 3MB per image, and share a
15-second fetch budget. Raster-only thumbnails are compressed to JPEG and cached
in bounded process memory for an hour. Missing or invalid images use initials/CM;
they do not prevent export. Story links drop query strings and fragments, and the
PDF never embeds the bearer link. No new migration is required. Internal metrics and
share creation/replacement/revocation still require Hub authentication; share
management requires an administrator and CSRF protection. Responses are no-store,
no-referrer, noindex and cannot be framed. Treat URLs as confidential; proxy access
logs can still contain paths even though Rails filters the token parameter.

## Verification

Regression tests are in `test/services/analytics/editorial_report_test.rb`.
Run with the app's Ruby/Bundler and a **dedicated test PostgreSQL database**:

```bash
RAILS_ENV=test bundle exec ruby bin/rails db:prepare
RAILS_ENV=test bundle exec ruby test/services/analytics/editorial_report_test.rb
```

Ensure DATABASE_URL, if set, points at the test database before running either
command. Never run db:prepare against production for this test setup.

Development checks performed: Ruby 3.3 syntax, ERB structure, report-generated SQL
executed against PostgreSQL via PGlite with a test-only relation adapter, fixtures
for boundaries, periods, medians, missing metadata, search escaping, site isolation,
pagination and JSON, and PDF generation/rendering. These checks do not replace a
full Rails/ActiveRecord integration run on the deployed application.

After deployment: authenticate, open `/metricas`, switch all three tabs, filter a
known author, drill into an article, compare the chart/table and export all formats.
Verify `hub.cm.com.br/up` and confirm the ERP remains reachable separately.

Next phase: active-reading instrumentation, impression-based CTR, real-time
sessions, stable author IDs/coauthors and the CMS publication catalog.
