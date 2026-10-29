// Run only against the isolated VPS test server, never the live Hub.
const assert = require("node:assert/strict");
const { chromium, webkit } = require("playwright");

(async () => {
  const base = process.env.HUB_TEST_URL;
  assert(base === "http://127.0.0.1:3127", "Use the isolated VPS test server");
  for (const [name, engine] of [["chromium", chromium], ["webkit", webkit]]) {
    const browser = await engine.launch();
    try {
      const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
      await page.goto(`${base}/users/sign_in`);
      await page.locator('input[name="user[email]"]').fill("browser-admin@example.com");
      await page.locator('input[name="user[password]"]').fill("isolated-browser-password-123");
      await Promise.all([page.waitForURL((url) => !url.pathname.includes("sign_in")), page.getByRole("button", { name: "Entrar", exact: true }).click()]);
      const response = await page.goto(`${base}/metricas/envio-semanal`);
      assert.equal(response.headers()["referrer-policy"], "same-origin");
      await page.locator('select[name="analytics_email_schedule[hour]"]').selectOption("9");
      const saved = page.waitForResponse((response) => response.request().method() === "POST" && response.url().includes("envio-semanal"));
      await page.getByRole("button", { name: "Salvar agendamento", exact: true }).click();
      assert.equal((await saved).status(), 302);
      await page.getByText("Agendamento atualizado.", { exact: true }).waitFor();
      await page.goto(`${base}/metricas/envio-semanal`);
      const preview = page.waitForResponse((response) => response.request().method() === "POST" && response.url().includes("/send_now"));
      await page.getByRole("button", { name: "Prévia para mim", exact: true }).click();
      const sent = await preview;
      assert.equal(sent.status(), 302);
      const payload = new URLSearchParams(sent.request().postData());
      assert.equal(payload.get("delivery_mode"), "preview");
      await page.locator(".report-send-form").waitFor();
      console.log(JSON.stringify({ browser: name, csrfEnabled: true, save: "passed", preview: "passed" }));
    } finally {
      await browser.close();
    }
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
