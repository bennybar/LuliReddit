import 'package:flutter/material.dart';

/// A compact formatting toolbar for a Markdown [TextField]. Wraps the current
/// selection (or inserts placeholders at the caret) with Reddit-flavored
/// markdown. Place it directly above/below the field sharing its controller.
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({super.key, required this.controller});
  final TextEditingController controller;

  void _wrap(String left, String right, {String placeholder = ''}) {
    final value = controller.value;
    final text = value.text;
    var sel = value.selection;
    // No valid selection yet → act at the end of the text.
    if (!sel.isValid) {
      sel = TextSelection.collapsed(offset: text.length);
    }
    final start = sel.start;
    final end = sel.end;
    final selected = start == end ? placeholder : text.substring(start, end);
    final newText = text.replaceRange(start, end, '$left$selected$right');
    // Select the inner text so the user can keep typing/replace the placeholder.
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: start + left.length,
        extentOffset: start + left.length + selected.length,
      ),
    );
  }

  /// Prefixes each selected line (or the caret's line) with [prefix].
  void _linePrefix(String prefix) {
    final value = controller.value;
    final text = value.text;
    var sel = value.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    var lineEnd = text.indexOf('\n', sel.end);
    if (lineEnd == -1) lineEnd = text.length;
    final block = text.substring(lineStart, lineEnd);
    final updated =
        block.split('\n').map((l) => '$prefix$l').join('\n');
    final newText = text.replaceRange(lineStart, lineEnd, updated);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + updated.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: cs.onSurfaceVariant,
          icon: Icon(icon),
          onPressed: onTap,
        );
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          btn(Icons.format_bold_rounded, 'Bold',
              () => _wrap('**', '**', placeholder: 'bold')),
          btn(Icons.format_italic_rounded, 'Italic',
              () => _wrap('*', '*', placeholder: 'italic')),
          btn(Icons.format_strikethrough_rounded, 'Strikethrough',
              () => _wrap('~~', '~~', placeholder: 'text')),
          btn(Icons.link_rounded, 'Link',
              () => _wrap('[', '](https://)', placeholder: 'text')),
          btn(Icons.format_quote_rounded, 'Quote', () => _linePrefix('> ')),
          btn(Icons.format_list_bulleted_rounded, 'List',
              () => _linePrefix('- ')),
          btn(Icons.visibility_off_rounded, 'Spoiler',
              () => _wrap('>!', '!<', placeholder: 'spoiler')),
          btn(Icons.code_rounded, 'Code',
              () => _wrap('`', '`', placeholder: 'code')),
        ],
      ),
    );
  }
}
