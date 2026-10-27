import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_icon.dart';
import '../../core/reddit_constants.dart';
import '../../core/widgets/connected_choice.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/loading.dart';
import '../settings/settings_controller.dart';
import 'auth_controller.dart';
import 'auth_repository.dart';
import 'web_login_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _clientId = TextEditingController();
  final _redirect =
      TextEditingController(text: RedditConstants.defaultRedirectUri);
  final _giphy = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _checkResult;
  bool _checkOk = false;
  // Two equal ways in. New users default to the website (Reddit no longer
  // hands out new API keys); someone with a saved Client ID gets the API form.
  bool _useApi = false;

  @override
  void initState() {
    super.initState();
    // The RedReader note and setup steps follow the redirect as it's typed.
    _redirect.addListener(() => setState(() {}));
    _prefill();
  }

  Future<void> _prefill() async {
    final store = ref.read(secureStoreProvider);
    final id = await store.clientId;
    final redirect = await store.redirectUri;
    final giphy = await store.giphyKey;
    if (!mounted) return;
    setState(() {
      if (id != null) _clientId.text = id;
      if (id != null && id.trim().isNotEmpty) _useApi = true;
      if (redirect != null) _redirect.text = redirect;
      if (giphy != null) _giphy.text = giphy;
    });
  }

  @override
  void dispose() {
    _clientId.dispose();
    _redirect.dispose();
    _giphy.dispose();
    super.dispose();
  }

  Future<void> _checkConfig() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _checkResult = null;
    });
    final result =
        await ref.read(authRepositoryProvider).validateClientId(_clientId.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _checkOk = result.valid;
      _checkResult = result.message;
    });
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (_clientId.text.trim().isEmpty) {
      setState(() => _error = 'Enter your Reddit Client ID first.');
      return;
    }
    if (_redirect.text.trim().isEmpty) {
      setState(() => _error = 'A Redirect URI is required.');
      return;
    }
    if (!_redirect.text.trim().contains('://')) {
      setState(() => _error =
          'The Redirect URI looks invalid — it should look like ${RedditConstants.defaultRedirectUri}');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    // Pre-flight: confirm the client id is a valid installed-app credential
    // before launching the browser, so we can give a precise error.
    final check = await ref
        .read(authRepositoryProvider)
        .validateClientId(_clientId.text);
    if (!check.valid) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = check.message;
      });
      return;
    }

    // Persist credentials early so a retry keeps them.
    await ref.read(secureStoreProvider).saveCredentials(
          clientId: _clientId.text.trim(),
          redirectUri: _redirect.text.trim(),
          giphyKey: _giphy.text.trim(),
        );

    try {
      await ref.read(authControllerProvider.notifier).login(
            clientId: _clientId.text.trim(),
            redirectUri: _redirect.text.trim(),
          );
      // Router redirects to '/' automatically on success.
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Login failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            // Brand
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppIconPreview(
                  AppIcon.parse(ref.watch(settingsControllerProvider
                      .select((s) => s.appIcon))),
                  size: 72),
            ),
            const SizedBox(height: 20),
            Text('Ilay for Reddit',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              "Sign in with your Reddit account. Both ways work the same once "
              "you're in.",
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),

            ConnectedChoice<bool>(
              options: const [(false, 'Reddit website'), (true, 'API key')],
              selected: _useApi,
              onSelect: (v) => setState(() {
                _useApi = v;
                _error = null;
              }),
              icon: (v) => v ? Icons.key_rounded : Icons.public_rounded,
            ),
            const SizedBox(height: 20),
            if (!_useApi) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sign in on reddit.com',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        "Reddit's own sign-in page opens inside Ilay. No API key "
                        'needed, and your password goes only to Reddit.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "This uses the website rather than Reddit's official "
                        'API. It can stop working if Reddit changes its site, '
                        'and Reddit could treat it as against its usage policy.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _Banner(ok: false, text: _error!),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _webLogin,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Sign in with Reddit'),
              ),
            ] else ...[
                _SetupCard(redirectUri: _redirect.text),
                const SizedBox(height: 20),

                _Field(
                  controller: _clientId,
                  label: 'Reddit Client ID',
                  hint: 'e.g. AbCdEf123...',
                  icon: Icons.key_rounded,
                  suffix: IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      final txt = data?.text?.trim();
                      if (txt != null && txt.isNotEmpty) {
                        setState(() => _clientId.text = txt);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _Field(
                  controller: _redirect,
                  label: 'Redirect URI',
                  hint: RedditConstants.defaultRedirectUri,
                  icon: Icons.link_rounded,
                  helper:
                      'Must match the redirect URI registered on your Reddit app.',
                ),
                // A RedReader-issued client ID only redirects to RedReader's URI.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Using a RedReader client ID?'),
                    onPressed: () =>
                        _redirect.text = RedditConstants.redReaderRedirectUri,
                  ),
                ),
                if (_redirect.text.trim().startsWith('redreader:'))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'If RedReader is also installed, Android will ask which app '
                      'should finish signing in. Pick Ilay. This client ID was '
                      'issued to RedReader, and Reddit could revoke it.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 4),
                _Field(
                  controller: _giphy,
                  label: 'Giphy API Key (optional)',
                  hint: 'Enables GIF picker',
                  icon: Icons.gif_box_rounded,
                ),

                if (_checkResult != null) ...[
                  const SizedBox(height: 16),
                  _Banner(
                    ok: _checkOk,
                    text: _checkResult!,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _Banner(ok: false, text: _error!),
                ],

                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _checkConfig,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Test configuration'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? const Loading.onContent()
                      : const Icon(Icons.login_rounded),
                  label: Text(_busy ? 'Working…' : 'Connect Reddit account'),
                ),
              const SizedBox(height: 8),
              // Read-only browsing uses the same Client ID.
              TextButton.icon(
                onPressed: _busy ? null : _browseAnonymously,
                icon: const Icon(Icons.travel_explore_rounded),
                label: const Text('Browse without signing in'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Read-only browsing with just a Client ID (Reddit refuses anonymous
  /// requests without one). Voting, commenting and the inbox need an account.
  Future<void> _browseAnonymously() async {
    FocusScope.of(context).unfocus();
    if (_clientId.text.trim().isEmpty) {
      setState(() => _error =
          'Browsing without an account still needs a Reddit Client ID — '
          'enter it above.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .browseAnonymously(_clientId.text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Website-session login (no API key): a Reddit login page inside Ilay,
  /// which stores the session itself. Its caveat is shown in the panel.
  Future<void> _webLogin() async {
    final cookie = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const WebLoginScreen()),
    );
    if (cookie == null || cookie.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).loginWithWebSession(cookie);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.redirectUri});
  final String redirectUri;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24))),
          leading: Icon(Icons.help_outline_rounded, color: cs.primary),
          title: const Text('How to get your Client ID'),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            const _Step(1, 'Open reddit.com/prefs/apps and tap "create app".'),
            const _Step(2, 'Choose the "installed app" type (no secret needed).'),
            _Step(3, 'Set the redirect URI to exactly:  $redirectUri'),
            const _Step(4,
                'Create it. The Client ID is the string just under the app name.'),
            const _Step(5, 'Paste that Client ID below and connect.'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://www.reddit.com/prefs/apps'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open Reddit app settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.text);
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: cs.secondaryContainer,
            child: Text('$n',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.onSecondaryContainer)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
          if (text.contains(RedditConstants.callbackScheme))
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () => Clipboard.setData(
                  const ClipboardData(text: RedditConstants.defaultRedirectUri)),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.helper,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? helper;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.ok, required this.text});
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = ok ? cs.primaryContainer : cs.errorContainer;
    final fg = ok ? cs.onPrimaryContainer : cs.onErrorContainer;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
              color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg))),
        ],
      ),
    );
  }
}
