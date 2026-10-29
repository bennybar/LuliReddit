import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/translate.dart';
import '../../models/comment.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';
import 'comment_tree.dart';
import 'comments_controller.dart';

/// A thread's translation: the languages Translate offers ([targets]: the
/// phone's and Settings → Second language, minus the thread's own), and the
/// translated post ("title", "body") and comment (fullname) texts while
/// shown in [shownIn] ([shown]; null: the original).
class ThreadTranslationState {
  const ThreadTranslationState(
      {this.targets = const [],
      this.shown,
      this.shownIn,
      this.translating = false});
  final List<String> targets;
  final Map<String, String>? shown;
  final String? shownIn;
  final bool translating;

  ThreadTranslationState copyWith(
          {List<String>? targets,
          (Map<String, String>?, String?)? shown,
          bool? translating}) =>
      ThreadTranslationState(
        targets: targets ?? this.targets,
        shown: shown == null ? this.shown : shown.$1,
        shownIn: shown == null ? shownIn : shown.$2,
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
  // Every text translated so far, per language, kept while the original is
  // shown.
  final _texts = <String, Map<String, String>>{};

  /// A thread (re)loaded or grown (more comments): the first one is checked
  /// for its language; while shown translated, new comments are translated
  /// too.
  void onThread(PostThread thread) {
    _thread = thread;
    if (_language == null && !_detecting) {
      _detect(thread);
    } else if (state.shownIn case final to?) {
      _translate(to);
    }
  }

  /// Offers Translate into the phone's language and the second one. With
  /// Settings → Auto-translate, a thread in neither opens translated into
  /// the phone's.
  Future<void> _detect(PostThread t) async {
    _detecting = true;
    // The post and its first comments: a title alone is too short to be sure.
    final sample = [
      t.post.title,
      t.post.selftext,
      for (final c in t.comments.where((c) => !c.isMore).take(5)) c.body,
    ].join('\n');
    final lang = await Translate.detect(sample);
    if (lang == null || !mounted) return;
    final s = ref.read(settingsControllerProvider);
    final targets =
        await Translate.targets(lang, s, ref.read(secureStoreProvider));
    if (targets.isEmpty || !mounted) return;
    _language = lang;
    state = state.copyWith(targets: targets);
    if (s.autoTranslate &&
        lang != s.translateSecondLanguage &&
        targets.contains(Translate.primary)) {
      _translate(Translate.primary);
    }
  }

  /// Shows the thread in [to], or the original when null.
  void translateTo(String? to) {
    if (to == null) {
      state = state.copyWith(shown: (null, null));
    } else {
      _translate(to);
    }
  }

  /// Error text for the screen to show once (Reddit-style snack).
  String? error;

  Future<void> _translate(String to) async {
    final from = _language;
    final t = _thread;
    if (from == null || t == null || state.translating) return;
    final texts = _texts.putIfAbsent(to, () => {});
    final missing = <String, String>{
      if (!texts.containsKey('title')) 'title': t.post.title,
      if (!texts.containsKey('body') && t.post.selftext.isNotEmpty)
        'body': t.post.selftext,
      for (final Comment c in CommentTree.flatten(t.comments, const {}))
        if (!c.isMore && !texts.containsKey(c.fullname) && c.body.isNotEmpty)
          c.fullname: c.body,
    };
    if (missing.isEmpty) {
      state = state.copyWith(shown: (Map.of(texts), to));
      return;
    }
    state = state.copyWith(translating: true);
    List<String>? out;
    try {
      out = await Translate.translate(missing.values.toList(), from, to,
          ref.read(settingsControllerProvider), ref.read(secureStoreProvider));
      if (out == null) error = "Couldn't translate this post";
    } catch (e) {
      error = "Couldn't translate: ${'$e'.replaceFirst('Exception: ', '')}";
    }
    if (!mounted) return;
    if (out == null) {
      state = state.copyWith(translating: false);
      return;
    }
    final keys = missing.keys.toList();
    for (var i = 0; i < keys.length && i < out.length; i++) {
      texts[keys[i]] = out[i];
    }
    state = state.copyWith(translating: false, shown: (Map.of(texts), to));
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
