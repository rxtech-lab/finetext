import { test, expect } from "@playwright/test";
const slugs = ["hugging-face", "openai-compatible", "flowcy", "humanizer", "refine-text"];

test("opens a guide from the home page and zooms its WebP screenshot", async ({ page }, testInfo) => {
  await page.goto("/en");
  await page.locator("header").getByRole("link", { name: "Tutorials", exact: true }).click();
  await expect(page).toHaveURL(/\/en\/tutorials$/);
  await expect(page.locator(".tutorial-card")).toHaveCount(5);
  await page.locator(".tutorial-card").filter({ hasText: "Connect your own endpoint" }).click();
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Connect your own endpoint");
  const image = page.locator(".tutorial-image-button img");
  await expect(image).toHaveJSProperty("complete", true);
  expect(await image.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBeGreaterThan(0);
  await expect(image).toHaveAttribute("src", /provider\.webp/);
  await page.getByRole("button", { name: "Enlarge screenshot" }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).not.toBeVisible();
  await expect(page.getByRole("button", { name: "Enlarge screenshot" })).toBeFocused();
  await page.screenshot({ path: testInfo.outputPath("tutorial-desktop.png"), fullPage: true });
});

test("keeps the guide when changing language", async ({ page }) => {
  await page.goto("/en/tutorials/humanizer");
  await page.getByRole("button", { name: "Choose your language" }).click();
  await page.getByRole("button", { name: "繁體中文（台灣）" }).click();
  await expect(page).toHaveURL(/\/zh-TW\/tutorials\/humanizer$/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("設定人性化模型");
  await expect(page.locator(".tutorial-sidebar a[aria-current=page]")).toHaveAttribute("href", "/zh-TW/tutorials/humanizer");
});

test("renders all tutorial locales on mobile with working assets and no overflow", async ({ page }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.setViewportSize({ width: 375, height: 812 });
  for (const locale of ["en", "zh-CN", "zh-TW", "zh-HK"]) {
    await page.goto(`/${locale}/tutorials`);
    await expect(page.locator(".tutorial-card")).toHaveCount(5);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    for (const slug of slugs) {
      await page.goto(`/${locale}/tutorials/${slug}`);
      await expect(page.locator("html")).toHaveAttribute("lang", locale);
      await expect(page.locator(".tutorial-steps li")).toHaveCount(3);
      const destinations: Record<string, string> = {
        "hugging-face": "finetext://settings/local/hugging-face",
        "openai-compatible": "finetext://settings/providers",
        flowcy: "finetext://settings/flowcy",
        humanizer: "finetext://settings/humanizer",
        "refine-text": "finetext://rewrite",
      };
      await expect(page.locator(".tutorial-steps p a.tutorial-open-link")).toHaveAttribute("href", destinations[slug]);
      await expect(page.locator(".tutorial-steps p a.tutorial-open-link")).toBeVisible();
      await expect(page.locator(".tutorial-title a[href^='finetext:']")).toHaveCount(0);
      const linkedStep = slug === "flowcy" ? 1 : 0;
      await expect(page.locator(".tutorial-steps li").nth(linkedStep).locator("a")).toHaveAttribute("href", destinations[slug]);
      const image = page.locator(".tutorial-image-button img");
      await expect(image).toHaveJSProperty("complete", true);
      expect(await image.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBeGreaterThan(0);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    }
    if (locale === "en") await page.screenshot({ path: testInfo.outputPath("tutorial-mobile.png"), fullPage: true });
  }
  expect(errors).toEqual([]);
});

test("links the guide sequence and returns 404 for an unknown guide", async ({ page }) => {
  await page.goto("/en/tutorials/hugging-face");
  for (const slug of slugs.slice(1)) {
    await page.locator(".tutorial-next a").click();
    await expect(page).toHaveURL(new RegExp(`/en/tutorials/${slug}$`));
  }
  await page.locator(".tutorial-next a").click();
  await expect(page).toHaveURL(/\/en\/tutorials$/);
  expect((await page.goto("/en/tutorials/missing-guide"))?.status()).toBe(404);
});
