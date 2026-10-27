import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../core/reddit_constants.dart';
import '../../core/storage/secure_store.dart';

/// Outcome of validating that an entered client id is correctly configured at
/// Reddit (exists + is an "installed app" type credential).
class ConfigCheckResult {
  const ConfigCheckResult.ok()
      : valid = true,
        message = 'Client ID is valid and registered as an installed app.';
  const ConfigCheckResult.failed(this.message) : valid = false;

  final bool valid;
  final String message;
}

/// Thrown during the interactive login with a human-readable, actionable message.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository(this._store, [Dio? dio]) : _dio = dio ?? Dio();

  final SecureStore _store;
  final Dio _dio;

  // A fixed, opaque CSRF state value checked on the redirect.
  static const _state = 'luli_oauth_state';

  String _basicAuth(String clientId) =>
      'Basic ${base64.encode(utf8.encode('$clientId:'))}';

  /// Pre-flight check: confirms the client id exists at Reddit AND is an
  /// installed-app credential (the only correct type for this app — it has no
  /// client secret). Does not validate the redirect URI; that is checked by
  /// Reddit during the browser authorize step.
  Future<ConfigCheckResult> validateClientId(String clientId) async {
    if (clientId.trim().isEmpty) {
      return const ConfigCheckResult.failed('Enter your Reddit Client ID.');
    }
    try {
      final res = await _dio.post(
        RedditConstants.accessTokenUrl,
        data: {
          'grant_type': RedditConstants.installedClientGrant,
          'device_id': RedditConstants.validationDeviceId,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Authorization': _basicAuth(clientId.trim()),
            'User-Agent': RedditConstants.userAgent(null),
          },
          validateStatus: (_) => true,
        ),
      );
      if (res.statusCode == 200 && res.data is Map && res.data['access_token'] != null) {
        return const ConfigCheckResult.ok();
      }
      if (res.statusCode == 401) {
        return const ConfigCheckResult.failed(
          'Reddit rejected this Client ID (401). Check that you copied the ID '
          'shown under your app name at reddit.com/prefs/apps, and that the app '
          'type is "installed app" (no secret).',
        );
      }
      return ConfigCheckResult.failed(
        'Unexpected response from Reddit (HTTP ${res.statusCode}). '
        'Verify the app exists and is an installed app.',
      );
    } on DioException catch (e) {
      return ConfigCheckResult.failed(
        'Could not reach Reddit to validate the Client ID: ${e.message}',
      );
    }
  }

  /// Full interactive login. Validates the redirect URI implicitly: if it is not
  /// registered on the Reddit app, Reddit returns an error on the redirect.
  /// Persists tokens + username on success and returns the username.
  Future<String> login({
    required String clientId,
    required String redirectUri,
    bool ephemeral = false,
  }) async {
    clientId = clientId.trim();
    redirectUri = redirectUri.trim();

    // The browser only returns to us on a scheme the app listens for; any
    // other one would surface as a confusing "cancelled" login.
    final scheme = Uri.tryParse(redirectUri)?.scheme.toLowerCase() ?? '';
    if (!RedditConstants.callbackSchemes.contains(scheme)) {
      throw AuthException(
        'Redirect URIs starting with "$scheme://" aren\'t supported. Use '
        '${RedditConstants.defaultRedirectUri}, or '
        '${RedditConstants.redReaderRedirectUri} with a RedReader client ID.',
      );
    }

    final authUri = Uri.parse(RedditConstants.authorizeUrl).replace(
      queryParameters: {
        'client_id': clientId,
        'response_type': RedditConstants.responseType,
        'state': _state,
        'redirect_uri': redirectUri,
        'duration': RedditConstants.duration,
        'scope': RedditConstants.scope,
      },
    );

    final String resultUrl;
    try {
      resultUrl = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: scheme,
        // Ephemeral = don't reuse the browser's Reddit cookies, so adding a
        // second account lets you sign into a *different* account.
        options: FlutterWebAuth2Options(preferEphemeral: ephemeral),
      );
    } catch (e) {
      throw AuthException('Login was cancelled or the browser failed: $e');
    }

    final returned = Uri.parse(resultUrl);
    final error = returned.queryParameters['error'];
    if (error != null) {
      if (error == 'access_denied') {
        throw AuthException('You declined the authorization request.');
      }
      throw AuthException(
        'Reddit returned an error: "$error". This usually means the Redirect '
        'URI does not exactly match the one registered at reddit.com/prefs/apps. '
        'It must be exactly: $redirectUri',
      );
    }
    if (returned.queryParameters['state'] != _state) {
      throw AuthException('Security check failed (state mismatch). Try again.');
    }
    final code = returned.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw AuthException('No authorization code was returned by Reddit.');
    }

    // Exchange the code for tokens.
    final Response res;
    try {
      res = await _dio.post(
        RedditConstants.accessTokenUrl,
        data: {
          'grant_type': RedditConstants.grantTypeAuthorizationCode,
          'code': code,
          'redirect_uri': redirectUri,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Authorization': _basicAuth(clientId),
            'User-Agent': RedditConstants.userAgent(null),
          },
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw AuthException('Failed to exchange the login code: ${e.message}');
    }

    if (res.statusCode != 200 || res.data is! Map) {
      throw AuthException(
        'Token exchange failed (HTTP ${res.statusCode}). The Redirect URI may '
        'not match the registered value: $redirectUri',
      );
    }
    final data = res.data as Map;
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    if (accessToken == null) {
      throw AuthException('Reddit did not return an access token.');
    }

    // Resolve the account before saving anything: a login without a username
    // used to be stored as a placeholder "redditor" account that broke on the
    // next resume.
    final username = await _fetchUsername(accessToken) ??
        await _fetchUsername(accessToken);
    if (username == null) {
      throw AuthException(
          "Signed in, but couldn't load your Reddit username. Check your "
          'connection and try again.');
    }

    await _store.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiry: DateTime.now().add(Duration(seconds: expiresIn - 60)),
    );
    await _store.saveUsername(username);
    await _store.saveCredentials(clientId: clientId, redirectUri: redirectUri);
    return username;
  }

  /// Website-session login (no API key). The UI captures reddit.com cookies via
  /// a WebView; here we verify them by fetching the logged-in user's info (which
  /// also yields the `modhash` used for write actions) and persist the session.
  Future<({String username, String? modhash})> completeWebLogin(
      String cookie) async {
    Response res;
    try {
      res = await _dio.get(
        '${RedditConstants.webApiBase}/api/me.json',
        options: Options(
          headers: {
            'cookie': cookie,
            'User-Agent': RedditConstants.webUserAgent,
          },
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw AuthException('Could not reach Reddit: ${e.message}');
    }
    dynamic body = res.data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } catch (_) {}
    }
    final data = body is Map ? body['data'] : null;
    final username = data is Map ? data['name'] as String? : null;
    final modhash = data is Map ? data['modhash'] as String? : null;
    if (username == null || username.isEmpty) {
      throw AuthException(
          'Reddit login didn\'t complete. Please finish signing in and try again.');
    }
    await _store.saveWebSession(
        username: username, cookie: cookie, modhash: modhash);
    return (username: username, modhash: modhash);
  }

  Future<String?> _fetchUsername(String accessToken) async {
    try {
      final res = await _dio.get(
        '${RedditConstants.oauthApiBase}/api/v1/me',
        options: Options(headers: {
          'Authorization': 'bearer $accessToken',
          'User-Agent': RedditConstants.userAgent(null),
        }),
      );
      return (res.data as Map)['name'] as String?;
    } catch (_) {
      return null;
    }
  }

  // Single-flight guard: concurrent 401s share one in-flight refresh so the
  // refresh token isn't spent multiple times in parallel.
  Future<String?>? _refreshing;

  /// Refreshes the access token using the stored refresh token. Returns the new
  /// access token, or null if refresh is not possible (caller should re-login).
  /// Starts browsing without an account, using [clientId]'s app-only token
  /// (Reddit's "installed client" grant). Throws [AuthException] if refused.
  Future<void> startAnonymous(String clientId) async {
    clientId = clientId.trim();
    final token = await _appOnlyToken(clientId);
    if (token == null) {
      throw AuthException(
          "Reddit didn't accept this Client ID. Check it, and that the app "
          'type is "installed app".');
    }
    await _store.saveAnonymousSession();
    await _store.saveCredentials(
        clientId: clientId, redirectUri: RedditConstants.defaultRedirectUri);
  }

  /// Fetches and stores an app-only access token for [clientId]; null if
  /// Reddit refuses it or can't be reached.
  Future<String?> _appOnlyToken(String clientId) async {
    try {
      final res = await _dio.post(
        RedditConstants.accessTokenUrl,
        data: {
          'grant_type': RedditConstants.installedClientGrant,
          'device_id': RedditConstants.validationDeviceId,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Authorization': _basicAuth(clientId),
            'User-Agent': RedditConstants.userAgent(null),
          },
          validateStatus: (_) => true,
        ),
      );
      final data = res.data;
      if (res.statusCode != 200 || data is! Map) return null;
      final token = data['access_token'] as String?;
      if (token == null) return null;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      await _store.saveTokens(
        accessToken: token,
        expiry: DateTime.now().add(Duration(seconds: expiresIn - 60)),
      );
      return token;
    } catch (_) {
      return null;
    }
  }

  Future<String?> refresh() {
    return _refreshing ??=
        _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _store.refreshToken;
    final clientId = await _store.clientId;
    // Browsing without an account: app-only tokens can't be refreshed, so
    // mint a new one the same way.
    if (refreshToken == null &&
        clientId != null &&
        await _store.authMode == 'anon') {
      return _appOnlyToken(clientId);
    }
    if (refreshToken == null || clientId == null) return null;
    try {
      final res = await _dio.post(
        RedditConstants.accessTokenUrl,
        data: {
          'grant_type': RedditConstants.grantTypeRefreshToken,
          'refresh_token': refreshToken,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Authorization': _basicAuth(clientId),
            'User-Agent': RedditConstants.userAgent(await _store.username),
          },
          validateStatus: (_) => true,
        ),
      );
      if (res.statusCode != 200 || res.data is! Map) return null;
      final data = res.data as Map;
      final accessToken = data['access_token'] as String?;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      if (accessToken == null) return null;
      await _store.saveTokens(
        accessToken: accessToken,
        expiry: DateTime.now().add(Duration(seconds: expiresIn - 60)),
      );
      return accessToken;
    } catch (_) {
      return null;
    }
  }
}
