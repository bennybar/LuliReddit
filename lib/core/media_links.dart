// Detection of media URLs embedded in comment/post markdown, so we can render
// them natively (image/video viewers) instead of kicking out to a browser.

/// Path (ignoring the query string), lowercased — reddit appends `?width=…&s=…`.
String _path(Uri u) => u.path.toLowerCase();

bool isImageUrl(Uri u) {
  final p = _path(u);
  if (p.endsWith('.jpg') ||
      p.endsWith('.jpeg') ||
      p.endsWith('.png') ||
      p.endsWith('.webp') ||
      p.endsWith('.gif')) {
    return true;
  }
  final host = u.host.toLowerCase();
  return host == 'i.redd.it' ||
      host == 'preview.redd.it' ||
      host == 'i.imgur.com';
}

bool isVideoUrl(Uri u) {
  final p = _path(u);
  if (p.endsWith('.mp4') || p.endsWith('.gifv')) return true;
  return u.host.toLowerCase() == 'v.redd.it';
}

bool isMediaUrl(Uri u) => isVideoUrl(u) || isImageUrl(u);

/// True when the URL points at an animated GIF (rendered as an image, but we
/// keep it distinct so callers can badge it).
bool isGifUrl(Uri u) => _path(u).endsWith('.gif');

final _urlRe = RegExp(r'https?://[^\s<>\)\]"]+');

/// Media URLs referenced anywhere in [markdown] (bare links or `![](url)`),
/// de-duplicated and in order of appearance.
List<Uri> extractMediaLinks(String markdown) {
  final out = <Uri>[];
  final seen = <String>{};
  for (final m in _urlRe.allMatches(markdown)) {
    // Trim trailing markdown/sentence punctuation the regex may have caught.
    var raw = m.group(0)!;
    while (raw.isNotEmpty && '.,;:!*_'.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !isMediaUrl(uri)) continue;
    if (seen.add(raw)) out.add(uri);
  }
  return out;
}

final _mediaRefRe = RegExp(r'!\[[^\]]*\]\(([^)\s]+)\)');

/// Reddit stores GIFs from its picker and some uploaded images in a comment
/// as `![gif](giphy|id|downsized)` / `![img](id)`, with the real URL in
/// `media_metadata` ([media]). Returns [body] with those references removed
/// (markdown can't load them, so they rendered as nothing) and their URLs.
({String text, List<Uri> media}) splitMediaRefs(
    String body, Map<String, String> media) {
  if (media.isEmpty) return (text: body, media: const []);
  final found = <Uri>[];
  final text = body.replaceAllMapped(_mediaRefRe, (m) {
    final url = media[m.group(1)];
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) return m.group(0)!;
    found.add(uri);
    return '';
  });
  return (text: text.trim(), media: found);
}
