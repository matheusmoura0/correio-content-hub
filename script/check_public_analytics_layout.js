// Run only on the VPS, in the disposable Playwright container described in docs.
const assert = require("node:assert/strict");
const { chromium } = require("playwright");

async function noOverflow(page) {
  const size = await page.evaluate(() => ({ viewport: innerWidth, content: document.documentElement.scrollWidth }));
  assert(size.content <= size.viewport + 1, `Horizontal overflow: ${JSON.stringify(size)}`);
}

(async () => {
  const url = process.env.HUB_PUBLIC_ANALYTICS_URL;
  assert(url && new URL(url).hostname === "hub.cm.com.br", "Use the deployed Hub public dashboard URL");
  const browser = await chromium.launch({ headless: true });
  try {
    for (const [width, height] of [[320, 740], [390, 844], [430, 932], [768, 1024], [1280, 900]]) {
      const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1,
        isMobile: width < 768, hasTouch: width < 768, locale: "pt-BR" });
      const page = await context.newPage();
      const response = await page.goto(url, { waitUntil: "domcontentloaded" });
      assert.equal(response.status(), 200);
      await page.locator(".audience-search input").waitFor();
      await noOverflow(page);
      assert.equal(await page.locator(".audience-filter-options").getAttribute("open"), null);
      await page.screenshot({ path: `/review/overview-${width}.png`, animations: "disabled" });
      if (width < 768) {
        const toolbar = page.locator(".audience-mobile-tools");
        assert(await toolbar.isVisible());
        const button = await toolbar.locator(".audience-mobile-pdf").boundingBox();
        assert(button.height >= 44 && button.y + button.height <= height);
        const search = await page.locator(".audience-search input").boundingBox();
        assert(search.height >= 44);
        const kpi = await page.locator(".insights-kpis article").first().boundingBox();
        assert(kpi.y < height * 0.75, "Primary metrics are too far down the first screen");
        await toolbar.locator('a[href="#analytics-ranking"]').click();
        await noOverflow(page);
        const tabs = await page.locator(".insights-tabs").boundingBox();
        assert(tabs.y >= -1 && tabs.y < 2, "Tabs must stick to the viewport top");
        const row = await page.locator(".insights-ranking tbody tr").first().boundingBox();
        assert(row.x >= 0 && row.x + row.width <= width);
        await page.screenshot({ path: `/review/ranking-${width}.png`, animations: "disabled" });
        await toolbar.locator('a[href="#analytics-summary"]').click();
        await page.evaluate(() => scrollTo(0, 0));
        await page.locator(".audience-filter-options > summary").click();
        await page.locator("input[name=from]").waitFor({ state: "visible" });
        await noOverflow(page);
        for (const selector of ["input[name=from]", "input[name=to]", "input[name=author]", "select[name=sort]"]) {
          const input = await page.locator(selector).boundingBox();
          assert(input.x >= 0 && input.x + input.width <= width && input.height >= 44);
        }
        await page.screenshot({ path: `/review/filters-${width}.png`, animations: "disabled" });
      } else {
        assert(!(await page.locator(".audience-mobile-tools").isVisible()));
        assert(await page.locator(".insights-pdf-button").isVisible());
      }
      if (width === 390) {
        await page.goto(`${url}?dimension=authors`, { waitUntil: "domcontentloaded" });
        await page.locator('.audience-mobile-tools a[href="#analytics-ranking"]').click();
        await noOverflow(page);
        await page.screenshot({ path: "/review/authors-390.png", animations: "disabled" });
        await page.goto(`${url}?dimension=categories`, { waitUntil: "domcontentloaded" });
        await page.locator('.audience-mobile-tools a[href="#analytics-ranking"]').click();
        const name = await page.locator(".insights-story-cell > div").first().boundingBox();
        assert(name.width > 220, "Category names need the full row width");
        await noOverflow(page);
        await page.screenshot({ path: "/review/categories-390.png", animations: "disabled" });
        await page.goto(url, { waitUntil: "domcontentloaded" });
        await page.locator("input[name=q]").fill("__hub_mobile_no_results__");
        await page.getByRole("button", { name: "Buscar matéria ou jornalista", exact: true }).click();
        await page.locator(".insights-ranking .insights-empty").waitFor();
        const pdf = await page.locator(".audience-mobile-pdf").getAttribute("href");
        assert.equal(new URL(pdf, url).searchParams.get("q"), "__hub_mobile_no_results__");
        await page.locator('.audience-mobile-tools a[href="#analytics-ranking"]').click();
        const empty = await page.locator(".insights-ranking td[colspan]").boundingBox();
        assert(empty.height > 100, "Empty results must remain in normal document flow");
        await noOverflow(page);
        await page.screenshot({ path: "/review/empty-390.png", animations: "disabled" });
      }
      console.log(JSON.stringify({ width, height, passed: true }));
      await context.close();
    }
  } finally {
    await browser.close();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
