/// Automatic Speech Recognition service — records audio and sends it
/// to the middleware for transcription (Whisper-compatible).
library;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/api_config.dart';
import 'debug_log.dart';

class AsrService {
  AudioRecorder? _recorder;
  String? _currentPath;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  AudioRecorder _getRecorder() {
    _recorder ??= AudioRecorder();
    return _recorder!;
  }

  /// Start recording audio from the microphone.
  Future<bool> startRecording() async {
    if (_isRecording) return false;

    final recorder = _getRecorder();

    try {
      final hasPermission = await recorder.hasPermission();
      debugLog(DebugSource.asr, 'hasPermission: $hasPermission');
      if (!hasPermission) {
        debugLog(DebugSource.asr, 'Microphone permission denied');
        return false;
      }
    } catch (e) {
      debugLog(DebugSource.asr, 'Permission check error: $e');
      return false;
    }

    try {
      final dir = await getTemporaryDirectory();
      // Use WAV on Windows (AAC may not be available), m4a on mobile
      final ext = Platform.isWindows ? 'wav' : 'm4a';
      final encoder = Platform.isWindows ? AudioEncoder.wav : AudioEncoder.aacLc;
      _currentPath = p.join(dir.path, 'bude_asr_${DateTime.now().millisecondsSinceEpoch}.$ext');

      debugLog(DebugSource.asr, 'Starting recording: encoder=$encoder path=$_currentPath');

      await recorder.start(
        RecordConfig(
          encoder: encoder,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentPath!,
      );
      _isRecording = true;
      debugLog(DebugSource.asr, 'Recording started');
      return true;
    } catch (e) {
      debugLog(DebugSource.asr, 'Failed to start recording: $e');
      _isRecording = false;
      return false;
    }
  }

  /// Stop recording and transcribe via the middleware.
  ///
  /// Returns the transcribed text, or `null` on failure.
  Future<String?> stopAndTranscribe(String universalApiKey) async {
    if (!_isRecording || _currentPath == null) {
      debugLog(DebugSource.asr, 'stopAndTranscribe: not recording');
      return null;
    }

    final recorder = _getRecorder();

    String? path;
    try {
      path = await recorder.stop();
      debugLog(DebugSource.asr, 'Recording stopped, path: $path');
    } catch (e) {
      debugLog(DebugSource.asr, 'Error stopping recorder: $e');
    }
    _isRecording = false;

    // Use the path returned by stop(), fall back to _currentPath
    final filePath = path ?? _currentPath!;
    final file = File(filePath);
    if (!await file.exists()) {
      debugLog(DebugSource.asr, 'Audio file not found: $filePath');
      return null;
    }

    final fileSize = await file.length();
    debugLog(DebugSource.asr, 'Audio file size: $fileSize bytes');

    if (fileSize < 100) {
      debugLog(DebugSource.asr, 'Audio file too small, likely empty recording');
      await file.delete().catchError((_) => file);
      return null;
    }

    final url = middlewareUrl(universalApiKey, '/v1/audio/transcriptions');
    if (url == null) {
      debugLog(DebugSource.asr, 'Could not decode middleware URL');
      await file.delete().catchError((_) => file);
      return null;
    }

    debugLog(DebugSource.asr, 'Sending to ASR: $url');

    try {
      final request = http.MultipartRequest('POST', Uri.parse(url))
        ..headers['Authorization'] = 'Bearer $universalApiKey'
        ..fields['model'] = 'whisper-1'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamedResp = await request.send();
      final body = await streamedResp.stream.bytesToString();

      await file.delete().catchError((_) => file);

      debugLog(DebugSource.asr, 'ASR response: ${streamedResp.statusCode}, body length: ${body.length}');

      if (streamedResp.statusCode != 200) {
        debugLog(DebugSource.asr, 'ASR error: $body');
        return null;
      }

      // The middleware may return plain text or JSON {"text": "..."}.
      String? text;
      if (body.trim().startsWith('{')) {
        try {
          final map = jsonDecode(body) as Map<String, dynamic>;
          text = map['text'] as String?;
        } catch (_) {
          text = body.trim();
        }
      } else {
        text = body.trim();
      }

      debugLog(DebugSource.asr, 'Transcribed: "$text"');
      return text;
    } catch (e) {
      debugLog(DebugSource.asr, 'ASR request failed: $e');
      await file.delete().catchError((_) => file);
      return null;
    }
  }

  void dispose() {
    _recorder?.dispose();
    _recorder = null;
  }
}
