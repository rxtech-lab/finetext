# FineText website

A Next.js App Router landing page with Material UI, built and managed with Bun.

```sh
cd website
bun install --frozen-lockfile
bun run dev
```

Open http://localhost:3000. For production: `bun run build` then `bun run start`.
Deploy as a Next.js project with **website** as the root directory (for example on Vercel). No static export: GitHub release discovery needs a server. No API key is required for public releases. Optionally set `GITHUB_TOKEN` server-side to increase GitHub rate limits; never use a `NEXT_PUBLIC_` token.

## Languages

Localized routes: `/en`, `/zh-CN`, `/zh-TW`, `/zh-HK`. `/` redirects using the saved `finetext-locale` cookie, then the browser’s weighted `Accept-Language` header, then English. Explicit locale URLs always win. The language dialog stores an explicit choice for one year. Translation copy lives in `src/lib/messages.ts`.

## Downloads

The page fetches release information from `rxtech-lab/finetext` on every visit, with no application cache. An invalid or restricted optional `GITHUB_TOKEN` falls back to the public API. If the API fails or returns no downloadable release, the server reads GitHub’s latest release page and its lazy-loaded asset list to recover the direct DMG link. Page fallback shows the version without inventing an exact file size. It selects the newest stable, published release with an uploaded `FineText.dmg`, matching the macOS CI workflow. A release whose build is still pending is skipped in favor of the last downloadable release. The download button links directly to the GitHub asset; the app server never proxies the binary. Empty releases, timeouts, API errors, and rate limits render a localized GitHub fallback instead of a broken download. The current build requires Apple silicon and macOS 26+.

The preview is a localized HTML illustration, not an app screenshot. The icon is composed from the existing Icon Composer SVG layers.

## Tutorials

`/[locale]/tutorials` is the tutorial hub. Each guide has its own page, an accessible screenshot zoom dialog, and topic navigation through the sidebar. The language picker preserves the current guide. Tutorial copy lives in `src/lib/tutorials.ts`.

All tutorial images are local WebP assets in `public/tutorials/`. The Hugging Face browser, local-model list, provider editor, and Humanizer were captured from the installed Mac app. Flowcy and the rewrite example are clearly labeled interface illustrations based on branch source; they do not claim a successful authenticated request. Regenerate those illustrations from `website/` with `node scripts/tutorials/generate-assets.mjs`. The branch build could not expose a usable app window during capture. Replace the illustrated assets with native captures when that build is available, and update their captions. Screenshots use English app controls in every locale.

## Checks

```sh
bun run typecheck
bun run test
bun run build
bunx playwright install chromium
bun run test:e2e
```

Alternatively, use an installed Chrome browser with `PLAYWRIGHT_CHANNEL=chrome bun run test:e2e`.

Playwright launches a local dev server on port 3100. Set `PLAYWRIGHT_PORT=3000` to reuse an existing server on port 3000. Tutorial tests cover all 20 localized guide pages, WebP loading, mobile overflow, guide navigation, image dialog focus/Escape, and language switching within a guide. Tests cover locale negotiation, persistence, translated content, the language dialog, responsive layout, and both download/fallback behavior. Unit tests cover release selection and language matching.
