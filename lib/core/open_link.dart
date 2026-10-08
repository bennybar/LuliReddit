import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/media/media_viewers.dart';
import '../features/settings/settings_controller.dart';
import 'deep_links.dart';
import 'media_links.dart';

/// Opens a link from Reddit content the way a Reddit client should: media in
/// the viewer, reddit.com links in the app, anything else in the browser
/// (in-app Custom Tab or external, per Settings).
///
/// Relative links (`/r/foo`, `/u/bar`, plain `r/foo`) are resolved against
/// reddit.com; they used to fail silently.
void openLink(BuildContext context, String? href) {
  if (href == null || href.trim().isEmpty) return;
  var raw = href.trim();
  if (raw.startsWith('/')) {
    raw = 'https://www.reddit.com$raw';
  } else if (RegExp(r'^(r|u|user)/').hasMatch(raw)) {
    raw = 'https://www.reddit.com/$raw';
  }
  final uri = Uri.tryParse(raw);
  if (uri == null) return;
  if (isVideoUrl(uri)) {
    openVideoViewer(context, resolveVideoUrl(raw), externalUrl: raw);
    return;
  }
  if (isImageUrl(uri)) {
    openImageViewer(context, raw);
    return;
  }
  final route = routeForRedditUrl(uri);
  if (route != null) {
    context.push(route);
    return;
  }
  openInBrowser(context, uri);
}

/// Opens [uri] in a browser: an in-app Custom Tab when the user turned that on
/// in Settings, else their default browser app.
void openInBrowser(BuildContext context, Uri uri) {
  final inApp = ProviderScope.containerOf(context, listen: false)
      .read(settingsControllerProvider)
      .inAppBrowser;
  launchUrl(uri,
      mode: inApp
          ? LaunchMode.inAppBrowserView
          : LaunchMode.externalApplication);
}
