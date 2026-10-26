import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/connected_choice.dart';
import '../../core/widgets/error_view.dart';
import '../auth/auth_controller.dart';
import '../home/account_tab.dart' show createMulti;
import 'multireddit_providers.dart';

/// Every custom feed of yours, in one list (Explore's row gets long).
class CustomFeedsScreen extends ConsumerStatefulWidget {
  const CustomFeedsScreen({super.key});

  @override
  ConsumerState<CustomFeedsScreen> createState() => _CustomFeedsScreenState();
}

class _CustomFeedsScreenState extends ConsumerState<CustomFeedsScreen> {
  @override
  void initState() {
    super.initState();
    // Fresh on open (a feed may have changed on the website).
    Future.microtask(() => ref.invalidate(myMultiredditsProvider));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final username = ref.watch(
            authControllerProvider.select((a) => a.valueOrNull?.username)) ??
        '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom feeds'),
        actions: [
          IconButton(
            tooltip: 'New feed',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => createMulti(context, ref, username),
          ),
        ],
      ),
      body: ref.watch(myMultiredditsProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                    "Couldn't load your custom feeds: ${friendlyError(e)}"),
              ),
            ),
            data: (multis) => multis.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('No custom feeds yet. A custom feed '
                              'mixes the communities you pick into one '
                              'feed.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () =>
                                createMulti(context, ref, username),
                            child: const Text('New feed'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: multis.length,
                    itemBuilder: (_, i) {
                      final m = multis[i];
                      final owner = m.owner(username);
                      final privacy =
                          m.visibility == 'public' ? 'Public' : 'Private';
                      return ListTile(
                        key: ValueKey(m.path.isEmpty ? m.name : m.path),
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: cs.tertiaryContainer,
                          foregroundColor: cs.onTertiaryContainer,
                          child:
                              const Icon(Icons.dynamic_feed_rounded, size: 20),
                        ),
                        title: Text(
                            m.displayName.isEmpty ? m.name : m.displayName),
                        subtitle: Text(
                            '${m.subreddits.length} communities · $privacy'),
                        trailing: IconButton(
                          tooltip: 'Manage',
                          icon: const Icon(Icons.tune_rounded),
                          onPressed: () =>
                              context.push('/m/$owner/${m.name}/manage'),
                        ),
                        onTap: () => context.push('/m/$owner/${m.name}'),
                      );
                    },
                  ),
          ),
    );
  }
}

/// A custom feed's name, description and visibility, from [editFeedDialog].
class FeedEdit {
  const FeedEdit(this.displayName, this.description, this.visibility);
  final String displayName;
  final String description;
  final String visibility;
}

/// Name, description and Public / Private for a custom feed ([title]: Edit /
/// Copy).
Future<FeedEdit?> editFeedDialog(BuildContext context,
    {required String title,
    required String confirm,
    required String name,
    required String description,
    required String visibility}) {
  return showDialog<FeedEdit>(
    context: context,
    builder: (_) => _EditFeedDialog(
        title: title,
        confirm: confirm,
        name: name,
        description: description,
        visibility: visibility),
  );
}

class _EditFeedDialog extends StatefulWidget {
  const _EditFeedDialog({
    required this.title,
    required this.confirm,
    required this.name,
    required this.description,
    required this.visibility,
  });
  final String title;
  final String confirm;
  final String name;
  final String description;
  final String visibility;

  @override
  State<_EditFeedDialog> createState() => _EditFeedDialogState();
}

class _EditFeedDialogState extends State<_EditFeedDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _description = TextEditingController(text: widget.description);
  late String _visibility = widget.visibility;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border =
        OutlineInputBorder(borderRadius: BorderRadius.circular(18));
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration:
                  InputDecoration(labelText: 'Name', border: border),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: null,
              decoration: InputDecoration(
                  labelText: 'Description (optional)', border: border),
            ),
            const SizedBox(height: 10),
            ConnectedChoice<String>(
              options: const [('private', 'Private'), ('public', 'Public')],
              selected: _visibility,
              onSelect: (v) => setState(() => _visibility = v),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  _visibility == 'public'
                      ? 'Anyone with the link can see it, follow it or copy '
                          'it.'
                      : 'Only you can see it.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  FeedEdit(_name.text.trim(), _description.text.trim(),
                      _visibility)),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
