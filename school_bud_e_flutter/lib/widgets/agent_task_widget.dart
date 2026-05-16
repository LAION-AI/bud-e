/// Widget showing a sub-agent task's status inline in the chat.
library;

import 'package:flutter/material.dart';
import '../models/agent_task.dart';
import 'file_chip.dart';

class AgentTaskWidget extends StatelessWidget {
  final AgentTask task;
  final VoidCallback? onRetry;

  const AgentTaskWidget({super.key, required this.task, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: task,
      builder: (_, __) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bgColor(colors),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor(colors), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row: icon + title + status
            Row(
              children: [
                _statusIcon(colors),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusTitle(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                if (task.status == AgentTaskStatus.running)
                  Text(
                    '${task.currentStep}/${task.maxSteps}',
                    style: TextStyle(fontSize: 11, color: colors.outline),
                  ),
              ],
            ),
            // Progress bar for running tasks
            if (task.status == AgentTaskStatus.running && task.maxSteps > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 28, right: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: task.currentStep / task.maxSteps,
                    minHeight: 4,
                    backgroundColor: colors.surfaceContainerHighest,
                    color: colors.primary,
                  ),
                ),
              ),
            // Instruction
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 28),
              child: Text(
                task.instruction.length > 100
                    ? '${task.instruction.substring(0, 100)}...'
                    : task.instruction,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            // Steps log
            if (task.steps.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final step in task.steps.reversed.take(3).toList().reversed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Icon(Icons.chevron_right, size: 12, color: colors.outline),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                step,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: colors.outline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            // Error message
            if (task.error != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  task.error!,
                  style: TextStyle(fontSize: 11, color: colors.error),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            // Generated files
            if (task.generatedFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final f in task.generatedFiles) FileChip(filePath: f),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(ColorScheme colors) {
    return switch (task.status) {
      AgentTaskStatus.pending => SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.outline)),
      AgentTaskStatus.running => SizedBox(
          width: 20,
          height: 20,
          child: _AnimatedGear(color: colors.primary)),
      AgentTaskStatus.completed => Icon(Icons.check_circle,
          size: 20, color: Colors.green),
      AgentTaskStatus.error => Icon(Icons.error_outline,
          size: 20, color: colors.error),
    };
  }

  Color _bgColor(ColorScheme colors) {
    return switch (task.status) {
      AgentTaskStatus.running =>
          colors.primaryContainer.withValues(alpha: 0.15),
      AgentTaskStatus.completed =>
          Colors.green.withValues(alpha: 0.06),
      AgentTaskStatus.error =>
          colors.errorContainer.withValues(alpha: 0.15),
      _ => colors.surfaceContainerLow,
    };
  }

  Color _borderColor(ColorScheme colors) {
    return switch (task.status) {
      AgentTaskStatus.running =>
          colors.primary.withValues(alpha: 0.3),
      AgentTaskStatus.completed =>
          Colors.green.withValues(alpha: 0.3),
      AgentTaskStatus.error =>
          colors.error.withValues(alpha: 0.3),
      _ => colors.outlineVariant.withValues(alpha: 0.3),
    };
  }

  String _statusTitle() {
    if (task.status == AgentTaskStatus.running && task.steps.isNotEmpty) {
      final lastStep = task.steps.last;
      // Show a human-readable description of what's happening
      if (lastStep.contains('web_search')) return 'Searching the web...';
      if (lastStep.contains('web_scrape')) return 'Reading webpage...';
      if (lastStep.contains('wikipedia')) return 'Looking up Wikipedia...';
      if (lastStep.contains('generate_image')) return 'Generating image...';
      if (lastStep.contains('write_file')) return 'Writing file...';
      if (lastStep.contains('LLM-Aufruf')) return 'Thinking... (${task.currentStep}/${task.maxSteps})';
    }
    return switch (task.status) {
      AgentTaskStatus.pending => 'Starting agent...',
      AgentTaskStatus.running => 'Agent working... (${task.currentStep}/${task.maxSteps})',
      AgentTaskStatus.completed => 'Done',
      AgentTaskStatus.error => 'Error',
    };
  }
}

/// Animated rotating gear icon.
class _AnimatedGear extends StatefulWidget {
  final Color color;
  const _AnimatedGear({required this.color});

  @override
  State<_AnimatedGear> createState() => _AnimatedGearState();
}

class _AnimatedGearState extends State<_AnimatedGear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.rotate(
        angle: _ctrl.value * 2 * 3.14159,
        child: child,
      ),
      child: Icon(Icons.settings, size: 20, color: widget.color),
    );
  }
}
