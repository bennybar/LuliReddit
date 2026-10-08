import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// [MarkdownBody] plus Reddit's own inline syntax: `>!spoilers!<` (hidden
/// until tapped) and `^superscript` / `^(several words)`.
class RedditMarkdown extends StatefulWidget {
  const RedditMarkdown({
    super.key,
    required this.data,
    this.selectable = false,
    this.styleSheet,
    this.onTapLink,
  });

  final String data;
  final bool selectable;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  State<RedditMarkdown> createState() => _RedditMarkdownState();
}

// `>!` at the start of a line would be parsed as a blockquote before any
// inline syntax runs, so spoilers are swapped for private-use markers first.
const _open = '', _close = '';
final _spoilerRe = RegExp(r'>!(.+?)!<');

class _RedditMarkdownState extends State<RedditMarkdown> {
  final _revealed = <int>{};
  final _recognizers = <TapGestureRecognizer>[];
  int _next = 0; // spoiler index while the body is being built

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TextSpan _spoiler(String text, TextStyle? style) {
    // The first spoiler of a fresh parse: the previous parse's spans (and
    // their recognizers) are being replaced. Only dispose them now — a
    // rebuild that doesn't re-parse keeps showing the old spans.
    if (_next == 0) {
      for (final r in _recognizers) {
        r.dispose();
      }
      _recognizers.clear();
    }
    final index = _next++;
    final cs = Theme.of(context).colorScheme;
    if (_revealed.contains(index)) {
      return TextSpan(
          text: text,
          style: style?.copyWith(backgroundColor: cs.surfaceContainerHighest));
    }
    final tap = TapGestureRecognizer()
      ..onTap = () => setState(() => _revealed.add(index));
    _recognizers.add(tap);
    // Same colour for text and background: a solid block until tapped.
    return TextSpan(
      text: text,
      recognizer: tap,
      style: style?.copyWith(
          color: cs.onSurfaceVariant, backgroundColor: cs.onSurfaceVariant),
    );
  }

  @override
  Widget build(BuildContext context) {
    _next = 0; // MarkdownBody re-parses (if at all) after this build
    final data = widget.data.contains('>!')
        ? widget.data.replaceAllMapped(
            _spoilerRe, (m) => '$_open${m.group(1)}$_close')
        : widget.data;
    return MarkdownBody(
      // MarkdownBody only re-parses when its data changes; a new key makes a
      // revealed spoiler actually redraw.
      key: ValueKey(_revealed.length),
      data: data,
      selectable: widget.selectable,
      styleSheet: widget.styleSheet,
      onTapLink: widget.onTapLink,
      inlineSyntaxes: [_SpoilerSyntax(), _SuperscriptSyntax()],
      builders: {
        'spoiler': _SpanBuilder((text, style) => _spoiler(text, style)),
        'sup': _SpanBuilder((text, style) => TextSpan(
              text: text,
              style: style?.copyWith(
                fontSize: (style.fontSize ?? 15) * 0.75,
                fontFeatures: const [FontFeature.superscripts()],
              ),
            )),
      },
    );
  }
}

class _SpoilerSyntax extends md.InlineSyntax {
  _SpoilerSyntax() : super('$_open(.+?)$_close');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('spoiler', match[1]!));
    return true;
  }
}

class _SuperscriptSyntax extends md.InlineSyntax {
  // `^(several words)` or `^word`, as Reddit renders them.
  _SuperscriptSyntax() : super(r'\^\(([^)\n]+)\)|\^([^\s^()]+)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('sup', match[1] ?? match[2]!));
    return true;
  }
}

/// Renders an inline element as a text span, so flutter_markdown merges it
/// into the surrounding paragraph instead of breaking the line.
class _SpanBuilder extends MarkdownElementBuilder {
  _SpanBuilder(this.span);
  final TextSpan Function(String text, TextStyle? style) span;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    return Text.rich(span(element.textContent, parentStyle));
  }
}
