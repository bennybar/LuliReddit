import 'package:flutter/services.dart';

/// On-device translation: Apple's Translation framework through the
/// `ilay/translate` channel (AppDelegate.swift). Free, private and offline
/// once a language is downloaded; iOS asks to download one the first time.
/// Posts are translated into the phone's language.
class Translate {
  static const _channel = MethodChannel('ilay/translate');

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

  /// Whether the phone can translate [from] into its own language.
  static Future<bool> canTranslate(String from) async {
    try {
      return await _channel.invokeMethod<bool>('canTranslate', {'from': from}) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// [texts] from [from] into the phone's language, in order; null when it
  /// couldn't (or the download was declined).
  static Future<List<String>?> translate(List<String> texts, String from) async {
    if (texts.isEmpty) return const [];
    try {
      final out = await _channel
          .invokeListMethod<String>('translate', {'texts': texts, 'from': from});
      return out;
    } on PlatformException {
      return null;
    }
  }
}
