import 'package:flutter/material.dart';

import '../../core/route_observer.dart';
import '../../core/widgets/loading.dart';
import '../../models/listing.dart';
import '../../core/widgets/error_view.dart';

/// Generic infinite-scroll list backed by a `fetch(after)` callback.
class PagedList<T> extends StatefulWidget {
  const PagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.padding = const EdgeInsets.fromLTRB(10, 8, 10, 130),
    this.emptyLabel = 'Nothing here',
    this.staleAfter = const Duration(minutes: 5),
    this.nested = false,
  });

  final Future<Listing<T>> Function(String? after) fetch;
  final Widget Function(BuildContext, T) itemBuilder;
  final EdgeInsets padding;
  final String emptyLabel;
  // How old the list may get before returning to it reloads it.
  final Duration staleAfter;
  // In a NestedScrollView's body: scrolls with it (its controller), so the
  // header above collapses.
  final bool nested;

  @override
  State<PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<PagedList<T>> with RouteAware {
  final _scroll = ScrollController();
  final _items = <T>[];
  String? _after;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  DateTime _lastLoaded = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  /// Returning to this list after a pushed route is popped: silently refresh if
  /// the data has gone stale (no full-screen spinner, keeps the user's place).
  @override
  void didPopNext() {
    if (!_loading &&
        DateTime.now().difference(_lastLoaded) > widget.staleAfter) {
      _load(silent: true);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final listing = await widget.fetch(null);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(listing.items);
        _after = listing.after;
        _loading = false;
        _lastLoaded = DateTime.now();
      });
    } catch (e) {
      // A silent (stale) refresh failing shouldn't blow away the list.
      if (mounted && !silent) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _after == null || _after!.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final listing = await widget.fetch(_after);
      if (!mounted) return;
      setState(() {
        _items.addAll(listing.items);
        _after = listing.after;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: Loading());
    if (_error != null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Text('Could not load.\n${friendlyError(_error)}',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      ]);
    }
    if (_items.isEmpty) {
      return RefreshBox(
        onRefresh: _load,
        child: ListView(children: [
          const SizedBox(height: 120),
          Center(child: Text(widget.emptyLabel)),
        ]),
      );
    }
    return RefreshBox(
      onRefresh: _load,
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) {
          if (n.depth == 0 &&
              n.metrics.axis == Axis.vertical &&
              n.metrics.pixels >= n.metrics.maxScrollExtent - 500) {
            _loadMore();
          }
          return false;
        },
        child: ListView.separated(
        controller: widget.nested ? null : _scroll,
        padding: widget.padding,
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            return _loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Loading()))
                : const SizedBox.shrink();
          }
          return widget.itemBuilder(context, _items[i]);
        },
        ),
      ),
    );
  }
}
