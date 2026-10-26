import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/open_link.dart';
import '../../core/widgets/markdown_style.dart';
import '../../core/widgets/reddit_markdown.dart';
import '../../data/ai_service.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';
import 'summary_store.dart';

String _aiBaseUrl(Settings s) =>
    s.aiUseCustomUrl ? s.aiBaseUrl : 'https://api.openai.com';

/// Runs an AI thread summary and shows the result (markdown) with copy.
void showSummarySheet(
    BuildContext context, WidgetRef ref, Post post, List<Comment> comments) {
  final key = ref.read(openAiKeyProvider).valueOrNull;
  if (key == null || key.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add an OpenAI key in Settings → AI summaries.')));
    return;
  }
  final s = ref.read(settingsControllerProvider);
  final style = SummaryStyle
      .values[s.aiSummaryStyle.clamp(0, SummaryStyle.values.length - 1)];
  final threadText = AiService.buildThreadText(post, comments, s.aiMaxChars);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SummarySheet(
      post: post,
      baseUrl: _aiBaseUrl(s),
      apiKey: key,
      model: s.aiModel,
      style: style,
      language: s.aiSummaryLanguage,
      threadText: threadText,
      store: ref.read(summaryStoreProvider.notifier),
    ),
  );
}

class _SummarySheet extends StatefulWidget {
  const _SummarySheet({
    required this.post,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.style,
    required this.language,
    required this.threadText,
    required this.store,
  });
  final Post post;
  final String baseUrl;
  final String apiKey;
  final String model;
  final SummaryStyle style;
  final String language;
  final String threadText;
  final SummaryStore store;

  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  bool _loading = true;
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await AiService.summarize(
        baseUrl: widget.baseUrl,
        apiKey: widget.apiKey,
        model: widget.model,
        style: widget.style,
        threadText: widget.threadText,
        language: widget.language,
      );
      // Kept in Summaries, with a link back to the post.
      final p = widget.post;
      widget.store.add(SavedSummary(
        postId: p.id,
        subreddit: p.subreddit,
        title: p.title,
        permalink: p.permalink,
        style: widget.style.label,
        model: widget.model,
        text: out,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      if (mounted) {
        setState(() {
          _result = out;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e'.replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Opens fully, at most 92% tall, and scrolls inside, so the end of a long
    // summary can always be scrolled into view.
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, 28 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('AI summary · ${widget.style.label}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (_result != null && !_loading)
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.content_copy_rounded, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _result!));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null) ...[
              Text(_error!, style: TextStyle(color: cs.error)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _run, child: const Text('Retry')),
            ] else
              RedditMarkdown(
                  data: _result ?? '',
                  selectable: true,
                  styleSheet: redditMarkdownStyle(context)),
            if (!_loading && _error == null) ...[
              const SizedBox(height: 16),
              Text('Generated by ${widget.model}. AI summaries can be wrong.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Ask about this thread": a short chat with the AI about the post and its
/// comments. Follow-up questions keep the conversation; nothing is kept after
/// the sheet closes. A cited comment's link closes the sheet and calls
/// [onOpenComment] with its fullname.
void showAskSheet(BuildContext context, WidgetRef ref, Post post,
    List<Comment> comments, void Function(String fullname) onOpenComment) {
  final key = ref.read(openAiKeyProvider).valueOrNull;
  if (key == null || key.isEmpty) return;
  final s = ref.read(settingsControllerProvider);
  final thread = AiService.buildCitedThread(post, comments, s.aiMaxChars);
  // What the answers can draw on: the comments that fit, of those loaded, of
  // the thread's total.
  final total =
      post.numComments > thread.loaded ? post.numComments : thread.loaded;
  final coverage =
      'Reads ${thread.included} of $total comments, most upvoted first';
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => AskThreadSheet(
      baseUrl: _aiBaseUrl(s),
      apiKey: key,
      model: s.aiModel,
      thread: thread,
      coverage: coverage,
      onOpenComment: (fullname) {
        Navigator.pop(sheet);
        onOpenComment(fullname);
      },
    ),
  );
}

class AskThreadSheet extends StatefulWidget {
  const AskThreadSheet({
    super.key,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.thread,
    required this.coverage,
    required this.onOpenComment,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final CitedThread thread;
  final String coverage;
  final void Function(String fullname) onOpenComment;

  @override
  State<AskThreadSheet> createState() => _AskThreadSheetState();
}

class _AskThreadSheetState extends State<AskThreadSheet> {
  static const _starters = [
    'What do most people agree on?',
    'Did OP add anything in the comments?',
    'Any useful links or sources?',
    'What are the strongest counterarguments?',
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <({bool fromUser, String text})>[];
  bool _waiting = false;
  String? _error;
  String? _failedQuestion; // retried by "Try again"

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String question) async {
    question = question.trim();
    if (question.isEmpty || _waiting) return;
    final history = List.of(_messages);
    setState(() {
      _messages.add((fromUser: true, text: question));
      _waiting = true;
      _error = null;
      _failedQuestion = null;
    });
    _input.clear();
    _toBottom();
    try {
      final answer = await AiService.ask(
        baseUrl: widget.baseUrl,
        apiKey: widget.apiKey,
        model: widget.model,
        threadText: widget.thread.text,
        history: history,
        question: question,
      );
      if (!mounted) return;
      setState(() {
        // Citations ([c3]) become links that jump to that comment.
        _messages.add((
          fromUser: false,
          text: AiService.linkCitations(answer, widget.thread.refs)
        ));
        _waiting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast(); // the question goes back into the box
        _input.text = question;
        _waiting = false;
        _error = '$e'.replaceFirst('Exception: ', '');
        _failedQuestion = question;
      });
    }
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: cs.primaryContainer, shape: BoxShape.circle),
                  child: Icon(Icons.forum_rounded,
                      color: cs.onPrimaryContainer, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ask about this thread',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${widget.model} · answers can be wrong',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                      Text(widget.coverage,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                children: [
                  if (_messages.isEmpty && !_waiting) ...[
                    Text(
                        'Answers come only from this post and its comments.',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final q in _starters)
                        ActionChip(label: Text(q), onPressed: () => _send(q)),
                    ]),
                  ],
                  for (final m in _messages)
                    _Bubble(
                        message: m, onOpenComment: widget.onOpenComment),
                  if (_waiting) const _Thinking(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(Icons.error_outline_rounded,
                            color: cs.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_error!,
                                style: TextStyle(color: cs.error))),
                        if (_failedQuestion != null)
                          TextButton(
                              onPressed: () => _send(_failedQuestion!),
                              child: const Text('Try again')),
                      ]),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                // One rounded pill: the field (no underline, no outline) with
                // the send button inside it.
                child: Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(18, 4, 5, 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        textInputAction: TextInputAction.send,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 1,
                        maxLines: 4,
                        onSubmitted: _send,
                        decoration: const InputDecoration.collapsed(
                          hintText: 'Ask anything about this thread…',
                          filled: false,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ValueListenableBuilder(
                      valueListenable: _input,
                      builder: (_, value, __) {
                        final ready =
                            !_waiting && value.text.trim().isNotEmpty;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: ready ? cs.primary : cs.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip: 'Send',
                            padding: EdgeInsets.zero,
                            onPressed: ready ? () => _send(_input.text) : null,
                            icon: Icon(Icons.arrow_upward_rounded,
                                color: ready
                                    ? cs.onPrimary
                                    : cs.onSurfaceVariant.withValues(alpha: 0.6)),
                          ),
                        );
                      },
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// While the AI works: a little reel of comment cards scrolls past while a
/// highlight reads each one, with a pulsing sparkle and a status line that
/// moves from reading to writing. In the spirit of Home's loading deck.
class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  static const _row = 22.0;
  static const _status = [
    'Reading the post…',
    'Going through the comments…',
    'Weighing the replies…',
    'Writing an answer…',
  ];
  static const _widths = [0.9, 0.62, 0.78, 0.5, 0.7];

  late final AnimationController _reel = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  Timer? _step;
  int _phase = 0;
  int _shift = 0; // rows already scrolled past, so the reel never repeats

  @override
  void initState() {
    super.initState();
    _reel.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _shift++);
        _reel.forward(from: 0);
      }
    });
    _step = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (_phase < _status.length - 1) setState(() => _phase++);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _reel.stop();
    } else if (!_reel.isAnimating) {
      _reel.forward();
    }
  }

  @override
  void dispose() {
    _step?.cancel();
    _reel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        width: 250,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedBuilder(
          animation: _reel,
          builder: (_, __) {
            final t = Curves.easeInOutCubic.transform(_reel.value);
            final pulse = 0.5 + 0.5 * math.sin(_reel.value * math.pi);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Transform.scale(
                    scale: 0.85 + 0.25 * pulse,
                    child: Transform.rotate(
                      angle: (_shift + _reel.value) * math.pi / 6,
                      child: Icon(Icons.auto_awesome_rounded,
                          size: 22,
                          color: Color.lerp(cs.primary, cs.tertiary, pulse)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Three rows visible; the middle one is being "read".
                  Expanded(
                    child: SizedBox(
                      height: _row * 3,
                      child: ClipRect(
                        child: Stack(children: [
                          for (var i = 0; i < 4; i++)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (i - t) * _row,
                              height: _row,
                              child: _ReelRow(
                                cs: cs,
                                width: _widths[(i + _shift) % _widths.length],
                                // Highlight lands on the row moving into
                                // the middle slot.
                                focus: i == 2
                                    ? t
                                    : i == 1
                                        ? 1 - t
                                        : 0,
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                              begin: const Offset(0, 0.4), end: Offset.zero)
                          .animate(a),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _status[_phase],
                    key: ValueKey(_phase),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One mini comment in the reel: an avatar dot and a text bar, tinted by
/// [focus] (0–1) while it's the one being read.
class _ReelRow extends StatelessWidget {
  const _ReelRow({required this.cs, required this.width, required this.focus});
  final ColorScheme cs;
  final double width; // fraction of the row the text bar spans
  final double focus;

  @override
  Widget build(BuildContext context) {
    final bar = Color.lerp(cs.surfaceContainerHighest, cs.primary, focus * 0.55)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Color.lerp(cs.surfaceContainerHighest, cs.tertiary, focus),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: width,
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: bar,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onOpenComment});
  final ({bool fromUser, String text}) message;
  final void Function(String fullname) onOpenComment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mine = message.fromUser;
    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(
          color: mine ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: mine
            ? Text(message.text,
                style: TextStyle(color: cs.onPrimaryContainer))
            : RedditMarkdown(
                data: message.text,
                selectable: true,
                onTapLink: (_, href, __) {
                  if (href != null &&
                      href.startsWith(AiService.commentLink)) {
                    onOpenComment(
                        href.substring(AiService.commentLink.length));
                  } else {
                    openLink(context, href);
                  }
                },
              ),
      ),
    );
  }
}
