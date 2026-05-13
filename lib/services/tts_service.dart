/// Text-to-Speech service — optimized batching strategy.
///
/// Key insight: Each TTS API call has ~2s fixed overhead. Sending 3 separate
/// sentence calls = ~7s, but sending them batched in 1 call = ~2.5s.
///
/// Strategy:
///   1. As LLM streams, detect first sentence boundary quickly (min 3 words)
///   2. Send first sentence to TTS immediately (eager, for fast TTFA)
///   3. Accumulate ALL remaining text during playback of sentence 1
///   4. When stream ends, send remaining text as ONE call
///   5. Result: only 2 TTS API calls for any response length
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:collection';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/api_config.dart';
import 'debug_log.dart';

// ---------------------------------------------------------------------------
// Sanitization
// ---------------------------------------------------------------------------

final _emojiRegex = RegExp(
  r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]'
  r'|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]'
  r'|[\u{FE00}-\u{FE0F}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]'
  r'|[\u{1FA70}-\u{1FAFF}]|[\u{200D}]|[\u{20E3}]|[\u{E0020}-\u{E007F}]'
  r'|[\u{2B50}]|[\u{23F0}-\u{23FA}]|[\u{2934}-\u{2935}]'
  r'|[\u{25AA}-\u{25FE}]|[\u{2194}-\u{21AA}]|[\u{1F004}]|[\u{1F0CF}]',
  unicode: true,
);

String sanitizeForTts(String text) {
  var s = text;
  s = s.replaceAll(RegExp(r'\[\[.*?\]\]', dotAll: true), '');
  s = s.replaceAll(RegExp(r'\*{1,3}'), '');
  s = s.replaceAll(RegExp(r'_{1,3}'), ' ');
  s = s.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'```[^`]*```', dotAll: true), '');
  s = s.replaceAll(RegExp(r'`([^`]*)`'), r'$1');
  s = s.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');
  s = s.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1');
  s = s.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
  s = s.replaceAll(_emojiRegex, '');
  s = s.replaceAll(RegExp(r'[~^<>|\\{}[\]@#$%&=+]'), '');
  s = s.replaceAll(RegExp(r'\n{2,}'), '. ');
  s = s.replaceAll(RegExp(r'\n'), ' ');
  s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
  return s.trim();
}

final _sentenceEndRe = RegExp(r'(?<!\d)[.!?:]\s');

// ---------------------------------------------------------------------------
// TTS Service
// ---------------------------------------------------------------------------

class TtsService {
  final AudioPlayer _player = AudioPlayer();
  String? _apiKey;
  String? _url;
  int _sessionId = 0;

  String _rawBuffer = '';
  bool _firstSentSent = false;
  Future<File?>? _firstSentFuture; // eager synthesis of first sentence
  bool _streamDone = false;
  bool _loopRunning = false;

  /// Ordered list of audio clips to play.
  final List<Future<File?>> _clipQueue = [];
  int _playIndex = 0;

  /// Cache: text hash → file path (last 50).
  final LinkedHashMap<int, String> _cache = LinkedHashMap();
  static const _maxCache = 50;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  // ---- Streaming API ----

  void beginStream(String universalApiKey) {
    _sessionId++;
    _player.stop().catchError((_) {});

    _rawBuffer = '';
    _firstSentSent = false;
    _firstSentFuture = null;
    _streamDone = false;
    _loopRunning = false;
    _isPlaying = false;
    _clipQueue.clear();
    _playIndex = 0;
    _apiKey = universalApiKey;
    _url = middlewareUrl(universalApiKey, '/v1/audio/speech');
  }

  void feedChunk(String chunk) {
    if (_url == null) return;
    _rawBuffer += chunk;

    // Only try to extract the FIRST sentence eagerly.
    // Everything else waits for endStream() to send as one batch.
    if (!_firstSentSent) {
      _tryExtractFirstSentence();
    }
  }

  void endStream() {
    if (_url == null) return;

    // Send ALL remaining text as ONE TTS call (saves ~2s per sentence)
    final remaining = sanitizeForTts(_rawBuffer).trim();
    _rawBuffer = '';

    if (remaining.isNotEmpty && remaining.split(RegExp(r'\s+')).length >= 2) {
      debugLog(DebugSource.tts,
          'Batch remaining: ${remaining.length}c');
      _clipQueue.add(_synthesize(remaining, _sessionId));
    }

    _streamDone = true;

    // If no first sentence was sent (very short response), start loop now
    if (!_loopRunning && _clipQueue.isNotEmpty) {
      _startPlayLoop();
    }
  }

