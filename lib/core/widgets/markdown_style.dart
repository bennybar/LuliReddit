import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Shared Markdown styling for comments/posts/messages. Notably fixes
/// blockquotes (the default light-blue box rendered low-contrast text in dark
/// mode) — now a left accent bar + subtle background with readable text.
MarkdownStyleSheet redditMarkdownStyle(BuildContext context,
    {double fontSize = 15}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final body = theme.textTheme.bodyMedium?.copyWith(
    fontSize: fontSize,
    height: 1.45,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    blockquote: body?.copyWith(color: cs.onSurfaceVariant),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    blockquoteDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      border: Border(left: BorderSide(color: cs.primary, width: 3)),
    ),
  );
}
