// Background service worker — handles auth, context menu, and API forwarding.

const API_BASE = "https://api.dripadvisor.app"; // override in dev via local storage

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "save-page",
    title: "Save to DripAdvisor",
    contexts: ["page", "image", "link"]
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (!tab?.id) return;

  // Pull OG meta from the page via content script.
  const [{ result: scraped } = {}] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: collectPageMeta
  });

  await saveToBackend({
    url: info.linkUrl || info.srcUrl || tab.url,
    title: scraped?.title || tab.title,
    image: info.srcUrl || scraped?.image || null,
    meta: scraped
  });
});

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === "save-current-tab") {
    (async () => {
      const tab = await activeTab();
      const [{ result: scraped } = {}] = await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: collectPageMeta
      });
      const r = await saveToBackend({
        url: tab.url,
        title: scraped?.title || tab.title,
        image: scraped?.image || null,
        meta: scraped
      });
      sendResponse(r);
    })();
    return true;
  }
});

async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

async function getApiBase() {
  const { apiBase } = await chrome.storage.local.get(["apiBase"]);
  return apiBase || API_BASE;
}

async function getToken() {
  const { sessionToken } = await chrome.storage.local.get(["sessionToken"]);
  return sessionToken;
}

async function saveToBackend(payload) {
  const token = await getToken();
  if (!token) {
    chrome.notifications?.create({
      type: "basic",
      title: "DripAdvisor",
      message: "Sign in via the extension popup first.",
      iconUrl: "icons/icon-128.png"
    });
    return { ok: false, error: "not_signed_in" };
  }
  const base = await getApiBase();
  const res = await fetch(`${base}/v1/wardrobe/scrape`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify({ url: payload.url })
  });
  return { ok: res.ok, status: res.status };
}

// Runs in the page context — pulls OG / schema.org product meta.
function collectPageMeta() {
  const meta = (sel, attr = "content") =>
    document.querySelector(sel)?.getAttribute(attr) || null;
  return {
    title: meta('meta[property="og:title"]') ||
           meta('meta[name="twitter:title"]') ||
           document.title,
    image: meta('meta[property="og:image"]') ||
           meta('meta[property="og:image:secure_url"]') ||
           meta('meta[name="twitter:image"]'),
    siteName: meta('meta[property="og:site_name"]'),
    price: meta('meta[property="product:price:amount"]') ||
           meta('meta[property="og:price:amount"]'),
    currency: meta('meta[property="product:price:currency"]') ||
              meta('meta[property="og:price:currency"]')
  };
}
