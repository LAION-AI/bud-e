/// Wake word detection service using ONNX runtime.
/// Pipeline: Audio (16kHz) -> Mel Spectrogram -> Speech Embeddings -> Classifier
/// Uses 3 ONNX models from livekit-wakeword project.
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

class WakeWordService {
  static const int sampleRate = 16000;
  static const int chunkDurationMs = 2000;
  static const int chunkSamples = 32000; // 2s at 16kHz
  static const double threshold = 0.1;
  static const int embeddingWindow = 76;
  static const int embeddingStride = 8;
  static const int minEmbeddings = 16;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _melSession;
  OrtSession? _embSession;
  OrtSession? _clsSession;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _sfxPlayer = AudioPlayer();
  Timer? _listenTimer;
  bool _isListening = false;
  bool _isProcessing = false;
  bool _modelsLoaded = false;
  DateTime _lastDetection = DateTime(2000);
  String? _beepPath;

  void Function()? onWakeWordDetected;

  bool get isListening => _isListening;
  bool get isReady => _modelsLoaded;

  Future<void> init() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final modelDir = Directory(p.join(tempDir.path, 'wakeword_models'));
      if (!await modelDir.exists()) await modelDir.create(recursive: true);

      final melPath = await _copyAsset('assets/melspectrogram.onnx', modelDir);
      final embPath = await _copyAsset('assets/embedding_model.onnx', modelDir);
      final clsPath = await _copyAsset('assets/hey_buddy_de_medium.onnx', modelDir);

      _melSession = await _ort.createSession(melPath);
      _embSession = await _ort.createSession(embPath);
      _clsSession = await _ort.createSession(clsPath);

      debugLog(DebugSource.system,
          'WakeWord loaded: mel inputs=${_melSession!.inputNames} outputs=${_melSession!.outputNames}');
      debugLog(DebugSource.system,
          'WakeWord loaded: emb inputs=${_embSession!.inputNames} outputs=${_embSession!.outputNames}');
      debugLog(DebugSource.system,
          'WakeWord loaded: cls inputs=${_clsSession!.inputNames} outputs=${_clsSession!.outputNames}');

      // Generate a short confirmation beep WAV
      _beepPath = p.join(modelDir.path, 'beep.wav');
      if (!File(_beepPath!).existsSync()) {
        await File(_beepPath!).writeAsBytes(_generateBeepWav());
      }

