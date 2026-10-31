// Use only on the VPS with a rendered settings page from an isolated test database.
const { chromium } = require("playwright");
const fs = require("node:fs");
const assert = require("node:assert/strict");

(async () => {
  const browser = await chromium.launch();
  try {
    for (const width of [320, 390, 1280]) {
      const context = await browser.newContext({ viewport: { width, height: 900 }, javaScriptEnabled: false });
      const page = await context.newPage();
      const html = fs.readFileSync("/review/settings.html", "utf8");
      // A synthetic same-origin document allows the actual icon masks to load without a login.
      await page.route("https://hub.cm.com.br/__codex-email-layout", (route) => route.fulfill({ status: 200, contentType: "text/html; charset=utf-8", body: html }));
      await page.goto("https://hub.cm.com.br/__codex-email-layout", { waitUntil: "networkidle" });
      const size = await page.evaluate(() => ({ viewport: innerWidth, content: document.documentElement.scrollWidth }));
      assert(size.content <= size.viewport + 1, JSON.stringify(size));
      for (const selector of [".report-recipient-form input[type=email]", ".report-recipient-form button", ".report-send-form input[type=date]", ".report-email-form select", ".report-email-form button"]) {
        const box = await page.locator(selector).first().boundingBox();
        assert(box.height >= 44 && box.x >= 0 && box.x + box.width <= width, `${selector}: ${JSON.stringify(box)}`);
      }
      assert.equal(await page.locator(".report-send-form button").count(), 2);
      assert(await page.getByRole("button", { name: "Enviar agora", exact: true }).isVisible());
      await page.screenshot({ path: `/review/settings-${width}.png`, fullPage: true });
      console.log(JSON.stringify({ width, passed: true }));
      await context.close();
    }
  } finally {
    await browser.close();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
