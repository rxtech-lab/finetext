import { test } from "node:test";
import assert from "node:assert/strict";
import { preferredLocale } from "./locales";
test("saved selection takes priority over browser preferences", () => {
  assert.equal(preferredLocale("zh-HK", "en-US,en;q=0.9"), "zh-HK");
  assert.equal(preferredLocale("invalid", "zh-TW"), "zh-TW");
});
test("browser language quality and regional Chinese variants", () => {
  for (const [header, expected] of [
    ["en;q=0.5,zh-CN;q=0.9", "zh-CN"], ["zh-Hant-HK,zh;q=0.9", "zh-HK"],
    ["zh-MO", "zh-HK"], ["zh-Hant", "zh-TW"], ["zh-SG", "zh-CN"],
    ["fr,zh-TW;q=0.8", "zh-TW"], ["zh-HK;q=0,en;q=0.2", "en"],
    ["de", "en"], ["zh-CN;q=invalid", "en"],
  ]) assert.equal(preferredLocale(undefined, header), expected);
  assert.equal(preferredLocale(undefined, null), "en");
});
