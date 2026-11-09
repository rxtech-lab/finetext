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

## Checks

```sh
bun run typecheck
bun run test
bun run build
bunx playwright install chromium
bun run test:e2e
```

Alternatively, use an installed Chrome browser with `PLAYWRIGHT_CHANNEL=chrome bun run test:e2e`.

Playwright launches a local dev server on port 3100. Tests cover locale negotiation, persistence, translated content, the language dialog, responsive layout, and both download/fallback behavior. Unit tests cover release selection and language matching.
