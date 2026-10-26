import 'package:flutter/material.dart';

import '../../core/redgifs.dart';
import '../../models/post.dart';
import 'media_viewers.dart';

/// Whether "Share as media" applies: images, GIFs, galleries and videos Ilay
/// can download (Reddit-hosted or RedGifs).
bool canShareAsMedia(Post p) => switch (p.type) {
      PostType.image || PostType.gif => true,
      PostType.gallery => p.gallery.isNotEmpty,
      PostType.video => !isExternalVideo(p) &&
          (p.fallbackVideoUrl != null || redgifsId(p.url) != null),
      _ => false,
    };

/// "Share as media": the post's image(s) or video themselves, downloaded and
/// handed to the share sheet, rather than a link.
// TODO(media): port Kotlin's ShareMedia.kt (download to a temp folder with a
// cancellable progress dialog, then share_plus with the files). Until the
// media area lands this only says so.
Future<void> shareAsMedia(BuildContext context, Post post) async {
  ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Sharing as media isn't available yet")));
}
