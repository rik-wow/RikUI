# RikUI website design

The public site centers on discovering, configuring, installing and sharing Setup Packs. Player-facing instructions live only in [docs/player](player/); [the documentation pipeline](documentation-pipeline.md) generates their pages and navigation. This file describes implementation decisions, not a second copy of those guides.

## Authentic Studio preview

The editor uses the exact public addon Lua configuration engine through Fengari. Validated data determines component ownership, module dependencies, fitting, accessibility precedence and exported packs. Submitted content is data; it is never loaded as Lua.

Game widgets derive from reviewed actual Lua captures in web/ui-renders. The browser places their bitmap pixels using recorded native roots and paint extents; it does not redraw widgets in HTML or SVG. Coordinated captured themes and supported states are explicit. Unsupported appearance remains stored and labeled as geometry-only. Canonical guide links cover window and situational features outside the preview.

Public component sprites are lossless crops of the reviewed paint bounds. Every build verifies the source hashes and exact decoded RGBA crop pixels; geometry retains original atlas coordinates. This removes transparent canvas space from image decoding without changing native output. Gallery and guide pictures retain their reviewed source images.

Studio uses the user's supplied 3840 × 2160 game screenshot, unchanged, for every setup, device and activity preview. Its original filename and exact reviewed image hash are recorded beside it. This historical screenshot includes its original character and overhead names; it makes no current-client or live-camera claim. Raw client files never enter public assets.

Background cover-cropping stays centered for each requested viewport and preserves aspect ratio. Screenshot, dim and plain modes are presentation-only. Actual addon fitting keeps the central character viewing corridor separate from scenery; the backdrop cannot establish live camera correctness.

## Responsive precise editing

Choose, Make it yours and Review & share form the main journey. Parts includes individual feature switches and component adoption; Appearance includes coordinated themes and personal readability; Layout includes named frames, labeled inactive movers, snap/align/reset and conflicts. UI scale is distinct from preview zoom.

Fullscreen uses the browser API on a user's click, listens for native exits, and restores focus and inert/scroll state. A declined or unsupported request uses a fixed expanded workspace. Controls remain available, may be hidden for a wider canvas, and scroll above the preview on narrow screens. Fit respects both available dimensions; 150–400% zoom exposes scrollable detail. No browser presentation choice changes a pack.

## Performance boundaries

One cached resolution tracks all actual semantic inputs, including direct property assignment, selective baseline, fitting, integration and accessibility. Attribution is excluded. Shared Lua still validates edits and performs every new solve. Pure Lua presentation predicates use bounded caches, preserving table prototypes, mutation isolation and invalid-data rejection.

Feature cards rebuild only when feature state, ownership, thumbnails or filters change. Settled scene pixels repaint only when appearance, geometry, scene visibility, viewport or backdrop changes. Selection, mover visibility, navigation and metadata retain unchanged pixels. Image requests are shared. Drag feedback uses a single animation-frame DOM outline and never reads or restores full canvas pixels; release commits through the shared fitter.

[The measured review](../web/studio-performance-review.json) records the same-machine before/after methodology and results. These measurements are development evidence, not a guarantee for all hardware. Browser tests assert retained nodes/pixels, real changes, keyboard/fullscreen recovery, crop behavior, failure fallback and portable export.

## Hosting and publication

Cloudflare Workers Static Assets serves only approved hashed asset paths, with immutable asset caching, no-store failures, same-origin CSP and release allowlists. HTML remains current. Installation links and release metadata use the actual published beta channel.

Run npm run build:docs before direct Wrangler commands. npm test, test:browser, check, dev and deploy build first. Lua capture checks authenticate unchanged reviewed addon images; website checks complement them. Source/fixture changes require only affected captures to be refreshed and exact reviewed hashes to be promoted. Builds never update baselines.

Browser review images and acquisition reports stay in ignored dist or external private scratch. Existing scene/realm saves, operator settings and unrelated development servers are preserved. Website-only changes deploy without manufacturing an addon release.
