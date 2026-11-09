import { test, expect } from "@playwright/test";
test("negotiates browser language and preserves explicit paths", async ({ browser }) => {
  const context = await browser.newContext({ locale: "zh-HK" });
  const page = await context.newPage();
  await page.goto("/");
  await expect(page).toHaveURL(/\/zh-HK$/);
  await expect(page.locator("html")).toHaveAttribute("lang", "zh-HK");
  await page.goto("/en");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("A little polish. A lot more you.");
  await context.close();
});
test("dialog remembers explicit locale on future visits", async ({ page, context }) => {
  await page.goto("/en");
  await page.getByRole("button", { name: "Choose your language" }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.getByRole("button", { name: "繁體中文（台灣）" }).click();
  await expect(page).toHaveURL(/\/zh-TW$/);
  await expect(page.getByRole("dialog")).not.toBeVisible();
  expect((await context.cookies()).find(cookie => cookie.name === "finetext-locale")?.value).toBe("zh-TW");
  await page.setExtraHTTPHeaders({ "Accept-Language": "en-US" });
  await page.goto("/");
  await expect(page).toHaveURL(/\/zh-TW$/);
});
test("renders all locales without horizontal overflow", async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 375, height: 812 });
  for (const locale of ["en", "zh-CN", "zh-TW", "zh-HK"]) {
    await page.goto(`/${locale}`);
    await expect(page.locator("html")).toHaveAttribute("lang", locale);
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    if (locale === "en") await page.screenshot({ path: testInfo.outputPath("mobile.png"), fullPage: true });
  }
});
test("offers a direct asset download or an honest release fallback", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.goto("/en");
  const download = page.getByRole("link", { name: "Download for Mac" });
  if (await download.count()) {
    await expect(download).toHaveAttribute("href", /^https:\/\/github.com\/rxtech-lab\/finetext\/releases\/download\/[^/]+\/FineText.dmg$/);
  } else {
    await expect(page.getByText("The first release is on its way.")).toBeVisible();
    await expect(page.locator(".hero-actions a")).toHaveAttribute("href", "https://github.com/rxtech-lab/finetext/releases");
  }
  await page.screenshot({ path: testInfo.outputPath("desktop.png"), fullPage: true });
  expect(errors).toEqual([]);
});
test("unknown routes return 404", async ({ page }) => {
  const response = await page.goto("/fr");
  expect(response?.status()).toBe(404);
});
