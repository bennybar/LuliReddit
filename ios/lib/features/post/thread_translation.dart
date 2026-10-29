import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/translate.dart';
import '../../models/comment.dart';
import '../settings/settings_controller.dart';
import 'comment_tree.dart';
import 'comments_controller.dart';

/// A thread's translation: whether it's offered ([canTranslate]: the thread
/// isn't in the phone's language and the phone can translate it), and the
/// translated post ("title", "body") and comment (fullname) texts while
/// shown ([shown]; null: the original).
class ThreadTranslationState {
  const ThreadTranslationState(
      {this.canTranslate = false, this.shown, this.translating = false});
  final bool canTranslate;
  final Map<String, String>? shown;
  final bool translating;

  ThreadTranslationState copyWith(
          {bool? canTranslate,
          Map<String, String>? Function()? shown,
          bool? translating}) =>
      ThreadTranslationState(
        canTranslate: canTranslate ?? this.canTranslate,
        shown: shown == null ? this.shown : shown(),
        translating: translating ?? this.translating,
      );
}

/// Per thread (the comments controller's key). The screen hands it each
/// loaded thread ([onThread]).
final threadTranslationProvider = StateNotifierProvider.autoDispose
    .family<ThreadTranslation, ThreadTranslationState, String>(
        (ref, key) => ThreadTranslation(ref));

class ThreadTranslation extends StateNotifier<ThreadTranslationState> {
  ThreadTranslation(this.ref) : super(const ThreadTranslationState());
  final Ref ref;

  String? _language; // the thread's, once detected
  bool _detecting = false;
  PostThread? _thread;
  // Every text translated so far, kept while the original is shown.
  final _texts = <String, String>{};

  /// A thread (re)loaded or grown (more comments): the first one is checked
  /// for its language (Settings → Auto-translate translates it right away);
  /// while shown translated, new comments are translated too.
  void onThread(PostThread thread) {
    _thread = thread;
    if (_language == null && !_detecting) {
      _detect(thread);
    } else if (state.shown != null) {
      _translate();
    }
  }

  Future<void> _detect(PostThread t) async {
    _detecting = true;
    // The post and its first comments: a title alone is too short to be sure.
    final sample = [
      t.post.title,
      t.post.selftext,
      for (final c in t.comments.where((c) => !c.isMore).take(5)) c.body,
    ].join('\n');
    final lang = await Translate.detect(sample);
    if (lang == null || !await Translate.canTranslate(lang) || !mounted) return;
    _language = lang;
    state = state.copyWith(canTranslate: true);
    if (ref.read(settingsControllerProvider).autoTranslate) _translate();
  }

  /// Translate / Show original.
  void toggle() {
    if (state.shown != null) {
      state = state.copyWith(shown: () => null);
    } else {
      _translate();
    }
  }

  Future<void> _translate() async {
    final from = _language;
    final t = _thread;
    if (from == null || t == null || state.translating) return;
    final missing = <String, String>{
      if (!_texts.containsKey('title')) 'title': t.post.title,
      if (!_texts.containsKey('body') && t.post.selftext.isNotEmpty)
        'body': t.post.selftext,
      for (final Comment c in CommentTree.flatten(t.comments, const {}))
        if (!c.isMore && !_texts.containsKey(c.fullname) && c.body.isNotEmpty)
          c.fullname: c.body,
    };
    if (missing.isEmpty) {
      state = state.copyWith(shown: () => Map.of(_texts));
      return;
    }
    state = state.copyWith(translating: true);
    final out = await Translate.translate(missing.values.toList(), from);
    if (!mounted) return;
    if (out == null) {
      state = state.copyWith(translating: false);
      return;
    }
    final keys = missing.keys.toList();
    for (var i = 0; i < keys.length && i < out.length; i++) {
      _texts[keys[i]] = out[i];
    }
    state = state.copyWith(translating: false, shown: () => Map.of(_texts));
  }
}

/// [t] with [texts] (ThreadTranslationState.shown) in place of the original
/// post and comment texts.
PostThread translatedThread(PostThread t, Map<String, String>? texts) {
  if (texts == null) return t;
  Comment tr(Comment c) => c.isMore
      ? c
      : c.copyWith(
          body: texts[c.fullname] ?? c.body,
          replies: c.replies.map(tr).toList());
  return PostThread(
    post: t.post.copyWith(
        title: texts['title'] ?? t.post.title,
        selftext: texts['body'] ?? t.post.selftext),
    comments: t.comments.map(tr).toList(),
    collapsed: t.collapsed,
    loadingMore: t.loadingMore,
  );
}
