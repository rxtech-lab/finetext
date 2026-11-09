import { test, mock } from "node:test";
import assert from "node:assert/strict";
import { fetchLatestRelease } from "./github-releases";
import { repository } from "./release-data";

const published = [{
  tag_name: "v1.0.4", draft: false, prerelease: false,
  html_url: `${repository}/releases/tag/v1.0.4`, published_at: "2026-11-09T12:27:30Z",
  assets: [{ name: "FineText.dmg", state: "uploaded", size: 21949233,
    browser_download_url: `${repository}/releases/download/v1.0.4/FineText.dmg` }],
}];

test("loads the published GitHub download without a token", async () => {
  const fetchMock = mock.method(globalThis, "fetch", async (url: string | URL | Request, options?: RequestInit) => {
    assert.equal(url, "https://api.github.com/repos/rxtech-lab/finetext/releases?per_page=100");
    assert.equal(options?.cache, "no-store");
    assert.equal(new Headers(options?.headers).has("Authorization"), false);
    return Response.json(published);
  });
  try {
    assert.equal((await fetchLatestRelease())?.downloadUrl, published[0].assets[0].browser_download_url);
  } finally { fetchMock.mock.restore(); }
});

test("retries public discovery when the optional token is rejected", async () => {
  for (const status of [401, 403, 404]) {
    const credentials: (string | null)[] = [];
    const fetchMock = mock.method(globalThis, "fetch", async (_url: string | URL | Request, options?: RequestInit) => {
      credentials.push(new Headers(options?.headers).get("Authorization"));
      return credentials.length === 1 ? new Response(null, { status }) : Response.json(published);
    });
    try {
      assert.equal((await fetchLatestRelease("expired-token"))?.version, "v1.0.4");
      assert.deepEqual(credentials, ["Bearer expired-token", null]);
    } finally { fetchMock.mock.restore(); }
  }
});

test("a failed lookup does not prevent the next lookup succeeding", async () => {
  let calls = 0;
  const fetchMock = mock.method(globalThis, "fetch", async () => {
    calls++;
    return calls === 1 ? new Response(null, { status: 503 }) : Response.json(published);
  });
  try {
    assert.equal(await fetchLatestRelease(), null);
    assert.equal((await fetchLatestRelease())?.version, "v1.0.4");
  } finally { fetchMock.mock.restore(); }
});
