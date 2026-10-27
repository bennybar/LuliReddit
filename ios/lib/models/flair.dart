/// A subreddit link flair template.
class Flair {
  const Flair({required this.id, required this.text});
  final String id;
  final String text;

  factory Flair.fromJson(Map<String, dynamic> j) => Flair(
        id: j['id'] as String? ?? '',
        text: (j['text'] as String? ?? '').trim(),
      );
}

/// One piece of a user flair: some text, or an emoji (an image Reddit hosts).
class FlairPart {
  const FlairPart({this.text, this.emojiUrl});
  final String? text;
  final String? emojiUrl;

  @override
  bool operator ==(Object other) =>
      other is FlairPart && other.text == text && other.emojiUrl == emojiUrl;

  @override
  int get hashCode => Object.hash(text, emojiUrl);

  @override
  String toString() => 'FlairPart(text: $text, emojiUrl: $emojiUrl)';
}

/// A user's flair: its text and emoji, in order.
class UserFlair {
  const UserFlair(this.parts);
  final List<FlairPart> parts;

  /// Just the words, for where images can't go.
  String get text => parts
      .map((p) => p.text ?? '')
      .join()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  bool operator ==(Object other) =>
      other is UserFlair &&
      other.parts.length == parts.length &&
      [for (var i = 0; i < parts.length; i++) other.parts[i] == parts[i]]
          .every((e) => e);

  @override
  int get hashCode => Object.hashAll(parts);
}

/// A user's flair from a post or comment: the richtext's text and emoji
/// parts; else the plain text without its :emoji: codes (no image links
/// there). Null when there's none.
UserFlair? authorFlairOf(Map<String, dynamic>? d) {
  final rich = d?['author_flair_richtext'];
  final parts = <FlairPart>[];
  if (rich is List && rich.isNotEmpty) {
    for (final p in rich) {
      if (p is! Map) continue;
      final t = p['t'], u = p['u'];
      if (p['e'] == 'text' && t is String && t.isNotEmpty) {
        parts.add(FlairPart(text: t));
      } else if (p['e'] == 'emoji' && u is String && u.startsWith('http')) {
        parts.add(FlairPart(emojiUrl: u));
      }
    }
  } else {
    final plain = (d?['author_flair_text'] as String? ?? '')
        .replaceAll(RegExp(r':[\w-]+:'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.isNotEmpty) parts.add(FlairPart(text: plain));
  }
  // Tidy the ends: no leading / trailing spaces around the emoji.
  final tidy = <FlairPart>[];
  for (var i = 0; i < parts.length; i++) {
    var t = parts[i].text;
    if (t == null) {
      tidy.add(parts[i]);
      continue;
    }
    if (i == 0) t = t.trimLeft();
    if (i == parts.length - 1) t = t.trimRight();
    if (t.isNotEmpty) tidy.add(FlairPart(text: t));
  }
  return tidy.isEmpty ? null : UserFlair(tidy);
}

/// A choice of user flair in a community, and whether you may write your own
/// text in it.
class UserFlairChoice {
  const UserFlairChoice(
      {required this.id, required this.text, required this.editable});
  final String id;
  final String text;
  final bool editable;
}

/// Your flair in a community now, and what you can pick from.
class UserFlairSelector {
  const UserFlairSelector(
      {this.currentText, this.currentId, this.choices = const []});
  final String? currentText;
  final String? currentId;
  final List<UserFlairChoice> choices;
}
