# Design QA - Radar Editorial

## Targets

- Desktop reference: `exec-244c5576-3cd9-4189-ac99-795e5c7f0397.png`
- Mobile reference: `exec-4882faee-3c22-4508-81d8-be8666bd3f5c.png`
- Tested viewports: 1440x1024, 768x1024, and 390x844

## Comparison

- Layout: desktop preserves the dark navigation rail, three-stage editorial board, and contextual detail panel. Mobile becomes a single-stage list with fixed bottom navigation and a floating primary action.
- Typography: editorial headlines use Georgia while navigation, metadata, controls, and statuses use the system sans-serif stack. Text wraps without horizontal page overflow.
- Color and surfaces: Correio red is reserved for active states and primary actions; semantic amber and green states remain distinguishable. Cards use restrained borders and square editorial surfaces.
- Icons: controls use one consistent Lucide icon set through the `ui_icon` helper. No handwritten SVG substitutes are present.
- Responsiveness: tablet switches to the mobile workflow at 900px. Measured document width matches the viewport at all tested sizes, and mobile action targets are 50px high.
- States and interaction: stage tabs switch the visible list, selected-story actions remain reachable, the publication menu and user menu keep their existing behavior, and the empty-state path remains implemented.
- Accessibility: page landmarks, labels, tab roles, selected state, visible focus behavior, semantic links/buttons, and practical mobile tap targets are present. Decorative icons are hidden from assistive technology.

## Resolved Findings

- P1: Three workflow columns were cramped at 768px. Fixed by moving the app-layout breakpoint to 900px.
- P2: Static CSS could remain cached across deployments. Fixed with a versioned stylesheet URL.
- P2: Mobile duplicated the Radar title and pushed stories down. Fixed by using the app header as the mobile page identity.
- P2: Local production-mode login could not retain a session over HTTP. Fixed by tying the secure cookie and SSL assumptions to `FORCE_SSL`, which remains enabled by default.
- P1: The expanded publication list inherited a fixed legacy height and overlapped the following navigation groups. Fixed with an auto-height sidebar group that keeps the alphabetical list in document flow.
- P1: Original reporting was restricted to Turismo Hoje and hidden from the main workflow. Generalized the editor to every active publication, with destination-aware categories and responsive access from Radar and Production.

## Verification

- Docker production image builds successfully.
- Rails migrations and seeds complete against PostgreSQL 18.
- `/up` returns HTTP 200.
- Authenticated dashboard renders successfully in the browser.
- The original-article draft flow saves against every active publication and was verified inside a rolled-back database transaction.
- Publication navigation and the writing editor were visually verified on desktop and mobile.
- Browser console reports no warnings or errors during the final mobile pass.
- `git diff --check` passes.

## Audience Analytics

- Replaced the long spreadsheet-first layout with a decision-focused dashboard: compact period controls, four summary indicators, current-versus-previous daily trend, device distribution, clicked destinations, and a ranked content view.
- Added quick 7/30/90-day periods, advanced filters, configurable 25/50/100 row pagination, and a consolidated export menu while preserving CSV, JSON, and PDF outputs.
- Desktop was verified at 1280x720 with the complete 2153px page captured. The redesigned content stays inside the viewport and keeps the sidebar and top bar intact.
- Mobile was verified at 390x844. Filters stack into touch-friendly controls, indicators use a two-column grid, supporting panels become a single reading flow, and ranking rows become metric cards instead of a horizontally scrolling table.
- The export control, advanced-filter disclosure, dimension navigation, comparison series, device totals, and ranking metadata were checked with representative local analytics events.
- Rails runtime checks confirm that current and previous daily series both contain seven days, their sums match their summaries, and device totals match page views.
- Correio da Manhã is modeled as a source-only product: it is excluded from destination selectors and publication navigation, and the publishing services reject it even when called directly.
- Source-only destination tests pass with 7 assertions; the analytics report suite passes with 34 assertions. Browser console remains free of warnings and errors after the final responsive pass.
- Article ranking now receives editorial images from `data-image`, `cm:image`, or the page's `og:image`, with a stable 4:3 fallback when no image is available. Twelve populated rows were verified on desktop and mobile.
- Recent team activity is integrated below the ranking as a three-column operational stream on desktop and a single-column timeline on mobile. Six populated activities were verified with user and relative time metadata.
- The extended analytics suite passes with 35 assertions, including preservation of the image URL in grouped report rows. The final media pass had no browser console issues.
- The Journalist dimension now pairs each normalized signature with a circular profile photo collected from `data-author-image`, `cm:author-image`, or matching JSON-LD author data. Initials provide the fallback.
- Four populated columnist profiles were verified at 1280px and 390px. Every image completed at its expected 160px source size, names and metrics remained readable, and no browser console issues were reported.
- Analytics tests now pass with 36 assertions, including grouped preservation of both article and author image URLs.

final result: passed
