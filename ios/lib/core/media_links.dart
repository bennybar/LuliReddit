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

/// A video uploaded inside a text post or comment appears in the text as
/// `reddit.com/link/<post>/video/<id>/player`; it's the v.redd.it video
/// `<id>`. Returns that v.redd.it URL, else null.
Uri? inlineRedditVideo(Uri u) {
  final host = u.host.toLowerCase();
  if (host != 'reddit.com' && !host.endsWith('.reddit.com')) return null;
  final seg = u.pathSegments;
  final i = seg.indexOf('video');
  if (seg.isEmpty || seg.first != 'link' || i < 0 || i + 1 >= seg.length) {
    return null;
  }
  return Uri.parse('https://v.redd.it/${seg[i + 1]}');
}

bool isVideoUrl(Uri u) {
  if (inlineRedditVideo(u) != null) return true;
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
    final media = inlineRedditVideo(uri) ?? uri;
    if (seen.add(media.toString())) out.add(media);
  }
  return out;
}

/// Giphy's animated WebP for a GIF-picker reference (`giphy|<id>` or
/// `giphy|<id>|downsized`), for when Reddit's `media_metadata` has no usable
/// URL for it. Null for anything else.
String? giphyUrl(String ref) {
  if (!ref.startsWith('giphy|')) return null;
  final parts = ref.split('|');
  final id = parts.length > 1 ? parts[1] : '';
  if (id.isEmpty || !RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) return null;
  return 'https://media.giphy.com/media/$id/giphy.webp';
}

/// An uploaded image / picker GIF in a body: `![gif](giphy|id|downsized)` /
/// `![img](id)`; its URL is in `media_metadata`.
final _mediaRefRe = RegExp(r'!\[[^\]]*\]\(([^)\s]+)\)');

final _paragraphRe = RegExp(r'\n\s*\n');
final _loneLinkRe =
    RegExp(r'^!?\[[^\]]*\]\((\S+?)\)$|^<?(https?://\S+?)>?$');

/// [body] without its media-only paragraphs and uploaded-media refs: the text
/// a feed card previews.
String textWithoutMedia(String body) => body
    .replaceAll(_mediaRefRe, '')
    .split(_paragraphRe)
    .map((p) => p.trim())
    .where((p) {
      if (p.isEmpty) return false;
      final m = _loneLinkRe.firstMatch(p);
      if (m == null) return true;
      final lone = m.group(1) ?? m.group(2) ?? '';
      final u = Uri.tryParse(lone);
      return !(u != null && u.hasScheme && isMediaUrl(u));
    })
    .join('\n\n');

/// A piece of a post / comment body: markdown text ([markdown] set), or one
/// media item shown in its place ([media] set).
class BodySegment {
  const BodySegment.text(String this.markdown) : media = null;
  const BodySegment.media(Uri this.media) : markdown = null;
  final String? markdown;
  final Uri? media;
}

/// Splits [body] into text and media, in reading order. A paragraph that is
/// only a media link (a bare URL, `[text](url)` or an uploaded `![img](id)`
/// from [media]) becomes that media, without its link text; media linked
/// inside a sentence follows its paragraph. At most [maxMedia] media items.
List<BodySegment> bodySegments(
    String body, Map<String, String> media, int maxMedia) {
  // Uploaded media refs become their own paragraphs holding the real URL.
  final expanded = body.replaceAllMapped(_mediaRefRe, (m) {
    final ref = m.group(1)!;
    final url = media[ref] ?? giphyUrl(ref);
    return url == null ? m.group(0)! : '\n\n$url\n\n';
  });
  // No media at all (most bodies): the text exactly as written. Splitting it
  // into paragraphs could only lose markdown structure (indented code, nested
  // list paragraphs, blank lines inside fenced code).
  if (expanded == body && extractMediaLinks(body).isEmpty) {
    return body.trim().isEmpty ? const [] : [BodySegment.text(body)];
  }
  final out = <BodySegment>[];
  final text = StringBuffer();
  final seen = <String>{};
  var count = 0;
  void flush() {
    // Only surrounding blank lines go: leading spaces are markdown (an
    // indented code block's first line).
    final t = text.toString();
    if (t.trim().isNotEmpty) {
      out.add(BodySegment.text(
          t.replaceAll(RegExp(r'^[\r\n]+|[\r\n]+$'), '').trimRight()));
    }
    text.clear();
  }

  void addMedia(Uri u) {
    if (count >= maxMedia || !seen.add(u.toString())) return;
    count++;
    out.add(BodySegment.media(u));
  }

  for (final para in expanded.split(_paragraphRe)) {
    final p = para.trim();
    if (p.isEmpty) continue;
    final m = _loneLinkRe.firstMatch(p);
    final lone = m == null ? null : (m.group(1) ?? m.group(2));
    final loneUri = lone == null ? null : Uri.tryParse(lone);
    if (loneUri != null &&
        loneUri.hasScheme &&
        isMediaUrl(loneUri) &&
        count < maxMedia) {
      flush();
      addMedia(inlineRedditVideo(loneUri) ?? loneUri);
      continue;
    }
    if (text.isNotEmpty) text.write('\n\n');
    final trimmed = para.replaceAll(RegExp(r'^[\r\n]+|[\r\n]+$'), '');
    text.write(trimmed.startsWith('    ') || trimmed.startsWith('\t')
        ? trimmed
        : trimmed.trimLeft());
    final inline = extractMediaLinks(p);
    if (inline.isNotEmpty) {
      flush();
      inline.forEach(addMedia);
    }
  }
  flush();
  return out;
}
