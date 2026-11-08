// Content scripts can't reach the app: ask the native side (SafariWebExtensionHandler)
// for Settings → "Safari extension: ask which app".
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message !== "settings") return;
  browser.runtime.sendNativeMessage("application.id", {})
    .then((reply) => sendResponse({ ask: !!(reply && reply.ask) }))
    .catch(() => sendResponse({ ask: false }));
  return true;
});
