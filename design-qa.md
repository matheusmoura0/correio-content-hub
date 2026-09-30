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

final result: passed
