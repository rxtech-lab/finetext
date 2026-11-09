import { repository, selectRelease, type Release } from "./release-data";
import { fetchReleasePage } from "./release-page";

export async function fetchLatestRelease(token?: string): Promise<Release | null> {
  const request = (credential?: string) => fetch(
    "https://api.github.com/repos/rxtech-lab/finetext/releases?per_page=100",
    {
      headers: {
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        ...(credential ? { Authorization: `Bearer ${credential}` } : {}),
      },
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
    },
  );

  try {
    let response = await request(token);
    // Public downloads should still work with an expired or restricted optional token.
    if (token && [401, 403, 404].includes(response.status)) response = await request();
    if (!response.ok) {
      console.warn(`GitHub releases lookup failed (${response.status}): ${repository}`);
    } else {
      const release = selectRelease(await response.json());
      if (release) return release;
    }
  } catch {
    console.warn(`GitHub releases lookup could not complete: ${repository}`);
  }
  return fetchReleasePage();
}
