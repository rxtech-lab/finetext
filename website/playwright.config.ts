import { defineConfig, devices } from "@playwright/test";
export default defineConfig({
  testDir: "./tests", fullyParallel: true, use: { baseURL: "http://localhost:3100" },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"], ...(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {}) } }],
  webServer: { command: "bun run dev --port 3100", url: "http://localhost:3100/en", reuseExistingServer: !process.env.CI, timeout: 120000 },
});
