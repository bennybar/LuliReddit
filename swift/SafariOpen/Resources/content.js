// Sends a Reddit page Ilay can show to the app (luli://share?url=…, the share
// sheet's handoff); Safari asks "Open in Ilay?" first. Other pages (login,
// settings, wiki, search…) stay in Safari.
(() => {
  if (window.top !== window) return;
  const url = new URL(location.href);
  const segs = url.pathname.split("/").filter(Boolean);
  const host = url.hostname.toLowerCase();
  const shown =
    host === "redd.it" ? segs.length >= 1
    : segs.includes("comments") ||
      (segs[0] === "gallery" && segs.length >= 2) ||
      ((segs[0] === "r" || segs[0] === "u" || segs[0] === "user") && segs.length >= 2 &&
        !["wiki", "about", "submit", "search"].includes(segs[2]));
  if (!shown) return;
  // Once per page in this tab: coming back to Safari (or tapping Cancel) and
  // reloading shows the page instead of asking again.
  const key = "ilay-opened:" + url.href;
  try {
    if (sessionStorage.getItem(key)) return;
    sessionStorage.setItem(key, "1");
  } catch (e) {}
  location.href = "luli://share?url=" + encodeURIComponent(url.href);
})();
