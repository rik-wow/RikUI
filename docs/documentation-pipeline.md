# Public documentation pipeline

Player-facing guides live in `docs/player/*.md`. Each public route has exactly one Markdown source; `web/docs-catalogue.mjs` owns navigation groups, module mappings and visual-coverage metadata, not prose. The other files under `docs/` are developer contracts, research and verification records.

`web/docs-source.mjs` loads the exact catalogue inventory and resolves only the approved `{{release.*}}` tokens from `web/releases.mjs`. Unknown tokens, missing or extra guide files fail the build. Canonical guides use LF line endings so byte hashes are consistent across checkouts. `web/build-docs.mjs` generates public HTML, route mapping and `web/docs-inventory.json`; do not edit generated HTML. Each guide records raw source, resolved Markdown, release-data and HTML hashes, verified by `web/docs-source.test.mjs`.

Run `npm --prefix web test` to build and verify the public guides, then `npm --prefix web run test:browser` for route, keyboard, responsive navigation and no-JavaScript checks. Documentation changes trigger the website workflow. Nonvisual prose and navigation changes reuse the authentic reviewed Lua captures; the renderer gate still checks their recorded dependencies. Addon or fixture changes refresh only affected captures and require exact-hash visual review.

The site uses its existing Marked/static Cloudflare Worker pipeline. Fumadocs supports static export (reviewed https://www.fumadocs.dev/docs/deploying, 2026-10-02), but adopting its React framework is not necessary for a canonical Markdown source or accessible navigation. Any later framework migration should preserve these source, release and authentic-capture contracts.
