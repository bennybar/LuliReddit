import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/tap_guard.dart';
import '../../models/post.dart';
import '../history/interest_store.dart';
import 'for_you_learner.dart';
import 'for_you_stores.dart';

/// "Tune For You" for one post: why it's here, and explicit More/Less for
/// its subreddit and its most distinctive topics (one "less" no longer
/// demotes every word of the title), plus mute.
void showTuneSheet(BuildContext context, WidgetRef ref, Post post) {
  HapticFeedback.mediumImpact();
  final messenger = ScaffoldMessenger.of(context);
  void toast(String msg) {
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(msg),
      action: SnackBarAction(
        label: 'Manage',
        onPressed: () => context.push('/manage_for_you'),
      ),
    ));
  }

  // The title's 1–2 most distinctive words: rare ones say more than "help".
  final docFreq = ref.read(docFreqProvider.notifier);
  final topics = (titleKeywords(post.title).toSet().toList()
        ..sort((a, b) => docFreq.idf(b).compareTo(docFreq.idf(a))))
      .take(2)
      .toList();

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Ignore taps briefly so the gesture that opened the sheet can't fall
    // through onto an item.
    builder: (ctx) => TapGuard(
      child: Consumer(builder: (ctx, ref, _) {
        final explicit = ref.watch(explicitPrefsProvider);
        final learner = ref.read(forYouLearnerProvider);
        final sub = post.subreddit;
        final subPref = explicit.subs[sub.toLowerCase()] ?? 0;
        final muted = ref.watch(mutedSubsProvider).contains(sub.toLowerCase());
        final why = ref.watch(forYouMetaProvider)[post.id]?.why;
        final cs = Theme.of(ctx).colorScheme;

        Widget prefTile(String label, IconData icon, bool on, VoidCallback f) =>
            ListTile(
              leading: Icon(icon, color: on ? cs.primary : null),
              title: Text(label),
              trailing: on ? Icon(Icons.check_rounded, color: cs.primary) : null,
              onTap: f,
            );

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text('Tune For You',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                ),
                if (why != null && why.isNotEmpty)
                  ExpansionTile(
                    leading: const Icon(Icons.help_outline_rounded),
                    title: const Text('Why am I seeing this?'),
                    childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in why)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $line',
                              style: TextStyle(color: cs.onSurfaceVariant)),
                        ),
                    ],
                  ),
                prefTile('More from r/$sub', Icons.thumb_up_alt_outlined,
                    subPref > 0, () {
                  learner.subPreference(post, subPref > 0 ? 0 : 1);
                  Navigator.pop(ctx);
                  toast(subPref > 0
                      ? 'Cleared'
                      : "We'll show more from r/$sub");
                }),
                prefTile('Less from r/$sub', Icons.thumb_down_alt_outlined,
                    subPref < 0, () {
                  learner.subPreference(post, subPref < 0 ? 0 : -1);
                  Navigator.pop(ctx);
                  toast(subPref < 0
                      ? 'Cleared'
                      : "We'll show less from r/$sub");
                }),
                for (final t in topics)
                  ListTile(
                    leading: const Icon(Icons.tag_rounded),
                    title: Text('“$t”'),
                    subtitle: const Text('This topic, in any community'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final (v, icon, tip) in [
                        (1, Icons.thumb_up_alt_outlined, 'More about'),
                        (-1, Icons.thumb_down_alt_outlined, 'Less about'),
                      ])
                        IconButton(
                          tooltip: '$tip “$t”',
                          isSelected: explicit.topics[t] == v,
                          color: explicit.topics[t] == v ? cs.primary : null,
                          icon: Icon(icon),
                          onPressed: () {
                            final on = explicit.topics[t] == v;
                            learner.topicPreference(t, on ? 0 : v);
                            Navigator.pop(ctx);
                            toast(on
                                ? 'Cleared'
                                : "We'll show ${v > 0 ? 'more' : 'less'} "
                                    'about “$t”');
                          },
                        ),
                    ]),
                  ),
                ListTile(
                  leading: Icon(muted
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded),
                  title:
                      Text(muted ? 'Unmute r/$sub' : 'Mute r/$sub in For You'),
                  onTap: () {
                    ref.read(mutedSubsProvider.notifier).toggle(sub);
                    Navigator.pop(ctx);
                    toast(muted ? 'r/$sub unmuted' : 'r/$sub muted from For You');
                  },
                ),
              ],
            ),
          ),
        );
      }),
    ),
  );
}
