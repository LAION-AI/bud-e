/// Wake Word Debug Screen — shows live scores, audio levels, and pipeline details.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/wakeword_service.dart';
import '../services/debug_log.dart';

class WakeWordDebugScreen extends StatefulWidget {
  const WakeWordDebugScreen({super.key});

  @override
  State<WakeWordDebugScreen> createState() => _WakeWordDebugScreenState();
}

class _WakeWordDebugScreenState extends State<WakeWordDebugScreen> {
  Timer? _refreshTimer;
  final List<_ScoreEntry> _scores = [];
  static const int maxEntries = 100;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateFromLog();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _updateFromLog() {
    final entries = DebugLog.instance.entries;
    // Find new WakeWord score entries
    for (final e in entries) {
      if (e.message.contains('WakeWord score:') &&
          !_scores.any((s) => s.time == e.timestamp)) {
        final scoreMatch = RegExp(r'score: ([0-9.]+)').firstMatch(e.message);
        final rmsMatch = RegExp(r'rms=([0-9.]+)').firstMatch(e.message);
        final samplesMatch = RegExp(r'samples=(\d+)').firstMatch(e.message);
        if (scoreMatch != null) {
          _scores.add(_ScoreEntry(
            time: e.timestamp,
            score: double.tryParse(scoreMatch.group(1)!) ?? 0,
            rms: double.tryParse(rmsMatch?.group(1) ?? '0') ?? 0,
            samples: int.tryParse(samplesMatch?.group(1) ?? '0') ?? 0,
          ));
          if (_scores.length > maxEntries) _scores.removeAt(0);
        }
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final ww = chat.wakeWordService;
    final colors = Theme.of(context).colorScheme;

    final maxScore = _scores.isEmpty ? 0.1
        : _scores.map((s) => s.score).reduce((a, b) => a > b ? a : b).clamp(0.05, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wake Word Debug'),
        actions: [
          IconButton(
            icon: Icon(ww.isListening ? Icons.hearing : Icons.hearing_disabled),
            color: ww.isListening ? colors.primary : colors.outline,
            onPressed: () => chat.toggleWakeWord(),
            tooltip: ww.isListening ? 'Stop' : 'Start',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => _scores.clear()),
            tooltip: 'Clear',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.all(12),
            color: ww.isListening
                ? colors.primaryContainer.withValues(alpha: 0.3)
                : colors.errorContainer.withValues(alpha: 0.2),
            child: Row(
              children: [
                Icon(
                  ww.isListening ? Icons.radio_button_on : Icons.radio_button_off,
                  color: ww.isListening ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  ww.isListening ? 'LISTENING' : 'STOPPED',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ww.isListening ? Colors.green : Colors.red,
                  ),
                ),
                const Spacer(),
                Text('Threshold: ${WakeWordService.threshold}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                Text('Model: medium',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                Text('Device: ${ww.selectedDevice?.label ?? "Default"}',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),

          // Mic selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: DropdownButtonFormField<String>(
              value: ww.selectedDevice?.id,
              decoration: const InputDecoration(
                labelText: 'Mikrofon',
                prefixIcon: Icon(Icons.mic),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Standard')),
                ...ww.availableDevices.map((d) => DropdownMenuItem(
                  value: d.id,
                  child: Text(d.label, overflow: TextOverflow.ellipsis),
                )),
              ],
              onChanged: (v) {
                if (v == null) {
                  ww.selectedDevice = null;
                } else {
                  ww.selectedDevice = ww.availableDevices.firstWhere((d) => d.id == v);
                }
                if (ww.isListening) {
                  ww.stopListening();
                  ww.startListening();
                }
              },
            ),
          ),

          // Latest score big display
          if (_scores.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    _scores.last.score.toStringAsFixed(4),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: _scores.last.score > WakeWordService.threshold
                          ? Colors.green
                          : colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'RMS: ${_scores.last.rms.toStringAsFixed(6)} | '
                    'Samples: ${_scores.last.samples}',
                    style: TextStyle(fontSize: 12, color: colors.outline),
                  ),
                  if (_scores.last.score > WakeWordService.threshold)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('DETECTED!',
                          style: TextStyle(fontSize: 24, color: Colors.green,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),

          const Divider(),

          // Score history chart
          Expanded(
            child: _scores.isEmpty
                ? const Center(child: Text('Waiting for scores...'))
                : ListView.builder(
                    reverse: true,
                    itemCount: _scores.length,
                    itemBuilder: (_, i) {
                      final idx = _scores.length - 1 - i;
                      final s = _scores[idx];
                      final barWidth = (s.score / maxScore).clamp(0.0, 1.0);
                      final isDetected = s.score > WakeWordService.threshold;
                      final ts = '${s.time.hour.toString().padLeft(2, '0')}:'
                          '${s.time.minute.toString().padLeft(2, '0')}:'
                          '${s.time.second.toString().padLeft(2, '0')}';

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                        child: Row(
                          children: [
                            SizedBox(width: 60,
                                child: Text(ts, style: const TextStyle(
                                    fontSize: 11, fontFamily: 'monospace'))),
                            SizedBox(width: 60,
                                child: Text(s.score.toStringAsFixed(4),
                                    style: TextStyle(
                                      fontSize: 11, fontFamily: 'monospace',
                                      fontWeight: isDetected ? FontWeight.bold : null,
                                      color: isDetected ? Colors.green : null,
                                    ))),
                            Expanded(
                              child: Container(
                                height: 14,
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: barWidth,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isDetected ? Colors.green : colors.primary,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(width: 50,
                                child: Text('${(s.rms * 1000).toStringAsFixed(1)}',
                                    style: const TextStyle(
                                        fontSize: 10, fontFamily: 'monospace'),
                                    textAlign: TextAlign.right)),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Debug log (last few wake word entries)
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: DebugLog.instance.entries
                  .where((e) => e.message.contains('WakeWord') || e.message.contains('Wake'))
                  .toList()
                  .reversed
                  .take(10)
                  .map((e) => Text(
                    '${e.timestamp.toString().substring(11, 23)} ${e.message}',
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace',
                        color: Color(0xFFCDD6F4)),
                  ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreEntry {
  final DateTime time;
  final double score;
  final double rms;
  final int samples;
  const _ScoreEntry({required this.time, required this.score, required this.rms, required this.samples});
}
