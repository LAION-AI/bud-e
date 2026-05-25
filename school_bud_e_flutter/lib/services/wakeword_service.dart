/// Wake word detection service using ONNX runtime.
/// Supports multiple wake words: Hey Buddy, Stop Buddy, Go Buddy.
/// State machine: IDLE→(hey buddy)→RECORDING→(go buddy=submit, stop buddy=cancel)
/// During TTS playback: stop buddy = stop TTS.
///
/// Uses continuous PCM streaming so audio is never lost during inference.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'debug_log.dart';

enum WakeWordState { idle, recording }

class WakeWordScore {
  final double heyBuddy;
  final double stopBuddy;
  final double goBuddy;
  final double rms;
  final DateTime time;
  WakeWordScore({required this.heyBuddy, required this.stopBuddy,
      required this.goBuddy, required this.rms, DateTime? time})
      : time = time ?? DateTime.now();
}

class WakeWordService {
  static const int sampleRate = 16000;
  static const int windowSamples = 32000; // 2s analysis window
  static const int analyzeIntervalMs = 500; // analyze every 500ms
  static const double heyThreshold = 0.5;
  static const double stopThreshold = 0.5;
  static const double goThreshold = 0.5;
  static const int embeddingWindow = 76;
  static const int embeddingStride = 8;
  static const int minEmbeddings = 16;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _melSession;
  OrtSession? _embSession;
  OrtSession? _heySession;
  OrtSession? _stopSession;
  OrtSession? _goSession;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  StreamSubscription<Uint8List>? _streamSub;
  Timer? _analysisTimer;
  bool _isListening = false;
  bool _isProcessing = false;
  bool _modelsLoaded = false;
  DateTime _lastDetection = DateTime(2000);
  String? _beepPath;
  bool _shapeLogged = false;
  int _inferenceErrors = 0;

  final Float32List _ringBuffer = Float32List(windowSamples);
  int _ringFilled = 0;

  WakeWordState state = WakeWordState.idle;

  // Callbacks
  void Function()? onHeyBuddy;  // detected "hey buddy"
  void Function()? onGoBuddy;   // detected "go buddy" (submit recording)
  void Function()? onStopBuddy; // detected "stop buddy" (cancel/stop TTS)

  InputDevice? selectedDevice;
  List<InputDevice> availableDevices = [];

  // Score history for debug screen
  final List<WakeWordScore> scoreHistory = [];
  static const int maxHistory = 200;

  bool get isListening => _isListening;
  bool get isReady => _modelsLoaded;

  Future<void> init() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final modelDir = Directory(p.join(tempDir.path, 'wakeword_models'));
      if (!await modelDir.exists()) await modelDir.create(recursive: true);

      final melPath = await _copyAsset('assets/melspectrogram.onnx', modelDir);
      final embPath = await _copyAsset('assets/embedding_model.onnx', modelDir);

      // Use medium models on Android (large v3 causes native crashes on some devices)
      // Use large v3 on desktop where they're stable and fast
      final String modelSize;
      if (Platform.isAndroid) {
        modelSize = 'medium';
        final heyPath = await _copyAsset('assets/hey_buddy_en_medium.onnx', modelDir);
        final stopPath = await _copyAsset('assets/stop_buddy_en_medium.onnx', modelDir);
        final goPath = await _copyAsset('assets/go_buddy_en_medium.onnx', modelDir);
        _melSession = await _ort.createSession(melPath);
        _embSession = await _ort.createSession(embPath);
        _heySession = await _ort.createSession(heyPath);
        _stopSession = await _ort.createSession(stopPath);
        _goSession = await _ort.createSession(goPath);
      } else {
        modelSize = 'large_v3';
        final heyPath = await _copyAsset('assets/hey_buddy_en_large_v3.onnx', modelDir);
        final stopPath = await _copyAsset('assets/stop_buddy_en_large_v3.onnx', modelDir);
        final goPath = await _copyAsset('assets/go_buddy_en_large_v3.onnx', modelDir);
        _melSession = await _ort.createSession(melPath);
        _embSession = await _ort.createSession(embPath);
        _heySession = await _ort.createSession(heyPath);
        _stopSession = await _ort.createSession(stopPath);
        _goSession = await _ort.createSession(goPath);
      }

      debugLog(DebugSource.system, 'WakeWord: 5 ONNX models loaded ($modelSize)');

      try {
        availableDevices = await _recorder.listInputDevices();
        debugLog(DebugSource.system,
            'WakeWord: ${availableDevices.length} mics: ${availableDevices.map((d) => d.label).join(", ")}');
      } catch (_) {}

