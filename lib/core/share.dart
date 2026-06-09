import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet for a URL (post permalink, subreddit, media …).
Future<void> shareUrl(String url, {String? subject}) async {
  if (subject != null && subject.isNotEmpty) {
    await Share.share(url, subject: subject);
  } else {
    await Share.shareUri(Uri.parse(url));
  }
}
