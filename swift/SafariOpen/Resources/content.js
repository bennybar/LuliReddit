// A Reddit page Safari loads (typed, a bookmark, a link Safari opened itself) goes
// to Ilay; Safari asks "Open in Ilay?" first. Other pages (login, settings, wiki,
// search…) stay in Safari. With "ask which app" on, a sheet offers Ilay or staying.
(async () => {
  if (window.top !== window) return;
  const url = new URL(location.href);
  if (!ilay.shows(url)) return;
  // Once per page in this tab: coming back to Safari (or tapping Cancel) and
  // reloading shows the page instead of asking again.
  const key = "ilay-opened:" + url.href;
  try {
    if (sessionStorage.getItem(key)) return;
    sessionStorage.setItem(key, "1");
  } catch (e) {}
  if (!(await ilay.asks())) return ilay.open(url);
  const show = () => ilay.choose(url, { label: "Stay in Safari", action: () => {} });
  if (document.body) show();
  else document.addEventListener("DOMContentLoaded", show, { once: true });
})();
