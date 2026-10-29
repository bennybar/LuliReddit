import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/translate.dart';
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
    String language = '',
  }) async {
    // Settings → AI summaries → Summary language ('' = the thread's own).
    final lang = language.isEmpty
        ? 'Write the summary in the same language as the thread.'
        : 'Write the summary in $language, whatever language the thread is '
            'in.';
    final system =
        'You summarize Reddit threads accurately and neutrally. Do not invent '
        'details. ${style.instruction} $lang';
    return _chat(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': threadText},
      ],
    );
  }

  /// Answers [question] about the thread in [threadText], continuing the
  /// conversation in [history] (alternating user / assistant turns, oldest
  /// first). Answers only from the thread, and says so when it can't tell.
  static Future<String> ask({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String threadText,
    required List<({bool fromUser, String text})> history,
    required String question,
  }) {
    const system =
        'You answer questions about one Reddit thread: the post and its '
        'comments, given in the first user message. Use only what the thread '
        'says. If it doesn\'t answer the question, say so plainly instead of '
        'guessing. When a point comes from a specific comment, cite it with '
        "that comment's tag right after the point, like [c3] (several: [c3] "
        "[c7]); don't write the tags any other way. Be concise and use "
        'markdown.';
    return _chat(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': 'THE THREAD:\n$threadText'},
        {
          'role': 'assistant',
          'content': 'Got it. Ask me anything about this thread.'
        },
        for (final m in history)
          {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text},
        {'role': 'user', 'content': question},
      ],
    );
  }

  /// [texts] translated into [language] (its English name), in order: the
  /// fallback for languages the phone can't translate (translate.dart). Sent
  /// as JSON arrays, in batches so a long thread fits a reply.
  static Future<List<String>> translate({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<String> texts,
    required String language,
  }) async {
    final system = 'Translate each string in the JSON array the user sends '
        'into $language. Keep Markdown, links, line breaks, u/ and r/ names as '
        'they are. Reply with only a JSON array of the translations: the same '
        'number of strings, in the same order.';
    final out = <String>[];
    for (final batch in Translate.batches(texts, 6000, 60)) {
      final reply = await _chat(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': jsonEncode(batch)},
        ],
      );
      // Some models wrap it in a ```json fence.
      final start = reply.indexOf('['), end = reply.lastIndexOf(']');
      List? list;
      try {
        if (start >= 0 && end > start) {
          list = jsonDecode(reply.substring(start, end + 1)) as List;
        }
      } catch (_) {}
      if (list == null || list.length != batch.length) {
        throw Exception("The AI's translation didn't come back whole. Try "
            'again.');
      }
      out.addAll(list.map((e) => '$e'));
    }
    return out;
  }

  /// One /v1/chat/completions call; returns the reply text or throws with a
  /// readable message.
  static Future<String> _chat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
  }) async {
    final url = chatUrl(baseUrl);
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
        data: {'model': model, 'messages': messages},
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
    if (text.isEmpty) throw Exception('The AI returned an empty answer.');
    return text;
  }

  /// The thread for Ask: like [buildThreadText], but each comment is tagged
  /// [c1], [c2]… so answers can cite them, plus the refs (tag → comment) to
  /// turn those citations into links, and how many comments went in.
  static CitedThread buildCitedThread(
      Post post, List<Comment> comments, int maxChars) {
    final sb = StringBuffer();
    sb.writeln('POST in r/${post.subreddit} by u/${post.author} — score '
        '${post.score}, ${post.numComments} comments');
    sb.writeln('TITLE: ${post.title}');
    if (post.isSelf && post.selftext.trim().isNotEmpty) {
      sb.writeln('BODY: ${post.selftext.trim()}');
    }
    sb.writeln('\nTOP COMMENTS (most upvoted first), each with its tag:');
    final ranked = [
      for (final c in comments)
        if (!c.isMore && c.body.trim().isNotEmpty) c
    ]..sort((a, b) => b.score.compareTo(a.score));
    final refs = <String, Comment>{};
    for (final c in ranked) {
      final tag = 'c${refs.length + 1}';
      final line = '\n[$tag] [${c.score}] u/${c.author}: '
          '${c.body.replaceAll('\n', ' ').trim()}';
      if (sb.length + line.length > maxChars) break;
      sb.write(line);
      refs[tag] = c;
    }
    sb.write('\n\n(Included ${refs.length} of ${ranked.length} comments, '
        'highest-scored first.)');
    return CitedThread(sb.toString(), refs, refs.length, ranked.length);
  }

  /// A link to a comment in this thread, inside an Ask answer.
  static const commentLink = 'ilay-comment:';
  static final _citation = RegExp(r'\[(c\d+)\]');

  /// Turns the answer's [c12] citations into links to those comments
  /// (`ilay-comment:<fullname>`); unknown tags are dropped.
  static String linkCitations(String answer, Map<String, Comment> refs) =>
      answer.replaceAllMapped(_citation, (m) {
        final c = refs[m.group(1)];
        return c == null ? '' : '[u/${c.author}]($commentLink${c.fullname})';
      });

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

/// The thread as Ask sends it ([text]), its comment tags ([refs]), and how
/// many comments went in of those loaded.
class CitedThread {
  const CitedThread(this.text, this.refs, this.included, this.loaded);
  final String text;
  final Map<String, Comment> refs;
  final int included;
  final int loaded;
}

/// The chat endpoint under [baseUrl]. Providers document their base either
/// without the version (api.openai.com, a LiteLLM host) or with it
/// (api.groq.com/openai/v1): don't add a second /v1.
String chatUrl(String baseUrl) {
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  return RegExp(r'/v\d+$').hasMatch(base)
      ? '$base/chat/completions'
      : '$base/v1/chat/completions';
}
