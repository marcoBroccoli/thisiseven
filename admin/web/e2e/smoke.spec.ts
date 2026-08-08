import { expect, test } from '@playwright/test'

// A smoke pass over the console's front door. It deliberately does NOT sign in:
// a real sign-in needs a TOTP secret, and a test that carries one would be a
// second, weaker copy of the login path that already has Go coverage.
//
// What it proves is what only a browser can: the embedded bundle is served, it
// boots without a console error, the SPA fallback works on a deep link, and an
// unauthenticated visitor lands on the login screen instead of a blank page.

test.describe('admin console', () => {
  test('serves the SPA and shows the sign-in screen', async ({ page }) => {
    const errors: string[] = []
    page.on('pageerror', (e) => errors.push(e.message))
    page.on('console', (m) => {
      if (m.type() === 'error') errors.push(m.text())
    })

    await page.goto('/')

    await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible()
    await expect(page.getByTestId('login-email')).toBeVisible()
    await expect(page.getByTestId('login-password')).toBeVisible()
    await expect(page.getByTestId('login-submit')).toBeVisible()

    expect(errors, `console errors: ${errors.join(' | ')}`).toHaveLength(0)
  })

  test('a deep link falls back to the SPA shell, not a 404', async ({ page }) => {
    const res = await page.goto('/households/00000000-0000-0000-0000-000000000000')
    expect(res?.status()).toBe(200)
    // No session, so the router never renders the household page.
    await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible()
  })

  test('a wrong password is reported without leaking whether the account exists', async ({
    page,
  }) => {
    await page.goto('/')
    await page.getByTestId('login-email').fill('nobody@example.com')
    await page.getByTestId('login-password').fill('definitely-not-the-password')
    await page.getByTestId('login-submit').click()

    const alert = page.getByRole('alert')
    await expect(alert).toBeVisible()
    await expect(alert).toHaveText(/incorrect|too many/i)
  })

  test('the API refuses unauthenticated reads', async ({ request }) => {
    for (const path of ['/api/dashboard', '/api/users', '/api/households', '/api/audit']) {
      const res = await request.get(path)
      expect(res.status(), path).toBe(401)
      expect(res.headers()['content-type']).toContain('application/json')
    }
  })

  test('healthz is open and honest', async ({ request }) => {
    const res = await request.get('/healthz')
    expect(res.status()).toBe(200)
    expect(await res.json()).toEqual({ ok: true })
  })

  test('security headers are set', async ({ request }) => {
    const res = await request.get('/healthz')
    const h = res.headers()
    expect(h['x-content-type-options']).toBe('nosniff')
    expect(h['x-frame-options']).toBe('DENY')
    expect(h['content-security-policy']).toContain("default-src 'self'")
  })
})
