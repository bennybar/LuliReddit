import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../data/ai_service.dart';
import '../features/settings/settings_controller.dart';
import 'storage/secure_store.dart';

/// Translation into the phone's language and Settings → Second language.
/// On the phone first, through Apple's Translation framework (the
/// `ilay/translate` channel, AppDelegate.swift): free, private and offline
/// once a language is downloaded, which iOS asks for the first time.
/// Languages it can't do (Hebrew) go to Settings → Translation service: the
/// OpenAI key summaries use, or Azure Translator.
class Translate {
  static const _channel = MethodChannel('ilay/translate');

  /// The phone's language: the first thing posts are translated into.
  static String get primary =>
      PlatformDispatcher.instance.locale.languageCode;

  /// The language [text] is in (a code like "de"), when the phone is fairly
  /// sure.
  static Future<String?> detect(String text) async {
    if (text.trim().isEmpty) return null;
    try {
      return await _channel.invokeMethod<String>('detect', {'text': text});
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> _onPhone(String from, String to) async {
    try {
      return await _channel.invokeMethod<bool>(
              'canTranslate', {'from': from, 'to': to}) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> _serviceReady(Settings s, SecureStore store) async {
    final key = s.translateService == 'azure'
        ? await store.azureTranslatorKey
        : await store.openaiKey;
    return key != null && key.isNotEmpty;
  }

  /// The languages text in [from] can be translated into here: the phone's
  /// and the second language, minus [from], each when the phone or the
  /// translation service can do it.
  static Future<List<String>> targets(
      String from, Settings s, SecureStore store) async {
    final service = await _serviceReady(s, store);
    final out = <String>[];
    for (final to in {primary, s.translateSecondLanguage}) {
      if (to.isEmpty || to == from) continue;
      if (service || await _onPhone(from, to)) out.add(to);
    }
    return out;
  }

  /// [texts] from [from] into [to], in order: on the phone when it can, else
  /// (or when that fails, or the download was declined) through the
  /// translation service. Null when neither could; the service's error is
  /// thrown.
  static Future<List<String>?> translate(List<String> texts, String from,
      String to, Settings s, SecureStore store) async {
    if (texts.isEmpty) return const [];
    if (await _onPhone(from, to)) {
      try {
        final out = await _channel.invokeListMethod<String>(
            'translate', {'texts': texts, 'from': from, 'to': to});
        if (out != null) return out;
      } on PlatformException {
        // Falls through to the service.
      }
    }
    if (!await _serviceReady(s, store)) return null;
    if (s.translateService == 'azure') {
      return _azure(texts, from, to, (await store.azureTranslatorKey)!,
          s.azureRegion);
    }
    return AiService.translate(
      baseUrl: s.aiUseCustomUrl ? s.aiBaseUrl : 'https://api.openai.com',
      apiKey: (await store.openaiKey)!,
      model: s.aiModel,
      texts: texts,
      language: englishNames[to] ?? to,
    );
  }

  /// Azure Translator (Settings → Translation service): [key] and the
  /// resource's [region] (empty for a global resource). Up to 1000 texts and
  /// 50k characters a request, so a big thread goes in batches.
  static Future<List<String>> _azure(List<String> texts, String from,
      String to, String key, String region) async {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    final out = <String>[];
    for (final batch in batches(texts, 40000, 900)) {
      final Response<dynamic> r;
      try {
        r = await dio.post(
          'https://api.cognitive.microsofttranslator.com/translate',
          queryParameters: {'api-version': '3.0', 'from': from, 'to': to},
          data: jsonEncode([
            for (final t in batch) {'Text': t}
          ]),
          options: Options(headers: {
            'Ocp-Apim-Subscription-Key': key,
            if (region.isNotEmpty) 'Ocp-Apim-Subscription-Region': region,
            'Content-Type': 'application/json',
          }),
        );
      } on DioException catch (e) {
        throw Exception("Couldn't reach Azure Translator: ${e.message}");
      }
      final data = r.data;
      if (r.statusCode != 200 || data is! List) {
        final error = data is Map ? data['error'] : null;
        final msg = error is Map ? error['message'] : null;
        throw Exception(
            'Azure Translator refused it (${r.statusCode}): ${msg ?? data}');
      }
      for (var i = 0; i < batch.length; i++) {
        final Object? t = i < data.length ? data[i] : null;
        final tr = t is Map ? t['translations'] : null;
        final first = tr is List && tr.isNotEmpty ? tr.first : null;
        final text = first is Map ? first['text'] : null;
        out.add(text is String ? text : batch[i]);
      }
    }
    return out;
  }

  /// [texts] in order, in groups of at most [maxChars] characters and
  /// [maxCount] texts.
  static List<List<String>> batches(
      List<String> texts, int maxChars, int maxCount) {
    final out = <List<String>>[];
    var chars = 0;
    for (final t in texts) {
      if (out.isEmpty ||
          out.last.length >= maxCount ||
          chars + t.length > maxChars) {
        out.add([t]);
        chars = t.length;
      } else {
        out.last.add(t);
        chars += t.length;
      }
    }
    return out;
  }

  /// [code]'s name ("German"), for menus and the AI prompt.
  static String languageName(String code) => englishNames[code] ?? code;

  /// Settings → Second language: the languages Ilay can translate into
  /// (phone or service).
  static const englishNames = {
    'ar': 'Arabic',
    'de': 'German',
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'he': 'Hebrew',
    'hi': 'Hindi',
    'id': 'Indonesian',
    'it': 'Italian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'nl': 'Dutch',
    'pl': 'Polish',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'th': 'Thai',
    'tr': 'Turkish',
    'uk': 'Ukrainian',
    'vi': 'Vietnamese',
    'zh': 'Chinese',
  };
}
