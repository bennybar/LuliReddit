import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

/// Opens a Giphy search sheet. Returns the chosen GIF URL, or null.
/// Requires the optional Giphy API key entered at login.
Future<String?> showGiphyPicker(BuildContext context, WidgetRef ref) async {
  final key = await ref.read(secureStoreProvider).giphyKey;
  if (!context.mounted) return null;
  if (key == null || key.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Add a Giphy API key (login screen) to use the GIF picker.'),
    ));
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GiphySheet(apiKey: key),
  );
}

class _GiphySheet extends StatefulWidget {
  const _GiphySheet({required this.apiKey});
  final String apiKey;

  @override
  State<_GiphySheet> createState() => _GiphySheetState();
}

class _GiphySheetState extends State<_GiphySheet> {
  final _dio = Dio();
  final _query = TextEditingController();
  List<({String preview, String full})> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load(null); // trending
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load(String? q) async {
    setState(() => _loading = true);
    final path = (q == null || q.isEmpty)
        ? 'https://api.giphy.com/v1/gifs/trending'
        : 'https://api.giphy.com/v1/gifs/search';
    try {
      final res = await _dio.get(path, queryParameters: {
        'api_key': widget.apiKey,
        if (q != null && q.isNotEmpty) 'q': q,
        'limit': 24,
        'rating': 'pg-13',
      });
      final data = (res.data['data'] as List?) ?? const [];
      setState(() {
        _results = [
          for (final g in data)
            (
              preview: (((g as Map)['images'] as Map)['fixed_width']
                  as Map)['url'] as String,
              full: ((g['images'] as Map)['original'] as Map)['url'] as String,
            ),
        ];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _load,
              decoration: const InputDecoration(
                hintText: 'Search GIFs',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: _results.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => Navigator.pop(context, _results[i].full),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: _results[i].preview,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Powered by GIPHY',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
