import { defineConfig, devices } from "@playwright/test";
const port = Number(process.env.PLAYWRIGHT_PORT ?? 3100);
const baseURL = `http://localhost:${port}`;
export default defineConfig({
  testDir: "./tests", fullyParallel: true, use: { baseURL },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"], ...(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {}) } }],
  webServer: { command: `bun run dev --port ${port}`, url: `${baseURL}/en`, reuseExistingServer: !process.env.CI, timeout: 120000 },
});
