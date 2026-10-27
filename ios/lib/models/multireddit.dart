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

  /// Who owns it (from `/user/<name>/m/<feed>`), else [me].
  String owner(String me) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.length >= 4 && parts[0] == 'user' ? parts[1] : me;
  }

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

/// A feed name Reddit accepts in a path, made from [displayName] (a copy's
/// new name).
String multiSlug(String displayName) {
  var s = displayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
  s = s.replaceAll(RegExp(r'^_+|_+$'), '');
  if (s.length > 50) s = s.substring(0, 50);
  return s.isEmpty ? 'feed' : s;
}
