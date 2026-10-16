(() => {
  const script = document.currentScript;
  const meta = (name) => document.querySelector(`meta[name="${name}"]`)?.content || "";
  const site = script?.dataset.site || meta("cm:site");
  const endpoint = "https://hub.cm.com.br/api/v1/analytics/events";
  if (!site) return;

  const imageValue = (value) => {
    if (typeof value === "string") return value;
    return value?.url || value?.contentUrl || "";
  };
  const authorImageFromJsonLd = (authorName) => {
    const candidates = [];
    document.querySelectorAll('script[type="application/ld+json"]').forEach((node) => {
      try {
        const queue = [JSON.parse(node.textContent || "null")];
        while (queue.length) {
          const item = queue.shift();
          if (Array.isArray(item)) { queue.push(...item); continue; }
          if (!item || typeof item !== "object") continue;
          if (item.author) candidates.push(...(Array.isArray(item.author) ? item.author : [item.author]));
          if (item["@graph"]) queue.push(item["@graph"]);
        }
      } catch (_) {}
    });
    const normalized = authorName.toLocaleLowerCase("pt-BR");
    const match = candidates.find((author) => typeof author === "object" && author.name?.toLocaleLowerCase("pt-BR") === normalized) ||
      candidates.find((author) => typeof author === "object" && imageValue(author.image));
    return imageValue(match?.image);
  };

  const sessionId = () => {
    let value = sessionStorage.getItem("cm_analytics_session");
    if (!value) {
      value = self.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`;
      sessionStorage.setItem("cm_analytics_session", value);
    }
    return value;
  };
  const author = script?.dataset.author || meta("cm:author");
  const editorial = {
    article_id: script?.dataset.articleId || meta("cm:article-id") || new URLSearchParams(location.search).get("id") || "",
    category: script?.dataset.category || meta("cm:category"),
    author,
    author_image_url: script?.dataset.authorImage || meta("cm:author-image") || authorImageFromJsonLd(author || ""),
    image_url: script?.dataset.image || meta("cm:image") || document.querySelector('meta[property="og:image"]')?.content || ""
  };
  const send = (eventType, data = {}) => {
    const payload = new URLSearchParams({
      site, event_type: eventType, session_id: sessionId(),
      path: `${location.pathname}${location.search}`, title: document.title,
      origin: location.origin, referrer: document.referrer, ...editorial, ...data
    });
    if (!navigator.sendBeacon?.(endpoint, payload)) {
      fetch(endpoint, { method: "POST", body: payload, keepalive: true, mode: "cors" }).catch(() => {});
    }
  };

  send("page_view");
  document.addEventListener("click", (event) => {
    const target = event.target.closest("a,button,[data-analytics-click]");
    if (!target) return;
    send("click", {
      target_url: target.href || target.dataset.analyticsClick || "",
      target_text: (target.innerText || target.ariaLabel || "").trim().slice(0, 160)
    });
  }, { capture: true });

  let seconds = 0;
  let lastTick = Date.now();
  const tick = () => {
    if (document.visibilityState === "visible") seconds += Math.round((Date.now() - lastTick) / 1000);
    lastTick = Date.now();
  };
  document.addEventListener("visibilitychange", tick);
  addEventListener("pagehide", () => {
    tick();
    if (seconds > 0) send("engagement", { value: String(Math.min(seconds, 86_400)) });
  });
})();
