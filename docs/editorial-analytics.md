# Editorial analytics, phase 1

The authenticated `/metricas` dashboard adds article, byline and category analyses.
Click a row to drill down. Date, publication, exact author/category, text search,
sort and article filters persist in navigation and CSV/JSON/PDF exports.
Screen results are paginated in groups of 50; exports contain all filtered groups.

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
- Median views per accessed article complements volume; this is not a score of
  journalistic quality. Articles without visits are not included in the median.
- Engagement is summed recorded seconds from the legacy tracker, not validated
  active reading. General clicks are not labeled as CTR.
- Known metadata may be absent for older events; nothing is retroactively invented.

## Deployment

No migration, environment variable, new application dependency or tracker change
is required. Rebuild and recreate the web service using the existing production
Compose configuration. Do not restart or modify the ERP.

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
