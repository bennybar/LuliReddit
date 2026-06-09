import 'package:dio/dio.dart';

import '../reddit_constants.dart';
import '../storage/secure_store.dart';
import '../../features/auth/auth_repository.dart';
import 'rate_limit.dart';
import 'response_cache.dart';

/// Authenticated dio client for oauth.reddit.com. Attaches the bearer token,
/// a compliant User-Agent and `raw_json=1`, transparently refreshes the access
/// token once on a 401, surfaces rate-limit headers, and (optionally) serves a
/// disk cache fallback when offline.
class RedditClient {
  RedditClient(
    this._store,
    this._auth, {
    this.onRateLimit,
    this.cacheEnabled,
  }) {
    _dio = Dio(BaseOptions(
      baseUrl: RedditConstants.oauthApiBase,
      validateStatus: (s) => s != null && s < 500,
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _validToken();
        options.headers['Authorization'] = 'bearer $token';
        options.headers['User-Agent'] =
            RedditConstants.userAgent(await _store.username);
        options.queryParameters['raw_json'] = 1;
        handler.next(options);
      },
      onResponse: (response, handler) async {
        _captureRateLimit(response.headers);
        if (response.statusCode == 401 &&
            response.requestOptions.extra['retried'] != true) {
          final newToken = await _auth.refresh();
          if (newToken != null) {
            final req = response.requestOptions;
            req.extra['retried'] = true;
            req.headers['Authorization'] = 'bearer $newToken';
            try {
              final retry = await _dio.fetch(req);
              return handler.resolve(retry);
            } catch (_) {/* fall through */}
          }
        }
        handler.next(response);
      },
    ));
  }

  late final Dio _dio;
  final SecureStore _store;
  final AuthRepository _auth;
  final void Function(RateLimit)? onRateLimit;
  final bool Function()? cacheEnabled;
  final ResponseCache _cache = ResponseCache();

  void _captureRateLimit(Headers headers) {
    final rem = headers.value('x-ratelimit-remaining');
    final used = headers.value('x-ratelimit-used');
    final reset = headers.value('x-ratelimit-reset');
    if (rem == null || onRateLimit == null) return;
    onRateLimit!(RateLimit(
      remaining: double.tryParse(rem)?.round() ?? 0,
      used: double.tryParse(used ?? '0')?.round() ?? 0,
      resetSeconds: double.tryParse(reset ?? '0')?.round() ?? 0,
    ));
  }

  Future<String> _validToken() async {
    final token = await _store.accessToken;
    final expiry = await _store.tokenExpiry;
    final expired = expiry == null || DateTime.now().isAfter(expiry);
    if (token == null || token.isEmpty || expired) {
      final refreshed = await _auth.refresh();
      if (refreshed != null) return refreshed;
    }
    return token ?? '';
  }

  bool get _cacheOn => cacheEnabled?.call() ?? false;
  String _cacheKey(String path, Map<String, dynamic>? query) =>
      '$path?${(query ?? {}).entries.map((e) => '${e.key}=${e.value}').join('&')}';

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get<T>(path, queryParameters: query);
      if (_cacheOn && res.statusCode == 200) {
        _cache.write(_cacheKey(path, query), res.data);
      }
      return res;
    } on DioException catch (e) {
      // Network failure → serve cached copy if we have one.
      if (_cacheOn && _isNetworkError(e)) {
        final cached = await _cache.read(_cacheKey(path, query));
        if (cached != null) {
          return Response<T>(
            requestOptions: e.requestOptions,
            data: cached as T,
            statusCode: 200,
            extra: {'fromCache': true},
          );
        }
      }
      rethrow;
    }
  }

  bool _isNetworkError(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout;

  Future<void> clearCache() => _cache.clear();

  Future<Response<T>> post<T>(String path, {Map<String, dynamic>? data}) =>
      _dio.post<T>(path,
          data: data,
          options: Options(contentType: Headers.formUrlEncodedContentType));

  /// POST with a JSON body (used by submit_gallery_post and multireddit APIs).
  Future<Response<T>> postJson<T>(String path, {Object? data}) =>
      _dio.post<T>(path,
          data: data, options: Options(contentType: Headers.jsonContentType));

  Future<Response<T>> put<T>(String path, {Object? data}) => _dio.put<T>(path,
      data: data, options: Options(contentType: Headers.jsonContentType));

  Future<Response<T>> delete<T>(String path, {Map<String, dynamic>? query}) =>
      _dio.delete<T>(path, queryParameters: query);
}
