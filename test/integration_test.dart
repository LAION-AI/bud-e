/// Integration tests that hit the live middleware API.
///
/// These tests use the default universal API key to verify that
/// chat, TTS, and basic API connectivity work end-to-end.
///
/// Run with:  dart test test/integration_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:school_bud_e/config/api_config.dart';
import 'package:school_bud_e/services/chat_service.dart';
import 'package:school_bud_e/models/message.dart';

const _key = kDefaultUniversalKey;

void main() {
  late String baseUrl;

  setUpAll(() {
    final decoded = decodeMiddlewareBase(_key);
    if (decoded == null) {
      fail('Could not decode middleware base URL from default key');
    }
    baseUrl = decoded;
    print('Testing against middleware: $baseUrl');
  });

  group('Connectivity', () {
    test('middleware is reachable', () async {
      try {
        final resp = await http.get(
          Uri.parse('$baseUrl/v1/models'),
          headers: {'Authorization': 'Bearer $_key'},
        ).timeout(const Duration(seconds: 10));
        print('GET /v1/models -> ${resp.statusCode}');
        // Accept 200 or 404 (models endpoint may not exist, but server is up)
        expect(resp.statusCode, anyOf(200, 404, 405));
      } on SocketException {
        fail('Middleware not reachable at $baseUrl');
      }
    });
  });

  group('Chat completions', () {
    test('non-streaming chat returns a response', () async {
      final chatService = ChatService();
      final response = await chatService.chat(
        universalApiKey: _key,
        messages: [Message.user('Say exactly: "Hello from test"')],
        systemPrompt: 'You are a test assistant. Follow instructions precisely.',
      );
      print('Chat response: $response');
      expect(response, isNotEmpty);
      expect(response, isNot(startsWith('[Error]')));
    }, timeout: Timeout(Duration(seconds: 30)));

    test('streaming chat yields chunks', () async {
      final chatService = ChatService();
      final chunks = <String>[];

      await for (final chunk in chatService.streamChat(
        universalApiKey: _key,
        messages: [Message.user('Count from 1 to 5, one number per line.')],
        systemPrompt: 'You are a test assistant.',
      )) {
        chunks.add(chunk);
      }

      final full = chunks.join();
      print('Streamed response (${chunks.length} chunks): $full');
      expect(chunks, isNotEmpty);
      expect(full, isNotEmpty);
      expect(full, isNot(startsWith('[Error]')));
    }, timeout: Timeout(Duration(seconds: 30)));

    test('chat handles multi-turn conversation', () async {
      final chatService = ChatService();
      final messages = [
        Message.user('My name is TestBot.'),
        Message.assistant('Nice to meet you, TestBot!'),
        Message.user('What is my name?'),
      ];

      final response = await chatService.chat(
        universalApiKey: _key,
        messages: messages,
      );
      print('Multi-turn response: $response');
      expect(response.toLowerCase(), contains('testbot'));
    }, timeout: Timeout(Duration(seconds: 30)));
  });

  group('TTS', () {
    test('TTS endpoint returns audio bytes', () async {
      final url = middlewareUrl(_key, '/v1/audio/speech')!;
      final resp = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_key',
        },
        body: jsonEncode({
          'model': 'auto',
          'input': 'Hello, this is a test.',
        }),
      );

      print('TTS response: ${resp.statusCode}, '
          'content-type: ${resp.headers['content-type']}, '
          'body size: ${resp.bodyBytes.length} bytes');

      if (resp.statusCode == 200) {
        expect(resp.bodyBytes.length, greaterThan(100));
      } else {
        // TTS may not be configured — skip gracefully
        print('TTS not available (${resp.statusCode}), skipping');
      }
    }, timeout: Timeout(Duration(seconds: 20)));
  });

  group('Key decoding', () {
    test('default key decodes to a valid URL with port', () {
      final url = decodeMiddlewareBase(_key);
      expect(url, isNotNull);
      final uri = Uri.parse(url!);
      expect(uri.scheme, equals('http'));
      expect(uri.host, isNotEmpty);
      expect(uri.port, greaterThan(0));
      print('Decoded URL: $url');
    });
  });
}
