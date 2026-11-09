import { repository, type Release } from "./release-data";

// GitHub lazy-loads the download links from this fragment on the release page.
export function releaseAssetsUrl(html: string): string | null {
  const sources = html.matchAll(/<include-fragment\b[^>]*\bsrc=["']([^"']+)["']/gi);
  for (const [, source] of sources) {
    const url = new URL(source, repository);
    if (url.origin === "https://github.com" &&
      /^\/rxtech-lab\/finetext\/releases\/expanded_assets\/[^/]+$/.test(url.pathname) &&
      !url.search && !url.hash) return url.href;
  }
  return null;
}

export function releaseFromAssets(assetsUrl: string, html: string): Release | null {
  const tag = new URL(assetsUrl).pathname.split("/").at(-1)!;
  const path = `/rxtech-lab/finetext/releases/download/${tag}/FineText.dmg`;
  const links = html.matchAll(/<a\b[^>]*\bhref=["']([^"']+)["']/gi);
  for (const [, href] of links) {
    const url = new URL(href, repository);
    if (url.origin === "https://github.com" && url.pathname === path && !url.search && !url.hash) {
      return {
        version: decodeURIComponent(tag), url: `${repository}/releases/tag/${tag}`,
        downloadUrl: url.href,
        // The page only exposes a rounded size; don't present it as exact metadata.
        size: null, publishedAt: null,
      };
    }
  }
  return null;
}

export async function fetchReleasePage(): Promise<Release | null> {
  const request = (url: string) => fetch(url, {
    headers: { Accept: "text/html" }, cache: "no-store", signal: AbortSignal.timeout(8000),
  });
  try {
    const page = await request(`${repository}/releases/latest`);
    if (!page.ok) return null;
    const assetsUrl = releaseAssetsUrl(await page.text());
    if (!assetsUrl) return null;
    const assets = await request(assetsUrl);
    return assets.ok ? releaseFromAssets(assetsUrl, await assets.text()) : null;
  } catch {
    console.warn(`GitHub release page lookup could not complete: ${repository}`);
    return null;
  }
}
