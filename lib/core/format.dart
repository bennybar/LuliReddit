/// Compact formatting helpers for scores, counts and relative time.
String compactNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

String timeAgo(DateTime utc) {
  final diff = DateTime.now().toUtc().difference(utc);
  if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}y';
  if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo';
  if (diff.inDays >= 1) return '${diff.inDays}d';
  if (diff.inHours >= 1) return '${diff.inHours}h';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
  return 'now';
}
