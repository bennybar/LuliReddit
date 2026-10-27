import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../open_link.dart';

/// [MarkdownBody] plus Reddit's own inline syntax: `>!spoilers!<` (hidden
/// until tapped) and `^superscript` / `^(several words)`. Links open in the
/// app ([openLink]) unless [onTapLink] says otherwise, and a mostly
/// Hebrew / Arabic body lays out right-to-left.
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
    final body = MarkdownBody(
      // MarkdownBody only re-parses when its data changes; a new key makes a
      // revealed spoiler actually redraw.
      key: ValueKey(_revealed.length),
      data: data,
      selectable: widget.selectable,
      styleSheet: widget.styleSheet,
      onTapLink:
          widget.onTapLink ?? (_, href, __) => openLink(context, href),
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
    // Hebrew / Arabic / Persian text reads from the right: lay the blocks out
    // right-to-left (alignment, list bullets, quote bar), not just the
    // glyphs. Full width, so the text can sit against the right edge.
    if (!isMostlyRtl(widget.data)) return body;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Align(alignment: AlignmentDirectional.topStart, child: body),
    );
  }
}

/// More right-to-left letters (Hebrew, Arabic…) than left-to-right ones.
bool isMostlyRtl(String text) {
  var rtl = 0, ltr = 0;
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) ||
        (r >= 0xFB1D && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF)) {
      rtl++;
    } else if ((r >= 0x41 && r <= 0x5A) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x024F && r != 0xD7 && r != 0xF7) ||
        (r >= 0x0370 && r <= 0x052F) ||
        (r >= 0x0900 && r <= 0x1FFF) ||
        (r >= 0x3040 && r <= 0x9FFF) ||
        (r >= 0xAC00 && r <= 0xD7AF)) {
      ltr++; // Latin, Greek, Cyrillic, Indic, CJK, Hangul…
    }
  }
  return rtl > ltr;
}

/// [markdown] as plain text (for previews cut to a few lines).
String markdownPlainText(String markdown) {
  final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubWeb)
      .parseLines(markdown.split('\n'));
  final out = StringBuffer();
  void walk(md.Node n) {
    if (n is md.Text) {
      out.write(n.text);
    } else if (n is md.Element) {
      n.children?.forEach(walk);
      if (const ['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'pre']
          .contains(n.tag)) {
        out.write('\n');
      }
    }
  }

  nodes.forEach(walk);
  return out.toString().trim();
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
