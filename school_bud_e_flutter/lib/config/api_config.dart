/// API configuration — key management, middleware URL decoding.
///
/// The "universal key" format is `<api_key>#<encoded_middleware_url>`.
/// The suffix after `#` is either a raw `http(s)://` URL or a `v1`-prefixed
/// Base32-encoded, XOR-obfuscated `host:port` string.
library;

import 'dart:convert';
import 'dart:typed_data';

const String kDefaultUniversalKey =
    'sbe-2NE7Z87KY6DU#v1NNUG25DKORVHI23AMJWWE3I';

/// Splits a universal key into its API-key part and the raw suffix.
({String apiKey, String suffix}) splitUniversalKey(String universalKey) {
  final raw = universalKey.trim();
  final hash = raw.indexOf('#');
  if (hash < 0) return (apiKey: raw, suffix: '');
  return (apiKey: raw.substring(0, hash).trim(), suffix: raw.substring(hash + 1));
}

/// Extracts the bearer token (the part before `#`).
String extractApiKey(String universalKey) =>
    splitUniversalKey(universalKey).apiKey;

/// Decodes the middleware base URL from the universal key.
///
/// Returns `null` when no valid URL can be derived.
String? decodeMiddlewareBase(String universalKey) {
  final parts = splitUniversalKey(universalKey);
  final suffix = parts.suffix;
  if (suffix.isEmpty) return null;

  // Raw URL form
  if (RegExp(r'^https?://.+', caseSensitive: false).hasMatch(suffix)) {
    return suffix.replaceAll(RegExp(r'/+$'), '');
  }

  // v1-encoded form
  if (!suffix.startsWith('v1')) return null;
  try {
    final b32 = suffix.substring(2); // strip "v1"
    final bytes = _base32DecodeNoPadding(b32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = bytes[i] ^ 0x5A;
    }
    final hostPort = utf8.decode(bytes);
    if (!hostPort.contains(':')) return null;
    return _hostPortToHttpBase(hostPort).replaceAll(RegExp(r'/+$'), '');
  } catch (_) {
    return null;
  }
}

/// Builds the full endpoint URL for a given path.
///
/// Example: `middlewareUrl(key, '/v1/chat/completions')`
String? middlewareUrl(String universalKey, String path) {
  final base = decodeMiddlewareBase(universalKey);
  if (base == null) return null;
  return '$base$path';
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

const _b32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

Uint8List _base32DecodeNoPadding(String s) {
  final clean = s.trim().toUpperCase().replaceAll(RegExp(r'=+$'), '');
  var bits = 0;
  var value = 0;
  final out = <int>[];
  for (var i = 0; i < clean.length; i++) {
    final idx = _b32Alphabet.indexOf(clean[i]);
    if (idx == -1) throw FormatException('Invalid Base32 character');
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((value >> bits) & 0xFF);
    }
  }
  return Uint8List.fromList(out);
}

String _hostPortToHttpBase(String hostPort) {
  final lastColon = hostPort.lastIndexOf(':');
  var host = hostPort;
  var port = '';
  if (lastColon != -1) {
    host = hostPort.substring(0, lastColon);
    port = hostPort.substring(lastColon + 1);
  }
  final isIPv6 = host.contains(':');
  final bracketHost = isIPv6 ? '[$host]' : host;
  final portPart = port.isNotEmpty ? ':$port' : '';
  return 'http://$bracketHost$portPart';
}