  void _tryExtractFirstSentence() {
    final clean = sanitizeForTts(_rawBuffer);
    final match = _sentenceEndRe.firstMatch(clean);
    if (match == null) return;

    final sentence = clean.substring(0, match.end).trim();
    if (sentence.split(RegExp(r'\s+')).length < 3) return; // too short

    // Got first sentence! Send it immediately.
    _firstSentSent = true;
    _rawBuffer = clean.substring(match.end); // keep rest as raw (already sanitized)

    debugLog(DebugSource.tts,
        'First sentence: "${sentence.substring(0, sentence.length.clamp(0, 50))}" (${sentence.length}c)');

    _firstSentFuture = _synthesize(sentence, _sessionId);
    _clipQueue.add(_firstSentFuture!);

    _startPlayLoop();
  }

  // ---- Play loop ----

  void _startPlayLoop() {
    if (_loopRunning) return;
    final session = _sessionId;
    _loopRunning = true;
    _isPlaying = true;
    _playLoopAsync(session);
  }

  Future<void> _playLoopAsync(int session) async {
    while (session == _sessionId) {
      if (_playIndex >= _clipQueue.length) {
        if (_streamDone) break;
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }

      final audioFile = await _clipQueue[_playIndex];
      if (session != _sessionId) break;

      if (audioFile != null && await audioFile.length() > 100) {
        debugLog(DebugSource.tts, 'Playing clip #$_playIndex');
        await _playFile(audioFile, session);
      }

      _playIndex++;
    }

    if (session == _sessionId) {
      _loopRunning = false;
      _isPlaying = false;
    }
  }

  // ---- Synthesis ----

  Future<File?> _synthesize(String text, int session) async {
    if (session != _sessionId || _url == null || _apiKey == null) return null;

    final hash = text.hashCode;
    if (_cache.containsKey(hash)) {
      final cached = File(_cache[hash]!);
      if (await cached.exists()) return cached;
      _cache.remove(hash);
    }

    try {
      final response = await http.post(
        Uri.parse(_url!),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({'model': 'auto', 'input': text}),
      ).timeout(const Duration(seconds: 25));

      if (session != _sessionId) return null;
      if (response.statusCode != 200) return null;
      if (response.bodyBytes.length < 100) return null; // error response

      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'bude_tts_$hash.mp3'));
      await file.writeAsBytes(response.bodyBytes);

      _cache[hash] = file.path;
      if (_cache.length > _maxCache) {
        final oldKey = _cache.keys.first;
        final oldPath = _cache.remove(oldKey);
        if (oldPath != null) File(oldPath).delete().catchError((_) => File(oldPath));
      }

      return file;
    } catch (e) {
      debugLog(DebugSource.tts, 'Synthesis error: $e');
      return null;
    }
  }

  Future<void> _playFile(File file, int session) async {
    if (session != _sessionId) return;
    try {
      final completer = Completer<void>();
      late StreamSubscription sub;
      sub = _player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      });
      await _player.play(DeviceFileSource(file.path));
      await Future.any([
        completer.future,
        _waitForCancel(session),
      ]);
      if (!completer.isCompleted) {
        sub.cancel();
        await _player.stop();
      }
    } catch (e) {
      debugLog(DebugSource.tts, 'Play error: $e');
    }
  }

  Future<void> _waitForCancel(int session) async {
    while (session == _sessionId) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // ---- One-shot replay API ----

  Future<void> speakAndPlay(String text, String universalApiKey) async {
    beginStream(universalApiKey);
    _rawBuffer = text;
    _firstSentSent = true; // skip first-sentence logic, send all at once
    endStream();
    while (_loopRunning) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> stop() async {
    _sessionId++;
    _rawBuffer = '';
    _clipQueue.clear();
    _streamDone = true;
    _loopRunning = false;
    _isPlaying = false;
    await _player.stop();
  }

  void dispose() {
    _sessionId++;
    _clipQueue.clear();
    _player.dispose();
  }
}
