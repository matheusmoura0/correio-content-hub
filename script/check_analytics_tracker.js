// Run on the VPS in a disposable Playwright container; every request is intercepted.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { chromium } = require("playwright");
const source = fs.readFileSync("/tracker.js", "utf8");
const origin = "https://www.correiodamanha.com.br";

(async () => {
  const browser = await chromium.launch({ headless: true });
  async function fixture({ storageBlocked = false, gpc = false, required = false, fallback = false, duplicate = false } = {}) {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: "pt-BR", timezoneId: "America/Sao_Paulo" });
    await context.addInitScript(({ storageBlocked, gpc, fallback }) => {
      if (storageBlocked) Object.defineProperty(window, "sessionStorage", { get() { throw new DOMException("Blocked"); } });
      if (gpc) Object.defineProperty(navigator, "globalPrivacyControl", { get: () => true });
      if (fallback) navigator.sendBeacon = () => { throw new Error("Unavailable"); };
    }, { storageBlocked, gpc, fallback });
    const page = await context.newPage();
    const events = [], errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.clock.install({ time: new Date("2026-10-28T12:00:00Z") });
    await context.route("**/*", async (route) => {
      const request = route.request();
      if (request.url() === "https://hub.cm.com.br/api/v1/analytics/events") {
        events.push(Object.fromEntries(new URLSearchParams(request.postData())));
        return route.fulfill({ status: 204, headers: { "Access-Control-Allow-Origin": origin } });
      }
      if (request.url() === "https://hub.cm.com.br/cm-analytics.js") return route.fulfill({ contentType: "application/javascript", body: source });
      if (new URL(request.url()).origin === origin) {
        const tag = `<script src="https://hub.cm.com.br/cm-analytics.js" data-site="fixture" data-article-id="123" ${required ? 'data-consent="required"' : ""}></script>`;
        return route.fulfill({ contentType: "text/html", body: `<!doctype html><html><head><title>Fixture</title></head><body>
          <header><a id="next" href="/next?token=secret#section" onclick="event.preventDefault()">Next article</a></header>
          <article style="height:5000px"><button id="button" data-analytics-placement="related">Related</button></article>
          ${tag}${duplicate ? tag : ""}</body></html>` });
      }
      return route.abort();
    });
    await page.goto(`${origin}/fixture?utm_source=newsletter&utm_medium=email&utm_campaign=morning&token=secret`, { waitUntil: "load" });
    return { context, page, events, errors };
  }
  async function settle(page) { await page.evaluate(() => Promise.resolve()); await new Promise((resolve) => setTimeout(resolve, 150)); }
  try {
    const regular = await fixture({ duplicate: true });
    const { page, events } = regular;
    await settle(page);
    assert.equal(events.length, 1, "Duplicate script tags must not duplicate page views");
    assert.equal(events[0].tracking_version, "2");
    assert.equal(events[0].path, "/fixture");
    assert.equal(events[0].entry_path, "/fixture");
    assert.equal(events[0].previous_path, "");
    assert.equal(events[0].utm_source, "newsletter");
    assert.equal(events[0].time_zone, "America/Sao_Paulo");
    assert.equal(events[0].utc_offset_minutes, "-180");
    assert(!JSON.stringify(events).includes("secret"));
    assert(!Number.isNaN(Date.parse(events[0].client_occurred_at)));
    await page.locator("#next").click();
    await settle(page);
    const click = events.find((event) => event.event_type === "click");
    assert.equal(click.target_url, `${origin}/next`);
    assert.equal(click.click_placement, "header");
    assert.equal(click.link_type, "internal");
    assert(Number(click.page_elapsed_ms) >= 0);
    assert.equal(click.page_view_uuid, events[0].page_view_uuid);
    assert.notEqual(click.event_uuid, events[0].event_uuid);
    await page.clock.runFor(16000);
    await settle(page);
    const engagement = events.filter((event) => event.event_type === "engagement");
    assert(engagement.length > 0 && Number(engagement[0].value) > 0, "Active reading must checkpoint before exit");
    const before = engagement.reduce((sum, event) => sum + Number(event.value), 0);
    await page.clock.fastForward(60000);
    await settle(page);
    assert.equal(events.filter((event) => event.event_type === "engagement").reduce((sum, event) => sum + Number(event.value), 0), before, "Idle time must not inflate reading");
    await page.evaluate(() => scrollTo(0, 4500));
    await page.clock.runFor(100);
    await settle(page);
    assert(events.some((event) => event.event_type === "scroll" && Number(event.scroll_depth) >= 75));
    const session = events[0].session_id;
    await page.goto(`${origin}/second?email=private@example.com`, { waitUntil: "load" });
    await settle(page);
    const second = events.filter((event) => event.event_type === "page_view").at(-1);
    assert.equal(second.session_id, session);
    assert.equal(second.previous_path, "/fixture");
    assert.equal(second.entry_path, "/fixture");
    assert.equal(second.utm_campaign, "morning");
    await page.clock.fastForward(1_801_000);
    await page.goto(`${origin}/third`, { waitUntil: "load" });
    await settle(page);
    assert.notEqual(events.filter((event) => event.event_type === "page_view").at(-1).session_id, session);
    assert.deepEqual(regular.errors, []);
    await regular.context.close();

    for (const options of [{ storageBlocked: true }, { fallback: true }]) {
      const test = await fixture(options);
      await test.page.locator("#button").click();
      await settle(test.page);
      assert(test.events.some((event) => event.event_type === "page_view"));
      assert(test.events.some((event) => event.event_type === "click"));
      assert.deepEqual(test.errors, []);
      await test.context.close();
    }
    const privateVisit = await fixture({ gpc: true });
    await privateVisit.page.locator("#button").click();
    await privateVisit.page.clock.runFor(16000);
    await settle(privateVisit.page);
    assert.equal(privateVisit.events.length, 0, "GPC must prevent all tracking");
    await privateVisit.context.close();

    const consent = await fixture({ required: true });
    await settle(consent.page);
    assert.equal(consent.events.length, 0);
    await consent.page.evaluate(() => document.dispatchEvent(new CustomEvent("cm:analytics-consent", { detail: { granted: true } })));
    await consent.page.locator("#button").click();
    await settle(consent.page);
    assert.equal(consent.events.length, 2);
    await consent.page.evaluate(() => document.dispatchEvent(new CustomEvent("cm:analytics-consent", { detail: { granted: false } })));
    await consent.page.locator("#button").click();
    await consent.page.clock.runFor(16000);
    await settle(consent.page);
    assert.equal(consent.events.length, 2, "Revocation must stop events immediately");
    assert.equal(await consent.page.evaluate(() => sessionStorage.getItem("cm_analytics_v2")), null);
    await consent.context.close();
    console.log("Tracker checks passed: timestamps, attribution, click context, scroll, active/idle reading, sessions, blocked storage, beacon fallback, duplicate tags, GPC and consent revocation. No requests reached production.");
  } finally { await browser.close(); }
})().catch((error) => { console.error(error); process.exitCode = 1; });
