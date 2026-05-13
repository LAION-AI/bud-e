import 'package:test/test.dart';
import 'package:school_bud_e/config/api_config.dart';

void main() {
  group('Universal key decoding', () {
    test('splitUniversalKey separates key and suffix', () {
      final parts = splitUniversalKey('sbe-ABCD#v1XYZ');
      expect(parts.apiKey, equals('sbe-ABCD'));
      expect(parts.suffix, equals('v1XYZ'));
    });

    test('splitUniversalKey with no hash returns full string as key', () {
      final parts = splitUniversalKey('sbe-ABCD');
      expect(parts.apiKey, equals('sbe-ABCD'));
      expect(parts.suffix, isEmpty);
    });

    test('extractApiKey returns part before #', () {
      expect(extractApiKey('sbe-2NE7Z87KY6DU#v1NNUG25DKORVHI23AMJWWE3I'),
          equals('sbe-2NE7Z87KY6DU'));
    });

    test('decodeMiddlewareBase with default key returns valid URL', () {
      final url = decodeMiddlewareBase(kDefaultUniversalKey);
      expect(url, isNotNull);
      expect(url, startsWith('http://'));
      // Should decode to a valid host:port
      final uri = Uri.parse(url!);
      expect(uri.host, isNotEmpty);
      expect(uri.port, greaterThan(0));
    });

    test('decodeMiddlewareBase with raw URL suffix', () {
      final url = decodeMiddlewareBase('key#http://localhost:8787');
      expect(url, equals('http://localhost:8787'));
    });

    test('decodeMiddlewareBase with trailing slashes stripped', () {
      final url = decodeMiddlewareBase('key#http://localhost:8787///');
      expect(url, equals('http://localhost:8787'));
    });

    test('decodeMiddlewareBase with no hash returns null', () {
      expect(decodeMiddlewareBase('just-a-key'), isNull);
    });

    test('decodeMiddlewareBase with invalid suffix returns null', () {
      expect(decodeMiddlewareBase('key#garbage'), isNull);
    });

    test('middlewareUrl builds correct endpoint path', () {
      final url = middlewareUrl(
          'key#http://localhost:8787', '/v1/chat/completions');
      expect(url, equals('http://localhost:8787/v1/chat/completions'));
    });

    test('middlewareUrl returns null for invalid key', () {
      expect(middlewareUrl('bad-key', '/v1/chat/completions'), isNull);
    });
  });
}
