import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feed/content_filters.dart';

/// Manage content filters: keywords (title), domains, and flairs that hide
/// matching posts across all feeds.
class ContentFiltersScreen extends ConsumerWidget {
  const ContentFiltersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(contentFiltersProvider);
    final ctrl = ref.read(contentFiltersProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Content filters')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Hide posts that match these. Filters are stored only on this '
              'device and apply to every feed.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          _FilterSection(
            title: 'Title keywords',
            hint: 'e.g. spoiler',
            type: 'keyword',
            values: filters.keywords,
            onAdd: (v) => ctrl.add('keyword', v),
            onRemove: (v) => ctrl.remove('keyword', v),
          ),
          _FilterSection(
            title: 'Domains',
            hint: 'e.g. twitter.com',
            type: 'domain',
            values: filters.domains,
            onAdd: (v) => ctrl.add('domain', v),
            onRemove: (v) => ctrl.remove('domain', v),
          ),
          _FilterSection(
            title: 'Flairs',
            hint: 'e.g. Politics',
            type: 'flair',
            values: filters.flairs,
            onAdd: (v) => ctrl.add('flair', v),
            onRemove: (v) => ctrl.remove('flair', v),
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends StatefulWidget {
  const _FilterSection({
    required this.title,
    required this.hint,
    required this.type,
    required this.values,
    required this.onAdd,
    required this.onRemove,
  });
  final String title;
  final String hint;
  final String type;
  final List<String> values;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<_FilterSection> createState() => _FilterSectionState();
}

class _FilterSectionState extends State<_FilterSection> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    widget.onAdd(_ctrl.text);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Text(widget.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.primary, fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _add, child: const Text('Add')),
            ],
          ),
        ),
        if (widget.values.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final v in widget.values)
                  InputChip(
                    label: Text(v),
                    onDeleted: () => widget.onRemove(v),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