      _beepPath = p.join(modelDir.path, 'beep.wav');
      if (!File(_beepPath!).existsSync()) {
        await File(_beepPath!).writeAsBytes(_generateBeepWav());
      }

      _modelsLoaded = true;
    } catch (e, st) {
      debugLog(DebugSource.system, 'WakeWord init failed: $e\n$st');
      // Clean up partially loaded sessions
      _melSession = null;
      _embSession = null;
      _heySession = null;
      _stopSession = null;
      _goSession = null;
      _modelsLoaded = false;
    }
  }

  Future<String> _copyAsset(String assetPath, Directory targetDir) async {
    final filename = p.basename(assetPath);
    final targetPath = p.join(targetDir.path, filename);
    // Always re-copy to ensure latest model
    final data = await rootBundle.load(assetPath);
    await File(targetPath).writeAsBytes(data.buffer.asUint8List());
    return targetPath;
  }

  Future<void> startListening() async {
    if (!_modelsLoaded || _isListening) return;
    _isListening = true;
    _ringFilled = 0;
    debugLog(DebugSource.system, 'WakeWord: start listening (streaming)');

    try {
      if (!await _recorder.hasPermission()) {
        debugLog(DebugSource.system, 'WakeWord: no mic permission');
        _isListening = false;
        return;
      }

      final stream = await _recorder.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        device: selectedDevice,
      ));

      _streamSub = stream.listen(
        (bytes) => _appendPcmBytes(bytes),
        onError: (e) => debugLog(DebugSource.system, 'WW stream error: $e'),
        onDone: () {
          debugLog(DebugSource.system, 'WW stream ended');
          _isListening = false;
        },
      );

      // Analyze the ring buffer periodically — audio keeps flowing
      // even while inference is running
      _analysisTimer = Timer.periodic(
        const Duration(milliseconds: analyzeIntervalMs),
        (_) => _analyzeRingBuffer(),
      );

      debugLog(DebugSource.system, 'WakeWord: streaming started');
    } catch (e) {
      debugLog(DebugSource.system, 'WW stream start failed: $e');
      _isListening = false;
    }
  }

  void stopListening() {
    _isListening = false;
    _streamSub?.cancel();
    _streamSub = null;
    _analysisTimer?.cancel();
    _analysisTimer = null;
    _recorder.stop();
    _ringFilled = 0;
    debugLog(DebugSource.system, 'WakeWord: stopped');
  }

  /// Append raw PCM16 little-endian bytes to the ring buffer.
  /// Called from the stream listener — runs on every audio chunk,
  /// even while ONNX inference is in progress.
  void _appendPcmBytes(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    if (sampleCount == 0) return;

    final bd = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length);
    final newLen = sampleCount.clamp(0, windowSamples);

    // Slide ring buffer if full
    if (_ringFilled + newLen > windowSamples) {
      final shift = (_ringFilled + newLen) - windowSamples;
      final remaining = _ringFilled - shift;
      for (var i = 0; i < remaining; i++) {
        _ringBuffer[i] = _ringBuffer[i + shift];
      }
      _ringFilled = remaining;
    }

    // Append new samples (int16 → float32)
    for (var i = 0; i < newLen; i++) {
      _ringBuffer[_ringFilled + i] =
          bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    _ringFilled += newLen;
  }

  /// Analyze the current ring buffer contents.
  /// Skips if inference is already running (but audio keeps accumulating).
  Future<void> _analyzeRingBuffer() async {
    if (!_isListening || _isProcessing) return;
    if (_ringFilled < windowSamples) return; // need full 2s window
    _isProcessing = true;

    try {
      // Snapshot the ring buffer (so stream can keep writing)
      final window = Float32List(_ringFilled);
      for (var i = 0; i < _ringFilled; i++) window[i] = _ringBuffer[i];

      final rms = window.fold<double>(0, (s, v) => s + v * v) / window.length;

      // Extract embeddings once, run all classifiers — with timing
      final t0 = DateTime.now();
      final embeddings = await _extractEmbeddings(window);
      final t1 = DateTime.now();
      if (embeddings == null) { _isProcessing = false; return; }

      final heyScore = await _classify(_heySession!, embeddings);
      final t2 = DateTime.now();
      final stopScore = await _classify(_stopSession!, embeddings);
      final t3 = DateTime.now();
      final goScore = await _classify(_goSession!, embeddings);
      final t4 = DateTime.now();

      final embMs = t1.difference(t0).inMilliseconds;
      final heyMs = t2.difference(t1).inMilliseconds;
      final stopMs = t3.difference(t2).inMilliseconds;
      final goMs = t4.difference(t3).inMilliseconds;
      final totalMs = t4.difference(t0).inMilliseconds;

      // Store in history
      scoreHistory.add(WakeWordScore(
        heyBuddy: heyScore, stopBuddy: stopScore, goBuddy: goScore, rms: rms));
      if (scoreHistory.length > maxHistory) scoreHistory.removeAt(0);

      debugLog(DebugSource.system,
          'WW hey=${heyScore.toStringAsFixed(3)} stop=${stopScore.toStringAsFixed(3)} '
          'go=${goScore.toStringAsFixed(3)} [${state.name}] '
          '⏱ emb=${embMs}ms hey=${heyMs}ms stop=${stopMs}ms go=${goMs}ms total=${totalMs}ms');

      // Debounce — 2s cooldown after any activation
      final now = DateTime.now();
      if (now.difference(_lastDetection).inMilliseconds < 2000) {
        _isProcessing = false;
        return;
      }

      // Find the highest-scoring wake word above threshold (mutual exclusion)
      final candidates = <String, double>{};
      if (heyScore > heyThreshold) candidates['hey'] = heyScore;
      if (stopScore > stopThreshold) candidates['stop'] = stopScore;
      if (goScore > goThreshold) candidates['go'] = goScore;

      if (candidates.isEmpty) { _isProcessing = false; return; }

      // Pick the winner — highest score wins
      final winner = candidates.entries.reduce(
          (a, b) => a.value >= b.value ? a : b).key;

      _lastDetection = now;

      // State machine — only fire the winner
      switch (state) {
        case WakeWordState.idle:
          if (winner == 'hey') {
            debugLog(DebugSource.system, 'WW: HEY BUDDY detected! → start recording');
            _playBeep();
            _bringToForeground();
            onHeyBuddy?.call();
          } else if (winner == 'stop') {
            debugLog(DebugSource.system, 'WW: STOP BUDDY (idle) → stop TTS');
            onStopBuddy?.call();
          }
          // Ignore go buddy while idle

        case WakeWordState.recording:
          if (winner == 'go') {
            debugLog(DebugSource.system, 'WW: GO BUDDY → submit recording');
            _playBeep();
            onGoBuddy?.call();
          } else if (winner == 'stop') {
            debugLog(DebugSource.system, 'WW: STOP BUDDY → cancel recording');
            onStopBuddy?.call();
          }
          // Ignore hey buddy while recording
      }
    } catch (e) {
      _inferenceErrors++;
      debugLog(DebugSource.system, 'WakeWord error (#$_inferenceErrors): $e');
      if (_inferenceErrors >= 3) {
        debugLog(DebugSource.system, 'WakeWord: too many errors, disabling');
        stopListening();
        _modelsLoaded = false;
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Extract embeddings from audio (stages 1+2).
  Future<Float32List?> _extractEmbeddings(Float32List audio) async {
    if (_melSession == null || _embSession == null) return null;

    try {
      final melInputName = _melSession!.inputNames.first;
      final melInput = await OrtValue.fromList(Float32List.fromList(audio), [1, audio.length]);
      final melOutputs = await _melSession!.run({melInputName: melInput});
      final melValue = melOutputs.values.first;
      await melInput.dispose();

      final melFlat = await melValue.asFlattenedList();
      final melShape = melValue.shape;
      await melValue.dispose();

      if (!_shapeLogged) {
        debugLog(DebugSource.system, 'WW mel shape=$melShape');
        _shapeLogged = true;
      }

      const nMels = 32;
      final effectiveTime = melShape[melShape.length - 2];
      if (effectiveTime < embeddingWindow) return null;

      final melCount = effectiveTime * nMels;
      final melOffset = melFlat.length - melCount;
      final melNorm = Float32List(melCount);
      for (var i = 0; i < melCount; i++) {
        melNorm[i] = (melFlat[melOffset + i] as num).toDouble() / 10.0 + 2.0;
      }

      final embInputName = _embSession!.inputNames.first;
      final embeddings = <List<double>>[];

      for (var start = 0; start <= effectiveTime - embeddingWindow; start += embeddingStride) {
        final window = Float32List(embeddingWindow * nMels);
        for (var t = 0; t < embeddingWindow; t++) {
          for (var m = 0; m < nMels; m++) {
            final srcIdx = (start + t) * nMels + m;
            if (srcIdx < melNorm.length) window[t * nMels + m] = melNorm[srcIdx];
          }
        }

        final embInput = await OrtValue.fromList(window, [1, embeddingWindow, nMels, 1]);
        final embOutputs = await _embSession!.run({embInputName: embInput});
        final embValue = embOutputs.values.first;
        final embFlat = await embValue.asFlattenedList();
        await embInput.dispose();
        await embValue.dispose();

        if (embFlat.length >= 96) {
          embeddings.add(embFlat.sublist(embFlat.length - 96)
              .map((v) => (v as num).toDouble()).toList());
        }
        if (embeddings.length >= minEmbeddings) break;
      }

      if (embeddings.length < minEmbeddings) return null;

      // Pack last 16 embeddings into flat array
      final last16 = embeddings.sublist(embeddings.length - minEmbeddings);
      final result = Float32List(minEmbeddings * 96);
      for (var i = 0; i < minEmbeddings; i++) {
        for (var j = 0; j < 96; j++) result[i * 96 + j] = last16[i][j];
      }
      return result;
    } catch (e) {
      debugLog(DebugSource.system, 'WW embedding error: $e');
      return null;
    }
  }

  /// Run a single classifier on pre-extracted embeddings.
  Future<double> _classify(OrtSession session, Float32List embeddings) async {
    try {
      final inputName = session.inputNames.first;
      final input = await OrtValue.fromList(embeddings, [1, minEmbeddings, 96]);
      final outputs = await session.run({inputName: input});
      final scoreValue = outputs.values.first;
      final scoreFlat = await scoreValue.asFlattenedList();
      await input.dispose();
      await scoreValue.dispose();
      return scoreFlat.isNotEmpty ? (scoreFlat.first as num).toDouble() : 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  void _playBeep() {
    if (_beepPath != null) {
      _sfxPlayer.play(DeviceFileSource(_beepPath!)).catchError((_) {});
    }
  }

  Future<void> _bringToForeground() async {
    if (Platform.isWindows) {
      try {
        final tempDir = await getTemporaryDirectory();
        final scriptPath = p.join(tempDir.path, 'ww_foreground.ps1');
        final script = '''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class FGHelper {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@
\$proc = Get-Process -Name "school_bud_e_flutter" -ErrorAction SilentlyContinue | Select-Object -First 1
if (\$proc -and \$proc.MainWindowHandle -ne [IntPtr]::Zero) {
    \$hwnd = \$proc.MainWindowHandle
    if ([FGHelper]::IsIconic(\$hwnd)) { [FGHelper]::ShowWindow(\$hwnd, 9) }
    if ([FGHelper]::GetForegroundWindow() -ne \$hwnd) { [FGHelper]::SetForegroundWindow(\$hwnd) }
}
''';
        await File(scriptPath).writeAsString(script);
        await Process.run('powershell', ['-ExecutionPolicy', 'Bypass', '-File', scriptPath]);
      } catch (_) {}
    } else if (Platform.isAndroid) {
      try {
        // Native side checks if already in foreground — safe to call always
        const channel = MethodChannel('com.laion.bude/wakeword');
        await channel.invokeMethod('bringToForeground');
      } catch (_) {}
    }
  }

  static Uint8List _generateBeepWav() {
    const sr = 16000; const duration = 0.3; const freq = 880.0;
    final samples = (sr * duration).toInt();
    final data = Int16List(samples);
    for (var i = 0; i < samples; i++) {
      final t = i / sr;
      data[i] = (sin(2 * pi * freq * t) * 16000 * (1.0 - t / duration)).toInt().clamp(-32768, 32767);
    }
    final dataBytes = data.buffer.asUint8List();
    final wav = BytesBuilder();
    wav.add(utf8.encode('RIFF')); wav.add(_leU32(36 + dataBytes.length));
    wav.add(utf8.encode('WAVE')); wav.add(utf8.encode('fmt '));
    wav.add(_leU32(16)); wav.add(_leU16(1)); wav.add(_leU16(1));
    wav.add(_leU32(sr)); wav.add(_leU32(sr * 2)); wav.add(_leU16(2)); wav.add(_leU16(16));
    wav.add(utf8.encode('data')); wav.add(_leU32(dataBytes.length)); wav.add(dataBytes);
    return wav.toBytes();
  }

  static Uint8List _leU16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
  static Uint8List _leU32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

  void dispose() {
    stopListening();
    _melSession?.close(); _embSession?.close();
    _heySession?.close(); _stopSession?.close(); _goSession?.close();
    _sfxPlayer.dispose(); _recorder.dispose();
  }
}
