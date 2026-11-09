import "server-only";
import { selectRelease, type Release } from "./release-data";

export async function getLatestRelease(): Promise<Release | null> {
  try {
    const token = process.env.GITHUB_TOKEN;
    const response = await fetch("https://api.github.com/repos/rxtech-lab/finetext/releases?per_page=100", {
      headers: {
        Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      next: { revalidate: 300 },
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return null;
    return selectRelease(await response.json());
  } catch {
    return null;
  }
}
