import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/widgets/reddit_markdown.dart';

Iterable<TextSpan> _spans(WidgetTester t) sync* {
  final roots = <InlineSpan>[
    for (final r in t.widgetList<RichText>(find.byType(RichText))) r.text,
    for (final s in t.widgetList<SelectableText>(find.byType(SelectableText)))
      if (s.textSpan != null) s.textSpan!,
  ];
  for (final root in roots) {
    final stack = <InlineSpan>[root];
    while (stack.isNotEmpty) {
      final s = stack.removeLast();
      if (s is TextSpan) {
        yield s;
        stack.addAll(s.children ?? const []);
      }
    }
  }
}

void main() {
  Future<void> pump(WidgetTester t, String md, {bool selectable = false}) =>
      t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RedditMarkdown(data: md, selectable: selectable))));

  testWidgets('spoiler stays inline, hidden until tapped', (t) async {
    await pump(t, 'Ending: >!he dies!< sadly.');
    final paragraphs = t
        .widgetList<RichText>(find.byType(RichText))
        .where((r) => r.text.toPlainText().contains('Ending'))
        .toList();
    expect(paragraphs.single.text.toPlainText(), 'Ending: he dies sadly.');
    var spoiler = _spans(t).firstWhere((s) => s.text == 'he dies');
    expect(spoiler.style?.color, spoiler.style?.backgroundColor); // hidden
    expect(spoiler.recognizer, isNotNull);

    (spoiler.recognizer! as dynamic).onTap();
    await t.pump();
    spoiler = _spans(t).firstWhere((s) => s.text == 'he dies');
    expect(spoiler.style?.color, isNot(spoiler.style?.backgroundColor));
  });

  testWidgets('spoiler at line start is not a blockquote', (t) async {
    await pump(t, '>!secret!<');
    expect(find.byType(DecoratedBox).evaluate().where((e) {
      final w = e.widget as DecoratedBox;
      return w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border != null;
    }), isEmpty);
    expect(_spans(t).any((s) => s.text == 'secret'), isTrue);
  });

  testWidgets('superscript, both forms, and selectable mode', (t) async {
    await pump(t, 'x^2 and ^(tiny words) end', selectable: true);
    final sups = _spans(t)
        .where((s) => s.text == '2' || s.text == 'tiny words')
        .toList();
    expect(sups.length, 2);
    expect(sups.every((s) => (s.style?.fontSize ?? 99) < 14), isTrue);
  });
}
