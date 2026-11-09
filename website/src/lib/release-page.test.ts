import { test } from "node:test";
import assert from "node:assert/strict";
import { releaseAssetsUrl, releaseFromAssets } from "./release-page";
import { repository } from "./release-data";

test("finds only the repository's GitHub asset fragment", () => {
  assert.equal(releaseAssetsUrl('<include-fragment src="/rxtech-lab/finetext/releases/expanded_assets/v1.2.3">'), `${repository}/releases/expanded_assets/v1.2.3`);
  for (const source of ["https://example.com/rxtech-lab/finetext/releases/expanded_assets/v1", "/other/repo/releases/expanded_assets/v1", "/rxtech-lab/finetext/releases/expanded_assets/v1?fake=1"]) {
    assert.equal(releaseAssetsUrl(`<include-fragment src="${source}">`), null);
  }
  assert.equal(releaseAssetsUrl("<html>GitHub unavailable</html>"), null);
});

test("requires the exact DMG from the selected release", () => {
  const assets = `${repository}/releases/expanded_assets/v1.2.3`;
  for (const href of ["https://example.com/FineText.dmg", "/rxtech-lab/finetext/releases/download/v1.0.0/FineText.dmg", "/rxtech-lab/finetext/archive/v1.2.3.zip"]) {
    assert.equal(releaseFromAssets(assets, `<a href="${href}">Download</a>`), null);
  }
});
