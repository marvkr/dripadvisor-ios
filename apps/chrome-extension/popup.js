// Popup script — basic auth + save-current-page action.
// Full OAuth flow (chrome.identity.launchWebAuthFlow against
// dripadvisor.app/auth/extension/callback) is a v0.2 task.

(async function () {
  const { sessionToken } = await chrome.storage.local.get(["sessionToken"]);
  const $ = (id) => document.getElementById(id);

  if (sessionToken) {
    $("status").textContent = "Signed in.";
    $("saved-section").hidden = false;
  } else {
    $("status").textContent = "Sign in to save items.";
    $("auth-section").hidden = false;
  }

  $("save-token").addEventListener("click", async () => {
    const token = $("token").value.trim();
    const apiBase = $("apiBase").value.trim();
    if (!token) return;
    const payload = { sessionToken: token };
    if (apiBase) payload.apiBase = apiBase;
    await chrome.storage.local.set(payload);
    $("status").textContent = "Signed in.";
    $("auth-section").hidden = true;
    $("saved-section").hidden = false;
  });

  $("sign-out")?.addEventListener("click", async () => {
    await chrome.storage.local.remove(["sessionToken"]);
    location.reload();
  });

  $("save-page")?.addEventListener("click", async () => {
    $("save-page").disabled = true;
    $("save-page").textContent = "Saving…";
    const result = await chrome.runtime.sendMessage({ type: "save-current-tab" });
    if (result?.ok) {
      $("save-page").textContent = "Saved";
    } else {
      $("save-page").textContent = "Retry";
      $("save-page").disabled = false;
    }
  });
})();
