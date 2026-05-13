// Content script — minimal v0.1. Future versions will add inline
// "Save to DripAdvisor" badges on outfit photos. For now it just exposes
// page-level helpers when the background service worker asks for them.

(function () {
  if (window.__dripadvisorContentLoaded) return;
  window.__dripadvisorContentLoaded = true;

  window.addEventListener("dripadvisor:get-meta", () => {
    window.postMessage({
      source: "dripadvisor",
      type: "meta",
      payload: {
        url: location.href,
        title: document.title,
        ogImage:
          document.querySelector('meta[property="og:image"]')?.content || null,
        ogTitle:
          document.querySelector('meta[property="og:title"]')?.content || null
      }
    }, "*");
  });
})();
