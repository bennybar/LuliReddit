import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/deep_links.dart';
import '../../core/widgets/loading.dart';

/// A share link (/r/<sub>/s/<code>) shared to Ilay from another app: resolves
/// it to the real post, then opens that in its place.
class SharedLinkScreen extends StatefulWidget {
  const SharedLinkScreen(
      {super.key, required this.url, required this.summarize});

  final Uri url;
  final bool summarize;

  @override
  State<SharedLinkScreen> createState() => _SharedLinkScreenState();
}

class _SharedLinkScreenState extends State<SharedLinkScreen> {
  @override
  void initState() {
    super.initState();
    resolveShareLink(widget.url).then((target) {
      if (!mounted) return;
      final route = target == null ? null : routeForRedditUrl(target);
      if (route == null) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't open that link")));
        return;
      }
      if (widget.summarize) summarizeOnOpen = postIdInRoute(route);
      context.go(route);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Loading()));
}
