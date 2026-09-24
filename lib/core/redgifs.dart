import 'package:dio/dio.dart';

// RedGifs links point at a web page, not a playable file. Their public API
// hands out an anonymous temporary token, which then resolves a clip id to
// its HD (with sound) / SD mp4.

final _dio = Dio(BaseOptions(
  baseUrl: 'https://api.redgifs.com/v2',
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 8),
));
String? _token;

/// The clip id in a RedGifs URL (`redgifs.com/watch/<id>`, `/ifr/<id>`,
/// `i.redgifs.com/i/<id>.jpg`), or null when it isn't one.
String? redgifsId(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !u.host.toLowerCase().endsWith('redgifs.com')) return null;
  final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.length < 2 || !const {'watch', 'ifr', 'i'}.contains(segs[0])) {
    return null;
  }
  final id = segs[1].split('.').first.split('-').first.toLowerCase();
  return id.isEmpty ? null : id;
}

/// The best playable mp4 for a RedGifs URL, or null if it can't be resolved.
Future<String?> resolveRedgifs(String url) async {
  final id = redgifsId(url);
  if (id == null) return null;
  // One retry with a fresh token: temporary tokens expire (~24h).
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      _token ??= (await _dio.get<Map<String, dynamic>>('/auth/temporary'))
          .data?['token'] as String?;
      if (_token == null) return null;
      final res = await _dio.get<Map<String, dynamic>>('/gifs/$id',
          options: Options(headers: {'Authorization': 'Bearer $_token'}));
      final urls = (res.data?['gif'] as Map?)?['urls'] as Map?;
      return (urls?['hd'] ?? urls?['sd']) as String?;
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) return null;
      _token = null;
    } catch (_) {
      return null;
    }
  }
  return null;
}
