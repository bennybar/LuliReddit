import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// In-app content & conduct policy (EULA). Required for app-store distribution
/// of an app that surfaces user-generated content.
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget h(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
          child: Text(t,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
        );
    Widget p(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(t, style: const TextStyle(height: 1.45)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Content & conduct policy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          p('Luli is an independent, third-party client for Reddit. It is not '
              'made by, endorsed by, or affiliated with Reddit, Inc. All content '
              'is hosted by Reddit and provided through your own Reddit account.'),
          h('No tolerance for objectionable content'),
          p('By using Luli you agree not to use it to post, share, or promote '
              'content that is illegal, abusive, harassing, hateful, sexually '
              'exploitative, or otherwise objectionable. There is zero tolerance '
              'for objectionable content or abusive users.'),
          h('Reporting and moderation'),
          p('You can report any post or comment from its menu, block users so you '
              'no longer see their content or messages, and hide posts. Reports '
              'are sent to Reddit and the relevant subreddit moderators, who '
              'review and act on them. Where you moderate, you can remove content '
              'directly.'),
          h('Reddit rules apply'),
          p('All activity is also governed by Reddit\'s Content Policy and User '
              'Agreement. Violations may be actioned by Reddit independently of '
              'this app.'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 16, children: [
              TextButton(
                onPressed: () => launchUrl(
                    Uri.parse('https://www.redditinc.com/policies/content-policy'),
                    mode: LaunchMode.externalApplication),
                child: const Text('Reddit Content Policy'),
              ),
              TextButton(
                onPressed: () => launchUrl(
                    Uri.parse('https://www.redditinc.com/policies/user-agreement'),
                    mode: LaunchMode.externalApplication),
                child: const Text('Reddit User Agreement'),
              ),
            ]),
          ),
          h('Adult content'),
          p('Mature (NSFW) content is off by default and blurred until revealed. '
              'By enabling it you confirm you are of legal age to view such '
              'content in your jurisdiction.'),
          h('Your data'),
          p('Luli stores your API credentials, tokens, history, and settings only '
              'on this device. It has no servers and sends nothing anywhere except '
              'directly to Reddit. To remove your data, use "Clear all data" in '
              'settings; to delete your Reddit account, visit Reddit\'s settings.'),
          h('No warranty'),
          p('Luli is provided "as is", without warranty of any kind. You use it at '
              'your own risk.'),
        ],
      ),
    );
  }
}