      _modelsLoaded = true;
    } catch (e) {
      debugLog(DebugSource.system, 'WakeWord init failed: $e');
    }
  }

  Future<String> _copyAsset(String assetPath, Directory targetDir) async {
    final filename = p.basename(assetPath);
    final targetPath = p.join(targetDir.path, filename);
    if (!File(targetPath).existsSync()) {
      final data = await rootBundle.load(assetPath);
      await File(targetPath).writeAsBytes(data.buffer.asUint8List());
    }
    return targetPath;
  }

  Future<void> startListening() async {
    if (!_modelsLoaded || _isListening) return;
    _isListening = true;
    debugLog(DebugSource.system, 'WakeWord: start listening');
    _listenTimer = Timer.periodic(
      const Duration(milliseconds: chunkDurationMs + 200), // small gap
      (_) => _recordAndProcess(),
    );
    _recordAndProcess();
  }

  void stopListening() {
    _isListening = false;
    _listenTimer?.cancel();
    _listenTimer = null;
    _recorder.stop();
    debugLog(DebugSource.system, 'WakeWord: stopped');
  }

  Future<void> _recordAndProcess() async {
    if (!_isListening || _isProcessing) return;
    _isProcessing = true;

    try {
      if (!await _recorder.hasPermission()) {
        _isProcessing = false;
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final wavPath = p.join(tempDir.path, 'ww_chunk.wav');

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: wavPath,
      );

      await Future.delayed(const Duration(milliseconds: chunkDurationMs));
      final path = await _recorder.stop();
      if (path == null) { _isProcessing = false; return; }

      final wavBytes = await File(path).readAsBytes();
      final pcm = _wavToFloat32(wavBytes);
      if (pcm == null || pcm.length < 8000) {
        _isProcessing = false;
        return;
      }

      final score = await _detect(pcm);
      debugLog(DebugSource.system, 'WakeWord score: ${score.toStringAsFixed(3)}');

      if (score > threshold) {
        // Debounce: ignore detections within 3 seconds of each other
        final now = DateTime.now();
        if (now.difference(_lastDetection).inSeconds < 3) return;
        _lastDetection = now;

        debugLog(DebugSource.system, 'WakeWord DETECTED! score=${score.toStringAsFixed(3)}');

        // Play confirmation beep
        if (_beepPath != null) {
          try {
            await _sfxPlayer.play(DeviceFileSource(_beepPath!));
          } catch (_) {}
        }

        // Bring window to foreground (Windows)
        _bringToForeground();

        onWakeWordDetected?.call();
      }
    } catch (e) {
      debugLog(DebugSource.system, 'WakeWord error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<double> _detect(Float32List audio) async {
    if (_melSession == null || _embSession == null || _clsSession == null) return 0.0;

    try {
      // Stage 1: Mel spectrogram
      final melInputName = _melSession!.inputNames.first;
      final melInput = await OrtValue.fromList(
        Float32List.fromList(audio),
        [1, audio.length],
      );
      final melOutputs = await _melSession!.run({melInputName: melInput});
      final melValue = melOutputs.values.first;
      await melInput.dispose();

      // Get flattened mel data and apply post-processing: x/10 + 2
      final melFlat = await melValue.asFlattenedList();
      final melShape = melValue.shape;
      await melValue.dispose();

      // Determine time frames: shape is typically (1, 1, time, 32) or (1, time, 32)
      final nMels = 32;
      final totalMelValues = melFlat.length;
      final timeFrames = totalMelValues ~/ nMels;
      // Account for batch dim
      final effectiveTime = melShape.length >= 3
          ? melShape[melShape.length - 2]
          : timeFrames;

      if (effectiveTime < embeddingWindow) return 0.0;

      // Apply normalization: x/10 + 2
      final melNorm = Float32List(totalMelValues);
      for (var i = 0; i < totalMelValues; i++) {
        melNorm[i] = (melFlat[i] as num).toDouble() / 10.0 + 2.0;
      }

      // Stage 2: Extract embeddings with sliding window
      final embInputName = _embSession!.inputNames.first;
      final embeddings = <List<double>>[];

      for (var start = 0; start <= effectiveTime - embeddingWindow; start += embeddingStride) {
        final window = Float32List(embeddingWindow * nMels);
        for (var t = 0; t < embeddingWindow; t++) {
          for (var m = 0; m < nMels; m++) {
            // Skip batch dimension values
            final srcIdx = start * nMels + t * nMels + m;
            if (srcIdx < melNorm.length) {
              window[t * nMels + m] = melNorm[srcIdx];
            }
          }
        }

        // Input: (1, 76, 32, 1) channels-last
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

        if (embeddings.length >= minEmbeddings) break; // got enough
      }

      if (embeddings.length < minEmbeddings) return 0.0;

      // Stage 3: Classification — (1, 16, 96)
      final clsInputName = _clsSession!.inputNames.first;
      final last16 = embeddings.sublist(embeddings.length - minEmbeddings);
      final clsData = Float32List(minEmbeddings * 96);
      for (var i = 0; i < minEmbeddings; i++) {
        for (var j = 0; j < 96; j++) {
          clsData[i * 96 + j] = last16[i][j];
        }
      }

      final clsInput = await OrtValue.fromList(clsData, [1, minEmbeddings, 96]);
      final clsOutputs = await _clsSession!.run({clsInputName: clsInput});
      final scoreValue = clsOutputs.values.first;
      final scoreFlat = await scoreValue.asFlattenedList();
      await clsInput.dispose();
      await scoreValue.dispose();

      return scoreFlat.isNotEmpty ? (scoreFlat.first as num).toDouble() : 0.0;
    } catch (e) {
      debugLog(DebugSource.system, 'WakeWord pipeline error: $e');
      return 0.0;
    }
  }

  static Float32List? _wavToFloat32(Uint8List wav) {
    if (wav.length < 44) return null;
    if (wav[0] != 0x52 || wav[1] != 0x49) return null;

    var offset = 12;
    while (offset < wav.length - 8) {
      final chunkId = String.fromCharCodes(wav.sublist(offset, offset + 4));
      final chunkSize = wav.buffer.asByteData().getUint32(offset + 4, Endian.little);
      if (chunkId == 'data') {
        final dataStart = offset + 8;
        final dataEnd = (dataStart + chunkSize).clamp(0, wav.length);
        final samples = (dataEnd - dataStart) ~/ 2;
        final pcm = Float32List(samples);
        final bd = wav.buffer.asByteData();
        for (var i = 0; i < samples; i++) {
          pcm[i] = bd.getInt16(dataStart + i * 2, Endian.little) / 32768.0;
        }
        return pcm;
      }
      offset += 8 + chunkSize;
      if (chunkSize % 2 != 0) offset++;
    }
    return null;
  }

  /// Bring app window to foreground and maximize (Windows).
  void _bringToForeground() {
    if (!Platform.isWindows) return;
    // Use PowerShell to find and activate the Flutter window
    Process.run('powershell', ['-Command',
      'Add-Type @"',
      'using System;',
      'using System.Runtime.InteropServices;',
      'public class WW {',
      '  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);',
      '  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);',
      '}',
      '"@;',
      r'$p = Get-Process -Name "school_bud_e_flutter" -EA 0 | Select -First 1;',
      r'if ($p) { [WW]::ShowWindow($p.MainWindowHandle, 3); [WW]::SetForegroundWindow($p.MainWindowHandle) }',
    ]).catchError((_) {});
  }

  /// Generate a short 440Hz beep as WAV (0.3 seconds).
  static Uint8List _generateBeepWav() {
    const sr = 16000;
    const duration = 0.3;
    const freq = 880.0; // A5
    final samples = (sr * duration).toInt();
    final data = Int16List(samples);
    for (var i = 0; i < samples; i++) {
      final t = i / sr;
      final envelope = (1.0 - t / duration); // fade out
      data[i] = (sin(2 * pi * freq * t) * 16000 * envelope).toInt().clamp(-32768, 32767);
    }
    // Build WAV header
    final dataBytes = data.buffer.asUint8List();
    final wav = BytesBuilder();
    wav.add(utf8.encode('RIFF'));
    wav.add(_leU32(36 + dataBytes.length));
    wav.add(utf8.encode('WAVE'));
    wav.add(utf8.encode('fmt '));
    wav.add(_leU32(16)); // chunk size
    wav.add(_leU16(1)); // PCM
    wav.add(_leU16(1)); // mono
    wav.add(_leU32(sr)); // sample rate
    wav.add(_leU32(sr * 2)); // byte rate
    wav.add(_leU16(2)); // block align
    wav.add(_leU16(16)); // bits per sample
    wav.add(utf8.encode('data'));
    wav.add(_leU32(dataBytes.length));
    wav.add(dataBytes);
    return wav.toBytes();
  }

  static Uint8List _leU16(int v) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
  static Uint8List _leU32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

  void dispose() {
    stopListening();
    _melSession?.close();
    _embSession?.close();
    _clsSession?.close();
    _sfxPlayer.dispose();
    _recorder.dispose();
  }
}
