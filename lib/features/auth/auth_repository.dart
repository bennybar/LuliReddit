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
  }) async {
    clientId = clientId.trim();
    redirectUri = redirectUri.trim();

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
        callbackUrlScheme: RedditConstants.callbackScheme,
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

    await _store.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiry: DateTime.now().add(Duration(seconds: expiresIn - 60)),
    );

    final username = await _fetchUsername(accessToken);
    await _store.saveUsername(username);
    await _store.saveCredentials(clientId: clientId, redirectUri: redirectUri);
    return username ?? 'redditor';
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
  Future<String?> refresh() {
    return _refreshing ??=
        _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _store.refreshToken;
    final clientId = await _store.clientId;
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
