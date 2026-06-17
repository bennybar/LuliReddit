import 'package:dio/dio.dart';

import '../models/comment.dart';
import '../models/post.dart';

/// Summary styles for AI thread summaries.
enum SummaryStyle { tldr, points, debate, eli5 }

extension SummaryStyleX on SummaryStyle {
  String get label => switch (this) {
        SummaryStyle.tldr => 'TL;DR',
        SummaryStyle.points => 'Key points',
        SummaryStyle.debate => 'Consensus & disagreements',
        SummaryStyle.eli5 => 'Explain like I\'m 5',
      };

  String get instruction => switch (this) {
        SummaryStyle.tldr =>
          'Give a tight 2-4 sentence TL;DR of the discussion.',
        SummaryStyle.points =>
          'Summarize as concise markdown bullet points: the post in one line, '
              'then the main takeaways, notable opinions, and any useful facts '
              'or links raised in the comments.',
        SummaryStyle.debate =>
          'Summarize what the commenters broadly agree on, then the main points '
              'of disagreement or debate, as short markdown sections.',
        SummaryStyle.eli5 =>
          'Explain the post and what people are saying in simple, plain language '
              'anyone could understand.',
      };
}

/// Minimal client for an OpenAI-compatible /v1/chat/completions endpoint.
/// Works with OpenAI or any compatible gateway (e.g. LiteLLM) via [baseUrl].
class AiService {
  /// Returns the assistant's summary text, or throws with a readable message.
  static Future<String> summarize({
    required String baseUrl,
    required String apiKey,
    required String model,
    required SummaryStyle style,
    required String threadText,
  }) async {
    final url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/chat/completions';
    final system =
        'You summarize Reddit threads accurately and neutrally. Do not invent '
        'details. ${style.instruction}';
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 90),
      validateStatus: (_) => true,
    ));
    Response res;
    try {
      res = await dio.post(
        url,
        options: Options(headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': model,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': threadText},
          ],
        },
      );
    } on DioException catch (e) {
      throw Exception('Could not reach the AI endpoint: ${e.message}');
    }
    if (res.statusCode != 200) {
      final data = res.data;
      final msg = data is Map
          ? (data['error']?['message'] ?? data['error'] ?? data).toString()
          : '$data';
      throw Exception('AI request failed (${res.statusCode}): $msg');
    }
    final data = res.data;
    String? content;
    if (data is Map) {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final msg = (choices.first as Map?)?['message'];
        if (msg is Map) content = msg['content']?.toString();
      }
    }
    final text = content?.trim() ?? '';
    if (text.isEmpty) throw Exception('The AI returned an empty summary.');
    return text;
  }

  /// Builds the thread text to summarize: the post, then comments ordered by
  /// score (most upvoted first) until [maxChars] is reached.
  static String buildThreadText(Post post, List<Comment> comments, int maxChars) {
    final sb = StringBuffer();
    sb.writeln(
        'POST in r/${post.subreddit} by u/${post.author} — score ${post.score}, ${post.numComments} comments');
    sb.writeln('TITLE: ${post.title}');
    if (post.isSelf && post.selftext.trim().isNotEmpty) {
      sb.writeln('BODY: ${post.selftext.trim()}');
    }
    sb.writeln('\nTOP COMMENTS (most upvoted first):');

    final ranked = [
      for (final c in comments)
        if (!c.isMore && c.body.trim().isNotEmpty) c
    ]..sort((a, b) => b.score.compareTo(a.score));

    var included = 0;
    for (final c in ranked) {
      final line =
          '\n[${c.score}] u/${c.author}: ${c.body.replaceAll('\n', ' ').trim()}';
      if (sb.length + line.length > maxChars) break;
      sb.write(line);
      included++;
    }
    sb.write('\n\n(Included $included of ${ranked.length} comments, '
        'highest-scored first.)');
    return sb.toString();
  }
}
