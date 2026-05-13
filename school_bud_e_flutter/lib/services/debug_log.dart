/// Global debug log — captures timestamped events and structured snapshots
/// for context construction and memory updates.
library;

import 'package:flutter/foundation.dart';

enum DebugSource {
  contextConstructor,
  mainAgent,
  asr,
  tts,
  updater,
  memory,
  agentRegistry,
  system,
}

class DebugEntry {
  final DateTime timestamp;
  final DebugSource source;
  final String message;
  final Map<String, dynamic>? data;

  DebugEntry({
    required this.source,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();

  String get sourceLabel => source.name;

  @override
  String toString() =>
      '[${timestamp.toIso8601String().substring(11, 23)}] '
      '${sourceLabel.toUpperCase()}: $message';
}

/// A snapshot of a context construction for one exchange.
class ContextSnapshot {
  final DateTime timestamp;
  final String userMessage;
  final int episodicTokens;
  final int semanticTokens;
  final int totalTokens;
  final String episodicContext;
  final String semanticContext;
  final List<String> activatedMemories;
  final String systemPrompt;

  ContextSnapshot({
    required this.timestamp,
    required this.userMessage,
    required this.episodicTokens,
    required this.semanticTokens,
    required this.totalTokens,
    required this.episodicContext,
    required this.semanticContext,
    required this.activatedMemories,
    required this.systemPrompt,
  });
}

/// A record of a memory update operation.
class MemoryUpdateRecord {
  final DateTime timestamp;
  final String conversationId;
  final int conceptsUpdated;
  final int conceptsCreated;
  final List<String> updatedFiles;
  final String? episodicSummary;
  final String? error;
  final int durationMs;

  MemoryUpdateRecord({
    required this.timestamp,
    required this.conversationId,
    this.conceptsUpdated = 0,
    this.conceptsCreated = 0,
    this.updatedFiles = const [],
    this.episodicSummary,
    this.error,
    this.durationMs = 0,
  });
}

class DebugLog extends ChangeNotifier {
  static final DebugLog instance = DebugLog._();
  DebugLog._();

  final List<DebugEntry> _entries = [];
  static const int _maxEntries = 500;

  /// Context snapshots — one per exchange, keeps last 20.
  final List<ContextSnapshot> _contextSnapshots = [];
  static const int _maxSnapshots = 20;

  /// Memory update records — keeps last 30.
  final List<MemoryUpdateRecord> _memoryUpdates = [];
  static const int _maxUpdates = 30;

  List<DebugEntry> get entries => List.unmodifiable(_entries);
  List<ContextSnapshot> get contextSnapshots => List.unmodifiable(_contextSnapshots);
  List<MemoryUpdateRecord> get memoryUpdates => List.unmodifiable(_memoryUpdates);

  List<DebugEntry> entriesFor(DebugSource source) =>
      _entries.where((e) => e.source == source).toList();

  void log(DebugSource source, String message, {Map<String, dynamic>? data}) {
    final entry = DebugEntry(source: source, message: message, data: data);
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    debugPrint(entry.toString());
    notifyListeners();
  }

  void addContextSnapshot(ContextSnapshot snapshot) {
    _contextSnapshots.add(snapshot);
    if (_contextSnapshots.length > _maxSnapshots) {
      _contextSnapshots.removeAt(0);
    }
    notifyListeners();
  }

  void addMemoryUpdate(MemoryUpdateRecord record) {
    _memoryUpdates.add(record);
    if (_memoryUpdates.length > _maxUpdates) {
      _memoryUpdates.removeAt(0);
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _contextSnapshots.clear();
    _memoryUpdates.clear();
    notifyListeners();
  }
}

void debugLog(DebugSource source, String message, {Map<String, dynamic>? data}) {
  DebugLog.instance.log(source, message, data: data);
}
