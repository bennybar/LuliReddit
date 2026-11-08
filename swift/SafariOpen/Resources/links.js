// A tap on a Reddit link on another site (a Google result…). With the Reddit app
// installed, iOS hands such a link straight to it as a Universal Link and Safari
// never loads the page, so content.js can't see it: catch the tap here instead.
// With "ask which app" on, a sheet offers Ilay or the Reddit app.
document.addEventListener("click", async (e) => {
  if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
  const a = e.target.closest && e.target.closest("a[href]");
  if (!a) return;
  let url;
  try {
    url = new URL(a.href, location.href);
    // Search engines' redirect links: google.com/url?q=<link>, …?url=<link>.
    const wrapped = url.searchParams.get("q") || url.searchParams.get("url") || url.searchParams.get("u");
    if (!ilay.shows(url) && wrapped && /^https?:/.test(wrapped)) url = new URL(wrapped);
  } catch (err) {
    return;
  }
  if (!ilay.shows(url)) return;
  e.preventDefault();
  e.stopImmediatePropagation();
  if (!(await ilay.asks())) return ilay.open(url);
  // Going to the link from this tap's sheet is a tap on another site's link again:
  // iOS hands it to the Reddit app as before (or Safari opens it without the app).
  ilay.choose(url, { label: "Open in Reddit app", action: () => { location.href = url.href; } });
}, true);
