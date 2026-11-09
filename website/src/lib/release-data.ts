export const repository = "https://github.com/rxtech-lab/finetext";
export interface Release {
  version: string;
  url: string;
  downloadUrl: string;
  size: number | null;
  publishedAt: string | null;
}
interface GitHubRelease {
  tag_name: string;
  draft: boolean;
  prerelease: boolean;
  html_url: string;
  published_at: string;
  assets: { name: string; browser_download_url: string; size: number; state: string }[];
}
export function selectRelease(data: unknown): Release | null {
  if (!Array.isArray(data)) return null;
  const candidates = (data as GitHubRelease[]).filter((release) =>
    release && !release.draft && !release.prerelease && typeof release.published_at === "string" &&
    /^https:\/\/github\.com\/rxtech-lab\/finetext\/releases\//.test(release.html_url ?? "") &&
    Array.isArray(release.assets));
  candidates.sort((a, b) => Date.parse(b.published_at) - Date.parse(a.published_at));
  for (const release of candidates) {
    const asset = release.assets.find((asset) => asset.name === "FineText.dmg" && asset.state === "uploaded" &&
      asset.browser_download_url.startsWith(`${repository}/releases/download/`) && asset.size > 0);
    if (asset) return {
      version: release.tag_name, url: release.html_url, downloadUrl: asset.browser_download_url,
      size: asset.size, publishedAt: release.published_at,
    };
  }
  return null;
}
