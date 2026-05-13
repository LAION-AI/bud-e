/// LLM chat service — streaming SSE to the middleware.
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/message.dart';
import 'debug_log.dart';

class ChatService {
  /// Sends [messages] to the middleware and yields assistant text chunks.
  Stream<String> streamChat({
    required String universalApiKey,
    required List<Message> messages,
    String model = '',
    String? systemPrompt,
  }) async* {
    final url = middlewareUrl(universalApiKey, '/v1/chat/completions');
    if (url == null) {
      yield '[Error] Could not decode middleware URL from API key.';
      return;
    }

    final apiMessages = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      apiMessages.add(m.toApiMap());
    }

    final body = jsonEncode({
      'model': model.isEmpty ? 'auto' : model,
      'stream': true,
      'messages': apiMessages,
    });

    debugLog(DebugSource.mainAgent,
        'POST $url (${apiMessages.length} messages, ${body.length} chars)');

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(url))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $universalApiKey'
        ..body = body;

      final http.StreamedResponse response;
      try {
        response = await client.send(request)
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        yield '[Error] Connection failed: $e';
        return;
      }

      if (response.statusCode != 200) {
        final errBody = await response.stream.bytesToString()
            .timeout(const Duration(seconds: 10), onTimeout: () => '(timeout reading error)');
        yield '[Error] ${response.statusCode}: $errBody';
        return;
      }

      // Parse SSE stream with a per-chunk timeout.
      // If no data arrives for 60s, we assume the stream is dead.
      await for (final chunk in response.stream
          .timeout(const Duration(seconds: 60),
              onTimeout: (sink) => sink.close())
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.isEmpty) continue;
        if (chunk.startsWith('data: ')) {
          final data = chunk.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                yield content;
              }
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  /// Non-streaming chat (used by background agents).
  Future<String> chat({
    required String universalApiKey,
    required List<Message> messages,
    String model = '',
    String? systemPrompt,
  }) async {
    final url = middlewareUrl(universalApiKey, '/v1/chat/completions');
    if (url == null) return '[Error] Could not decode middleware URL.';

    final apiMessages = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      apiMessages.add(m.toApiMap());
    }

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $universalApiKey',
        },
        body: jsonEncode({
          'model': model.isEmpty ? 'auto' : model,
          'stream': false,
          'messages': apiMessages,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        return '[Error] ${response.statusCode}: ${response.body}';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        return (choices[0]['message']['content'] as String?) ?? '';
      }
      return '';
    } catch (e) {
      return '[Error] $e';
    }
  }
}
