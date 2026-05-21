/// Wake word detection service using ONNX runtime.
/// Pipeline: Audio (16kHz) -> Mel Spectrogram -> Speech Embeddings -> Classifier
/// Uses sliding window: records continuously, infers every 0.5s on last 2.5s.
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
  static const int windowSamples = 40000; // 2.5s ring buffer
  static const int slideSamples = 8000;   // 0.5s slide
  static const int recordChunkMs = 600;   // record slightly more than 0.5s
  static const double threshold = 0.15;
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
  bool _shapeLogged = false;

  // Ring buffer for sliding window
  final Float32List _ringBuffer = Float32List(windowSamples);
  int _ringFilled = 0; // how many valid samples in buffer

  void Function()? onWakeWordDetected;
  InputDevice? selectedDevice;
  List<InputDevice> availableDevices = [];

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
          'WakeWord loaded: mel=${_melSession!.inputNames} emb=${_embSession!.inputNames} cls=${_clsSession!.inputNames}');

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

  /// Start continuous listening with sliding window.
  Future<void> startListening() async {
    if (!_modelsLoaded || _isListening) return;
    _isListening = true;
    _ringFilled = 0;
    debugLog(DebugSource.system, 'WakeWord: start listening (sliding window)');

    // Record chunks every 0.5s and slide into ring buffer
    _listenTimer = Timer.periodic(
      const Duration(milliseconds: recordChunkMs + 100),
      (_) => _recordSlice(),
    );
    _recordSlice(); // start immediately
  }

  void stopListening() {
    _isListening = false;
    _listenTimer?.cancel();
    _listenTimer = null;
    _recorder.stop();
    _ringFilled = 0;
    debugLog(DebugSource.system, 'WakeWord: stopped');
  }

  /// Record a 0.5s chunk, append to ring buffer, then run inference on full 2.5s window.
  Future<void> _recordSlice() async {
    if (!_isListening || _isProcessing) return;
    _isProcessing = true;

    try {
      if (!await _recorder.hasPermission()) {
        _isProcessing = false;
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final wavPath = p.join(tempDir.path, 'ww_slice.wav');

      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: 1,
          bitRate: 256000,
          device: selectedDevice,
        ),
        path: wavPath,
      );

      await Future.delayed(const Duration(milliseconds: recordChunkMs));
      final path = await _recorder.stop();
      if (path == null) { _isProcessing = false; return; }

      final wavBytes = await File(path).readAsBytes();
      final newPcm = _wavToFloat32(wavBytes);
      if (newPcm == null || newPcm.isEmpty) {
        _isProcessing = false;
        return;
      }

      // Slide ring buffer: shift old data left, append new data
      final newLen = newPcm.length.clamp(0, windowSamples);
      if (_ringFilled + newLen > windowSamples) {
        // Shift left to make room
        final shift = (_ringFilled + newLen) - windowSamples;
        final remaining = _ringFilled - shift;
        for (var i = 0; i < remaining; i++) {
          _ringBuffer[i] = _ringBuffer[i + shift];
        }
        _ringFilled = remaining;
      }
      for (var i = 0; i < newLen; i++) {
        _ringBuffer[_ringFilled + i] = newPcm[i];
      }
      _ringFilled += newLen;

      // Need at least ~2s of audio to get enough mel frames
      if (_ringFilled < 32000) {
        _isProcessing = false;
        return;
      }

      // Run inference on the current window
      final window = Float32List.sublistView(_ringBuffer, 0, _ringFilled);
      final rms = window.fold<double>(0, (s, v) => s + v * v) / window.length;

      final score = await _detect(window);
      debugLog(DebugSource.system,
          'WakeWord score: ${score.toStringAsFixed(3)} '
          '(samples=${window.length}, rms=${rms.toStringAsFixed(6)})');

      if (score > threshold) {
        final now = DateTime.now();
        if (now.difference(_lastDetection).inSeconds < 3) {
          _isProcessing = false;
          return;
        }
        _lastDetection = now;

        debugLog(DebugSource.system, 'WakeWord DETECTED! score=${score.toStringAsFixed(3)}');

        if (_beepPath != null) {
          try { await _sfxPlayer.play(DeviceFileSource(_beepPath!)); } catch (_) {}
        }
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
        Float32List.fromList(audio), [1, audio.length],
      );
      final melOutputs = await _melSession!.run({melInputName: melInput});
      final melValue = melOutputs.values.first;
      await melInput.dispose();

      final melFlat = await melValue.asFlattenedList();
      final melShape = melValue.shape;
      await melValue.dispose();

      if (!_shapeLogged) {
        debugLog(DebugSource.system,
            'WakeWord mel shape=$melShape, flat=${melFlat.length}');
        _shapeLogged = true;
      }

      // Shape: (1, 1, time, 32) or (1, time, 32)
      const nMels = 32;
      final effectiveTime = melShape[melShape.length - 2];

      if (effectiveTime < embeddingWindow) return 0.0;

      // Normalize: x/10 + 2
      final melCount = effectiveTime * nMels;
      final melOffset = melFlat.length - melCount;
      final melNorm = Float32List(melCount);
      for (var i = 0; i < melCount; i++) {
        melNorm[i] = (melFlat[melOffset + i] as num).toDouble() / 10.0 + 2.0;
      }

      // Stage 2: Extract embeddings
      final embInputName = _embSession!.inputNames.first;
      final embeddings = <List<double>>[];

      for (var start = 0; start <= effectiveTime - embeddingWindow; start += embeddingStride) {
        final window = Float32List(embeddingWindow * nMels);
        for (var t = 0; t < embeddingWindow; t++) {
          for (var m = 0; m < nMels; m++) {
            final srcIdx = (start + t) * nMels + m;
            if (srcIdx < melNorm.length) {
              window[t * nMels + m] = melNorm[srcIdx];
            }
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

  Future<void> _bringToForeground() async {
    debugLog(DebugSource.system, 'WakeWord: bringing to foreground...');
    if (Platform.isWindows) {
      // Write a temp PS1 script and execute it
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
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@
\$proc = Get-Process -Name "school_bud_e_flutter" -ErrorAction SilentlyContinue | Select-Object -First 1
if (\$proc -and \$proc.MainWindowHandle -ne [IntPtr]::Zero) {
    \$hwnd = \$proc.MainWindowHandle
    \$isForeground = [FGHelper]::GetForegroundWindow() -eq \$hwnd
    \$isMaximized = [FGHelper]::IsZoomed(\$hwnd)
    if ([FGHelper]::IsIconic(\$hwnd)) {
        [FGHelper]::ShowWindow(\$hwnd, 9)  # SW_RESTORE
    }
    if (-not \$isForeground) {
        [FGHelper]::SetForegroundWindow(\$hwnd)
    }
    if (-not \$isMaximized) {
        Start-Sleep -Milliseconds 100
        [FGHelper]::ShowWindow(\$hwnd, 3)  # SW_MAXIMIZE
    }
}
''';
        await File(scriptPath).writeAsString(script);
        await Process.run('powershell', ['-ExecutionPolicy', 'Bypass', '-File', scriptPath]);
      } catch (e) {
        debugLog(DebugSource.system, 'WakeWord foreground error: $e');
      }
    } else if (Platform.isAndroid) {
      // Use Flutter's platform channel to bring activity to front
      try {
        const channel = MethodChannel('com.laion.bude/wakeword');
        await channel.invokeMethod('bringToForeground');
      } catch (e) {
        debugLog(DebugSource.system, 'WakeWord Android foreground error: $e');
      }
    }
  }

  static Uint8List _generateBeepWav() {
    const sr = 16000;
    const duration = 0.3;
    const freq = 880.0;
    final samples = (sr * duration).toInt();
    final data = Int16List(samples);
    for (var i = 0; i < samples; i++) {
      final t = i / sr;
      final envelope = (1.0 - t / duration);
      data[i] = (sin(2 * pi * freq * t) * 16000 * envelope).toInt().clamp(-32768, 32767);
    }
    final dataBytes = data.buffer.asUint8List();
    final wav = BytesBuilder();
    wav.add(utf8.encode('RIFF'));
    wav.add(_leU32(36 + dataBytes.length));
    wav.add(utf8.encode('WAVE'));
    wav.add(utf8.encode('fmt '));
    wav.add(_leU32(16));
    wav.add(_leU16(1));
    wav.add(_leU16(1));
    wav.add(_leU32(sr));
    wav.add(_leU32(sr * 2));
    wav.add(_leU16(2));
    wav.add(_leU16(16));
    wav.add(utf8.encode('data'));
    wav.add(_leU32(dataBytes.length));
    wav.add(dataBytes);
    return wav.toBytes();
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
