import { defineConfig, devices } from '@playwright/test'

// The smoke spec is written to run against a locally-running admin service; it
// is NOT part of the build gate and does not download a browser on install.
// Run it deliberately:
//
//   npx playwright install chromium      # one time, ~120 MB
//   ADMIN_BASE_URL=http://127.0.0.1:3026 npm run test:e2e
export default defineConfig({
  testDir: './e2e',
  timeout: 20_000,
  expect: { timeout: 5_000 },
  fullyParallel: false,
  workers: 1,
  reporter: [['list']],
  use: {
    baseURL: process.env.ADMIN_BASE_URL ?? 'http://127.0.0.1:3026',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
})
