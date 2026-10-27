#!/bin/zsh
# Wireless OTA install over a throwaway Cloudflare tunnel (no permanent server).
#
#   ./ota.zsh            # serve the existing ~/Downloads/Luli.ipa
#   ./ota.zsh --build    # rebuild the ad-hoc IPA first, then serve
#
# It starts a local static server, generates manifest.plist + install.html
# pointed at the live tunnel URL, and prints a link. Open that link in SAFARI on
# the device (Chrome/in-app browsers won't trigger the installer). Ctrl-C to
# stop; the tunnel + server are torn down on exit.
#
# Requirements: an Ad Hoc IPA whose profile includes the device UDID, and
# `cloudflared` (brew install cloudflared).

set -e

PROJECT="/Users/bennybarak/StudioProjects/luli_for_reddit"
FLUTTER="/Users/bennybarak/Downloads/flutter/bin/flutter"
IPA_SRC="$HOME/Downloads/Luli.ipa"
SERVE="$HOME/Downloads/ilay-ota"
PORT=8788
BUNDLE_ID="com.bennybar.lulireddit"
TITLE="Ilay for Reddit"
# Version name from pubspec (e.g. 1.0.30), so the manifest always matches.
VERSION=$(grep -m1 '^version:' "$PROJECT/pubspec.yaml" | sed -E 's/^version:[[:space:]]*([0-9.]+).*/\1/')

command -v cloudflared >/dev/null || { echo "✗ cloudflared missing: brew install cloudflared" >&2; exit 1; }

if [[ "$1" == "--build" || ! -f "$IPA_SRC" ]]; then
  echo "==> building ad-hoc IPA (v$VERSION)"
  ( cd "$PROJECT" && "$FLUTTER" build ipa --release --export-options-plist ios/ExportOptions.plist )
  cp "$PROJECT"/build/ios/ipa/*.ipa "$IPA_SRC"
fi
[[ -f "$IPA_SRC" ]] || { echo "✗ no IPA at $IPA_SRC — run ./ota.zsh --build" >&2; exit 1; }

# Fresh serve dir with the IPA.
rm -rf "$SERVE"; mkdir -p "$SERVE"
cp "$IPA_SRC" "$SERVE/app.ipa"

# Static server with the content-types iOS OTA needs (.ipa octet-stream, .plist xml).
python3 - "$SERVE" "$PORT" >/dev/null 2>&1 <<'PY' &
import http.server, socketserver, sys, os
serve_dir, port = sys.argv[1], int(sys.argv[2])
os.chdir(serve_dir)
class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
        '.ipa': 'application/octet-stream', '.plist': 'text/xml', '.html': 'text/html'}
socketserver.TCPServer(("127.0.0.1", port), H).serve_forever()
PY
SERVER_PID=$!

# Anonymous Cloudflare quick-tunnel (no account needed).
LOG=$(mktemp)
cloudflared tunnel --url "http://localhost:$PORT" --no-autoupdate >"$LOG" 2>&1 &
TUNNEL_PID=$!

cleanup() { kill $SERVER_PID $TUNNEL_PID 2>/dev/null || true; }
trap cleanup EXIT INT TERM

echo "==> bringing up tunnel…"
BASE=""
for i in {1..40}; do
  BASE=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" | head -1 || true)
  [[ -n "$BASE" ]] && break
  sleep 1
done
[[ -n "$BASE" ]] || { echo "✗ tunnel didn't come up:" >&2; cat "$LOG" >&2; exit 1; }

# Manifest + install page pointed at the live tunnel URL.
cat > "$SERVE/manifest.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict><key>items</key><array><dict>
  <key>assets</key><array><dict>
    <key>kind</key><string>software-package</string>
    <key>url</key><string>$BASE/app.ipa</string>
  </dict></array>
  <key>metadata</key><dict>
    <key>bundle-identifier</key><string>$BUNDLE_ID</string>
    <key>bundle-version</key><string>$VERSION</string>
    <key>kind</key><string>software</string>
    <key>title</key><string>$TITLE</string>
  </dict>
</dict></array></dict></plist>
EOF

cat > "$SERVE/install.html" <<EOF
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Install $TITLE</title></head>
<body style="font-family:-apple-system;text-align:center;padding:60px 24px">
<h2>$TITLE</h2><p>v$VERSION</p>
<p><a style="display:inline-block;background:#007aff;color:#fff;padding:16px 40px;border-radius:14px;text-decoration:none;font-size:20px"
 href="itms-services://?action=download-manifest&amp;url=$BASE/manifest.plist">Install</a></p>
<p style="color:#888;font-size:14px">Open this page in Safari.</p>
</body></html>
EOF

echo ""
echo "✓ OTA ready. On the device, open this in SAFARI:"
echo ""
echo "    $BASE/install.html"
echo ""
echo "(direct link: itms-services://?action=download-manifest&url=$BASE/manifest.plist)"
echo "Leave this running; Ctrl-C when done."
wait $TUNNEL_PID
