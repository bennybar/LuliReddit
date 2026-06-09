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
