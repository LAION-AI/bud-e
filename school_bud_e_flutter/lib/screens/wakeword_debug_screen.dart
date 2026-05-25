/// Wake Word Debug Screen — shows live scores for Hey/Stop/Go Buddy.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/wakeword_service.dart';

class WakeWordDebugScreen extends StatefulWidget {
  const WakeWordDebugScreen({super.key});
  @override
  State<WakeWordDebugScreen> createState() => _WakeWordDebugScreenState();
}

class _WakeWordDebugScreenState extends State<WakeWordDebugScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final ww = chat.wakeWordService;
    final colors = Theme.of(context).colorScheme;
    final scores = ww.scoreHistory;

    final latest = scores.isNotEmpty ? scores.last : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wake Word Debug'),
        actions: [
          IconButton(
            icon: Icon(ww.isListening ? Icons.hearing : Icons.hearing_disabled),
            color: ww.isListening ? colors.primary : colors.outline,
            onPressed: () => chat.toggleWakeWord(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => scores.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: ww.isListening
                ? colors.primaryContainer.withValues(alpha: 0.3)
                : colors.errorContainer.withValues(alpha: 0.2),
            child: Row(
              children: [
                Icon(ww.isListening ? Icons.radio_button_on : Icons.radio_button_off,
                    color: ww.isListening ? Colors.green : Colors.red, size: 14),
                const SizedBox(width: 6),
                Text(ww.isListening ? 'LISTENING' : 'STOPPED',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12,
                        color: ww.isListening ? Colors.green : Colors.red)),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: ww.state == WakeWordState.recording ? Colors.red.withValues(alpha: 0.2) : colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(ww.state == WakeWordState.recording ? 'RECORDING' : 'IDLE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: ww.state == WakeWordState.recording ? Colors.red : colors.outline)),
                ),
                const Spacer(),
                Text('Device: ${ww.selectedDevice?.label ?? "Default"}',
                    style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),

          // Mic selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: DropdownButtonFormField<String>(
              value: ww.selectedDevice?.id,
              decoration: const InputDecoration(
                labelText: 'Mikrofon', prefixIcon: Icon(Icons.mic), isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Standard')),
                ...ww.availableDevices.map((d) => DropdownMenuItem(
                    value: d.id, child: Text(d.label, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) {
                ww.selectedDevice = v == null ? null : ww.availableDevices.firstWhere((d) => d.id == v);
                if (ww.isListening) { ww.stopListening(); ww.startListening(); }
              },
            ),
          ),

          // Big scores display
          if (latest != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _ScoreCard('Hey Buddy', latest.heyBuddy, WakeWordService.heyThreshold,
                      Colors.green, ww.state == WakeWordState.idle),
                  const SizedBox(width: 8),
                  _ScoreCard('Go Buddy', latest.goBuddy, WakeWordService.goThreshold,
                      Colors.blue, ww.state == WakeWordState.recording),
                  const SizedBox(width: 8),
                  _ScoreCard('Stop Buddy', latest.stopBuddy, WakeWordService.stopThreshold,
                      Colors.red, true),
                ],
              ),
            ),

          const Divider(height: 1),

          // Score history
          Expanded(
            child: scores.isEmpty
                ? const Center(child: Text('Waiting for scores...'))
                : ListView.builder(
                    reverse: true,
                    itemCount: scores.length,
                    itemBuilder: (_, i) {
                      final idx = scores.length - 1 - i;
                      final s = scores[idx];
                      final ts = '${s.time.hour.toString().padLeft(2, '0')}:'
                          '${s.time.minute.toString().padLeft(2, '0')}:'
                          '${s.time.second.toString().padLeft(2, '0')}';

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        child: Row(
                          children: [
                            SizedBox(width: 52, child: Text(ts,
                                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'))),
                            _ScoreBar('H', s.heyBuddy, WakeWordService.heyThreshold, Colors.green),
                            const SizedBox(width: 4),
                            _ScoreBar('G', s.goBuddy, WakeWordService.goThreshold, Colors.blue),
                            const SizedBox(width: 4),
                            _ScoreBar('S', s.stopBuddy, WakeWordService.stopThreshold, Colors.red),
                            const SizedBox(width: 6),
                            SizedBox(width: 35, child: Text('${(s.rms * 1000).toStringAsFixed(1)}',
                                style: const TextStyle(fontSize: 9, fontFamily: 'monospace'),
                                textAlign: TextAlign.right)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final String label;
  final double score;
  final double threshold;
  final Color color;
  final bool active;
  const _ScoreCard(this.label, this.score, this.threshold, this.color, this.active);

  @override
  Widget build(BuildContext context) {
    final triggered = score > threshold;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: triggered ? color.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: triggered ? color : Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: active ? color : Colors.grey)),
            const SizedBox(height: 4),
            Text(score.toStringAsFixed(4),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: triggered ? color : Colors.grey)),
            Text('thr: $threshold', style: const TextStyle(fontSize: 9, color: Colors.grey)),
            if (triggered)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('TRIGGERED', style: TextStyle(fontSize: 10,
                    fontWeight: FontWeight.bold, color: color)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final String label;
  final double score;
  final double threshold;
  final Color color;
  const _ScoreBar(this.label, this.score, this.threshold, this.color);

  @override
  Widget build(BuildContext context) {
    final triggered = score > threshold;
    final barW = (score / 0.1).clamp(0.0, 1.0); // scale to 0.1 max
    return Expanded(
      child: Row(
        children: [
          SizedBox(width: 12, child: Text(label,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color))),
          Expanded(
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: barW,
                child: Container(
                  decoration: BoxDecoration(
                    color: triggered ? color : color.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ),
          SizedBox(width: 35, child: Text(score.toStringAsFixed(3),
              style: TextStyle(fontSize: 9, fontFamily: 'monospace',
                  fontWeight: triggered ? FontWeight.bold : null,
                  color: triggered ? color : null))),
        ],
      ),
    );
  }
}
