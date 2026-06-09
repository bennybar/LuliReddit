/// A user multireddit (custom feed).
class Multireddit {
  const Multireddit({
    required this.name,
    required this.displayName,
    required this.path,
    required this.subreddits,
    this.descriptionMd = '',
    this.visibility = 'private',
    this.iconUrl,
  });

  final String name;
  final String displayName;
  final String path; // /user/{username}/m/{name}/
  final List<String> subreddits;
  final String descriptionMd;
  final String visibility;
  final String? iconUrl;

  factory Multireddit.fromData(Map<String, dynamic> d) {
    final subs = (d['subreddits'] as List?) ?? const [];
    return Multireddit(
      name: d['name'] as String? ?? '',
      displayName: (d['display_name'] as String? ?? d['name'] as String? ?? ''),
      path: d['path'] as String? ?? '',
      subreddits: [
        for (final s in subs)
          (s as Map)['name'] as String? ?? '',
      ]..removeWhere((e) => e.isEmpty),
      descriptionMd: d['description_md'] as String? ?? '',
      visibility: d['visibility'] as String? ?? 'private',
      iconUrl: (d['icon_url'] as String?)?.isEmpty ?? true
          ? null
          : d['icon_url'] as String?,
    );
  }
}
