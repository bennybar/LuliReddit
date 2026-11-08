// Shared by content.js and links.js: which Reddit links Ilay shows, the app
// handoff (luli://share?url=…, the share sheet's), the "ask which app" setting
// and the sheet that asks.
var ilay = {
  shows(url) {
    const host = url.hostname.toLowerCase();
    const segs = url.pathname.split("/").filter(Boolean);
    if (host === "redd.it") return segs.length >= 1;
    if (host !== "reddit.com" && !host.endsWith(".reddit.com")) return false;
    return segs.includes("comments") ||
      (segs[0] === "gallery" && segs.length >= 2) ||
      ((segs[0] === "r" || segs[0] === "u" || segs[0] === "user") && segs.length >= 2 &&
        !["wiki", "about", "submit", "search"].includes(segs[2]));
  },

  open(url) {
    location.href = "luli://share?url=" + encodeURIComponent(url.href);
  },

  /// Settings → "Safari extension: ask which app" (off if it can't be read).
  async asks() {
    try {
      const reply = await browser.runtime.sendMessage("settings");
      return !!(reply && reply.ask);
    } catch (e) {
      return false;
    }
  },

  /// A sheet at the bottom of the page: "Open in Ilay", [other] (a label and what
  /// it does), Cancel. Cancel and a tap outside it just close it.
  choose(url, other) {
    const host = document.createElement("div");
    host.style.cssText = "all:initial;position:fixed;inset:0;z-index:2147483647;";
    const root = host.attachShadow({ mode: "closed" });
    root.innerHTML = `
      <style>
        :host { --bg:#f2f2f7; --row:#fff; --text:#000; --dim:#8e8e93; --line:rgba(60,60,67,.18); --accent:#6e52d6; }
        @media (prefers-color-scheme: dark) {
          :host { --bg:#1c1c1e; --row:#2c2c2e; --text:#fff; --dim:#98989f; --line:rgba(84,84,88,.6); --accent:#9b85ff; }
        }
        .scrim { position:fixed; inset:0; background:rgba(0,0,0,.3); }
        .sheet { position:fixed; left:8px; right:8px; bottom:calc(8px + env(safe-area-inset-bottom));
          font:17px -apple-system, system-ui; color:var(--text); display:flex; flex-direction:column; gap:8px; }
        .group { background:var(--row); border-radius:14px; overflow:hidden; }
        .title { padding:12px 16px; text-align:center; font-size:13px; color:var(--dim);
          border-bottom:0.5px solid var(--line); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
        button { all:unset; display:block; box-sizing:border-box; width:100%; padding:16px; text-align:center;
          color:var(--accent); -webkit-tap-highlight-color:transparent; }
        button + button { border-top:0.5px solid var(--line); }
        button:active { background:var(--line); }
        .main { font-weight:600; }
        .cancel { font-weight:600; }
      </style>
      <div class="scrim"></div>
      <div class="sheet">
        <div class="group">
          <div class="title"></div>
          <button class="main ilay">Open in Ilay</button>
          <button class="other"></button>
        </div>
        <div class="group"><button class="cancel">Cancel</button></div>
      </div>`;
    root.querySelector(".title").textContent = url.hostname.replace(/^www\./, "") + url.pathname;
    root.querySelector(".other").textContent = other.label;
    const close = () => host.remove();
    root.querySelector(".ilay").addEventListener("click", () => { close(); ilay.open(url); });
    root.querySelector(".other").addEventListener("click", () => { close(); other.action(); });
    root.querySelector(".cancel").addEventListener("click", close);
    root.querySelector(".scrim").addEventListener("click", close);
    (document.body || document.documentElement).appendChild(host);
  },
};
