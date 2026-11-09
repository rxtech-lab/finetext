import { test } from "node:test";
import assert from "node:assert/strict";
import { repository, selectRelease } from "./release-data";
const release = (tag: string, date: string, assets = true) => ({
  tag_name: tag, published_at: date, draft: false, prerelease: false,
  html_url: `${repository}/releases/tag/${tag}`,
  assets: assets ? [{ name: "FineText.dmg", state: "uploaded", size: 12345678, browser_download_url: `${repository}/releases/download/${tag}/FineText.dmg` }] : [],
});
test("selects newest built stable release while CI is pending", () => {
  const old = release("v1.0.0", "2026-10-01");
  const ready = release("v1.1.0", "2026-10-02");
  const pending = release("v1.2.0", "2026-10-03", false);
  assert.equal(selectRelease([old, pending, ready])?.version, "v1.1.0");
});
test("ignores draft, prerelease, wrong and incomplete assets", () => {
  const draft = { ...release("v2", "2026-10-04"), draft: true };
  const pre = { ...release("v3", "2026-10-05"), prerelease: true };
  const wrong = release("v4", "2026-10-06");
  wrong.assets[0].browser_download_url = "https://example.com/file.dmg";
  const incomplete = release("v5", "2026-10-07");
  incomplete.assets[0].state = "new";
  assert.equal(selectRelease([draft, pre, wrong, incomplete]), null);
});
test("handles empty or invalid GitHub data", () => {
  for (const input of [[], null, { message: "rate limit" }, [null], [{}]]) assert.equal(selectRelease(input), null);
});
