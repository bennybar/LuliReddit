import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/deep_links.dart';
import '../../core/widgets/loading.dart';

/// A Reddit link shared to Ilay from another app: resolves a share link
/// (/r/<sub>/s/<code>) to the real post, then opens it on top of Home.
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
    _open();
  }

  Future<void> _open() async {
    final target = isShareLink(widget.url)
        ? await resolveShareLink(widget.url)
        : widget.url;
    if (!mounted) return;
    final route = target == null ? null : routeForRedditUrl(target);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Home first, then the post pushed over it: back (or a swipe) goes Home.
    router.go('/');
    if (route == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't open that link")));
      return;
    }
    if (widget.summarize) summarizeOnOpen = postIdInRoute(route);
    await WidgetsBinding.instance.endOfFrame;
    router.push(route);
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Loading()));
}
