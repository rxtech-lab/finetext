import "server-only";
import { fetchLatestRelease } from "./github-releases";
import type { Release } from "./release-data";

export async function getLatestRelease(): Promise<Release | null> {
  try {
    return await fetchLatestRelease(process.env.GITHUB_TOKEN);
  } catch {
    return null;
  }
}
