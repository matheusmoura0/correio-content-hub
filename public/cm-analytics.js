(() => {
  const script = document.currentScript;
  const meta = (name) => document.querySelector(`meta[name="${name}"]`)?.content || "";
  const site = script?.dataset.site || meta("cm:site");
  const endpoint = "https://hub.cm.com.br/api/v1/analytics/events";
  if (!site || window.__cmAnalyticsV2) return;
  window.__cmAnalyticsV2 = true;
  let consent = window.cmAnalyticsConsent;
  const permitted = () => consent !== false && (script?.dataset.consent !== "required" || consent === true) &&
    !navigator.globalPrivacyControl && navigator.doNotTrack !== "1" && window.doNotTrack !== "1";
  const uuid = () => self.crypto?.randomUUID?.() || "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (char) => {
    const random = Math.floor(Math.random() * 16);
    return (char === "x" ? random : (random & 3) | 8).toString(16);
  });
  const safePath = (value) => {
    if (!value) return "";
    try { const url = new URL(value, location.origin); return url.origin === location.origin ? url.pathname : ""; } catch (_) { return ""; }
  };
  const safeUrl = (value, originOnly = false) => {
    if (!value) return "";
    try {
      const url = new URL(value, location.href);
      if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) return "";
      return originOnly ? url.origin : `${url.origin}${url.pathname}`;
    } catch (_) { return ""; }
  };
  const readStorage = () => { try { return JSON.parse(sessionStorage.getItem("cm_analytics_v2") || "null"); } catch (_) { return null; } };
  const store = (value) => { try { sessionStorage.setItem("cm_analytics_v2", JSON.stringify(value)); } catch (_) {} };

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
    const normalize = (value) => typeof value === "string" ? value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim().replace(/^por\s+/i, "").replace(/\s+/g, " ").toLocaleLowerCase("pt-BR") : "";
    const normalized = normalize(authorName);
    if (!normalized) return "";
    const match = candidates.find((author) => author && typeof author === "object" && normalize(author.name) === normalized);
    return imageValue(match?.image);
  };

  const author = script?.dataset.author || meta("cm:author");
  const editorial = {
    article_id: script?.dataset.articleId || meta("cm:article-id") || new URLSearchParams(location.search).get("id") || "",
    category: script?.dataset.category || meta("cm:category"),
    author,
    author_image_url: script?.dataset.authorImage || meta("cm:author-image") || authorImageFromJsonLd(author || ""),
    image_url: script?.dataset.image || meta("cm:image") || document.querySelector('meta[property="og:image"]')?.content || ""
  };
  let session, pageId, opened = 0, previousPath = "", activeMs = 0, sentActive = 0, maxScroll = 0;
  let lastTick = performance.now(), lastActivity = lastTick, started = false, stopped = false;
  let timeZone = "";
  try { timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || ""; } catch (_) {}
  const campaign = (value) => /^[a-zA-Z0-9 _.-]{1,80}$/.test(value || "") && !/\d{7,}/.test(value) ? value : "";
  const initializePage = () => {
    const now = Date.now();
    session = readStorage();
    if (!session || !/^[a-f0-9-]{36}$/i.test(session.id || "") || !Number.isFinite(session.lastSeen) || now - session.lastSeen > 1_800_000 || now < session.lastSeen) {
      const query = new URLSearchParams(location.search);
      session = { id: uuid(), lastSeen: now, entry: location.pathname, referrer: safeUrl(document.referrer, true),
        utm_source: campaign(query.get("utm_source")), utm_medium: campaign(query.get("utm_medium")), utm_campaign: campaign(query.get("utm_campaign")) };
    }
    previousPath = safePath(session.current || "");
    session.current = location.pathname;
    session.lastSeen = now;
    store(session);
    pageId = uuid();
  };
  const tick = () => {
    const now = performance.now();
    if (permitted() && !stopped && document.visibilityState === "visible" && document.hasFocus() && now - lastActivity < 30_000) {
      activeMs += Math.min(Math.max(now - lastTick, 0), 5_000);
    }
    lastTick = now;
  };
  const depth = () => {
    const article = document.querySelector("[itemprop=articleBody], article, main");
    const top = article ? article.getBoundingClientRect().top + scrollY : 0;
    const height = article?.scrollHeight || document.documentElement.scrollHeight;
    if (height > 0) maxScroll = Math.max(maxScroll, Math.min(100, Math.max(0, Math.floor((scrollY + innerHeight - top) * 100 / height))));
  };
  const send = (eventType, data = {}) => {
    if (!permitted() || !started || stopped) return;
    tick();
    session.lastSeen = Date.now();
    store(session);
    const payload = new URLSearchParams({
      site, event_type: eventType, session_id: session.id, tracking_version: "2", event_uuid: uuid(), page_view_uuid: pageId,
      client_occurred_at: new Date().toISOString(), page_elapsed_ms: String(Math.min(86_400_000, Math.max(0, Math.round(performance.now() - opened)))),
      time_zone: timeZone, utc_offset_minutes: String(-new Date().getTimezoneOffset()), language: (navigator.language || "").slice(0, 2),
      scroll_depth: String(maxScroll), active_seconds: String(Math.floor(activeMs / 1000)),
      path: location.pathname, title: document.title, entry_path: safePath(session.entry), previous_path: previousPath,
      origin: location.origin, referrer: safeUrl(document.referrer, true), entry_referrer: safeUrl(session.referrer, true),
      utm_source: campaign(session.utm_source), utm_medium: campaign(session.utm_medium), utm_campaign: campaign(session.utm_campaign),
      ...editorial, ...data
    });
    try {
      if (navigator.sendBeacon?.(endpoint, payload)) return;
    } catch (_) {}
    try { fetch(endpoint, { method: "POST", body: payload, keepalive: true, mode: "cors", credentials: "omit" }).catch(() => {}); } catch (_) {}
  };
  const checkpoint = () => {
    if (!permitted() || !started || stopped) return;
    tick();
    depth();
    const seconds = Math.floor(activeMs / 1000);
    const delta = seconds - sentActive;
    if (delta > 0) {
      send("engagement", { value: String(Math.min(delta, 86_400)) });
      sentActive = seconds;
    }
  };
  const begin = () => {
    if (!permitted() || started) return;
    started = true;
    initializePage();
    send("page_view");
  };
  document.addEventListener("cm:analytics-consent", (event) => {
    consent = event.detail?.granted === true;
    if (consent) begin();
    else {
      try { sessionStorage.removeItem("cm_analytics_v2"); } catch (_) {}
      started = false;
      activeMs = sentActive = maxScroll = 0;
      opened = lastTick = lastActivity = performance.now();
    }
  });
  begin();
  ["pointerdown", "pointermove", "keydown", "touchstart", "scroll"].forEach((name) => {
    document.addEventListener(name, () => { lastActivity = performance.now(); }, { passive: true });
  });
  addEventListener("scroll", () => {
    if (!permitted() || !started || stopped) return;
    const before = Math.floor(maxScroll / 25);
    depth();
    if (Math.floor(maxScroll / 25) > before) send("scroll", { value: String(maxScroll) });
  }, { passive: true });
  document.addEventListener("click", (event) => {
    if (!permitted() || !started || stopped || !(event.target instanceof Element)) return;
    const target = event.target.closest("a,button,[data-analytics-click]");
    if (!target) return;
    const url = safeUrl(target.href || "");
    const share = target.closest("[data-analytics-placement=share],.share,.social-share") || /(?:wa\.me|whatsapp\.com)\//.test(url);
    const marked = target.closest("[data-analytics-placement]")?.dataset.analyticsPlacement;
    const placement = marked || (share ? "share" : target.closest("header") ? "header" : target.closest("footer") ? "footer" :
      target.closest("nav") ? "navigation" : target.closest(".related-articles,[data-related-articles]") ? "related" : target.closest("article") ? "article_body" : "other");
    depth();
    send("click", {
      target_url: url, click_placement: placement,
      link_type: share ? "share" : !url ? "action" : new URL(url).origin === location.origin ? "internal" : "external",
      target_text: (target.dataset.analyticsLabel || target.innerText || target.ariaLabel || "").trim().slice(0, 100)
    });
  }, { capture: true });
  setInterval(tick, 5_000);
  setInterval(checkpoint, 15_000);
  document.addEventListener("visibilitychange", () => { checkpoint(); tick(); });
  addEventListener("pagehide", () => {
    checkpoint();
    stopped = true;
  });
  addEventListener("pageshow", (event) => {
    if (!event.persisted || !permitted()) return;
    opened = lastTick = lastActivity = performance.now();
    activeMs = sentActive = maxScroll = 0;
    stopped = false;
    started = false;
    begin();
  });
})();
