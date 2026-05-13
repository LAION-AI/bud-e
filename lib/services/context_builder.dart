/// Context Builder — constructs the LLM context from memory tiers.
///
/// Optimizations:
///   - In-memory cache for semantic entries (invalidated on write)
///   - Parallel file reads via Future.wait
///   - Episodic file cap (max 100 most recent)
library;

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_storage_service.dart';
import 'debug_log.dart';

int estimateTokens(String text) => (text.length / 4).ceil();

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

class _MemoryEntry {
  final String path;
  final Map<String, dynamic> data;
  final List<String> triggerWords;
  final List<String> relatedConcepts;
  final String? summary;
  final String fullText;
  final int fullTokens;
  final int summaryTokens;

  _MemoryEntry({
    required this.path,
    required this.data,
    required this.triggerWords,
    required this.relatedConcepts,
    this.summary,
    required this.fullText,
    required this.fullTokens,
    required this.summaryTokens,
  });
}

class BuiltContext {
  final String episodicContext;
  final int episodicTokens;
  final List<String> activatedMemories;
  final String semanticContext;
  final int semanticTokens;
  final int totalTokens;

  BuiltContext({
    required this.episodicContext,
    required this.episodicTokens,
    required this.activatedMemories,
    required this.semanticContext,
    required this.semanticTokens,
    required this.totalTokens,
  });
}

class ContextBuilder {
  final FileStorageService _storage;

  /// Cached semantic entries — invalidate with [invalidateCache()].
  List<_MemoryEntry>? _semanticCache;

  /// Cached episodic text + token count.
  String? _episodicCache;
  int _episodicFileCount = -1;

  ContextBuilder(this._storage);

  /// Call this after memory updater writes new files.
  void invalidateCache() {
    _semanticCache = null;
    _episodicCache = null;
    _episodicFileCount = -1;
  }

  Future<BuiltContext> buildContext({
    int episodicBudget = 50000,
    int totalBudget = 100000,
    String currentConversationText = '',
  }) async {
    final sw = Stopwatch()..start();

    // --- Step 1: Load episodic memory (parallel reads, cached) ---
    final episodicText = await _loadEpisodicMemory(episodicBudget);
    final episodicTokens = estimateTokens(episodicText);

    // --- Step 2: Get semantic entries (cached) ---
    final allEntries = await _getSemanticEntries();

    // --- Step 3: Trigger-word activation ---
    final scanText = _normalize('$episodicText $currentConversationText');
    final activated = <String>{};
    final toActivate = <_MemoryEntry>[];

    for (final entry in allEntries) {
      if (_matchesTriggers(scanText, entry.triggerWords)) {
        activated.add(entry.path);
        toActivate.add(entry);
      }
    }

    // --- Step 4: Follow related pointers (max 3 hops, max 20 entries) ---
    for (var hop = 0; hop < 3 && toActivate.length < 20; hop++) {
      final newActivations = <_MemoryEntry>[];
      for (final entry in List.of(toActivate)) {
        for (final relatedId in entry.relatedConcepts) {
          if (activated.contains(relatedId)) continue;
          final related = allEntries.where((e) =>
              e.path == relatedId ||
              p.basenameWithoutExtension(e.path) == relatedId
          ).firstOrNull;
          if (related != null) {
            activated.add(related.path);
            newActivations.add(related);
          }
        }
      }
      if (newActivations.isEmpty) break;
      toActivate.addAll(newActivations);
    }

    // --- Step 5: Sort by recency (newest first) and fill budget ---
    toActivate.sort((a, b) {
      final aTime = a.data['lastUpdated'] as String? ?? '';
      final bTime = b.data['lastUpdated'] as String? ?? '';
      return bTime.compareTo(aTime); // descending = newest first
    });

    var remainingTokens = totalBudget - episodicTokens;
    final semanticParts = <String>[];
    final activatedPaths = <String>[];

    for (final entry in toActivate) {
      if (remainingTokens <= 0) break;
      final name = p.basenameWithoutExtension(entry.path);
      final updated = entry.data['lastUpdated'] as String? ?? 'unknown';
      final header = '--- $name (aktualisiert: $updated) ---';

      if (entry.fullTokens <= remainingTokens) {
        semanticParts.add('$header\n${entry.fullText}');
        remainingTokens -= entry.fullTokens;
        activatedPaths.add(entry.path);
      } else if (entry.summary != null && entry.summaryTokens <= remainingTokens) {
        semanticParts.add('$header\n${entry.summary}');
        remainingTokens -= entry.summaryTokens;
        activatedPaths.add('${entry.path} (summary)');
      }
    }

    final semanticText = semanticParts.join('\n\n');
    final semanticTokens = estimateTokens(semanticText);
    final totalTokens = episodicTokens + semanticTokens;

    debugLog(DebugSource.contextConstructor,
        'Built in ${sw.elapsedMilliseconds}ms: ep=$episodicTokens sem=$semanticTokens '
        'act=${activatedPaths.length} total=$totalTokens');

    return BuiltContext(
      episodicContext: episodicText,
      episodicTokens: episodicTokens,
      activatedMemories: activatedPaths,
      semanticContext: semanticText,
      semanticTokens: semanticTokens,
      totalTokens: totalTokens,
    );
  }

  /// Load episodic memory with parallel reads and caching.
  Future<String> _loadEpisodicMemory(int tokenBudget) async {
    final dir = Directory(p.join(_storage.rootPath, 'episodic_memory'));
    if (!await dir.exists()) return '';

    final files = await dir.list()
        .where((e) => e.path.endsWith('.json'))
        .toList();

    // Check if cache is still valid (same file count)
    if (_episodicCache != null && _episodicFileCount == files.length) {
      return _episodicCache!;
    }

    // Sort descending (most recent first), cap at 100
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    final capped = files.take(100).toList();

    // Parallel read all files
    final contents = await Future.wait(
      capped.map((f) => (f as File).readAsString(encoding: utf8).catchError((_) => '')),
    );

    final parts = <String>[];
    var usedTokens = 0;

    for (final raw in contents) {
      if (raw.isEmpty) continue;
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final text = _formatEpisodicEntry(data);
        final tokens = estimateTokens(text);
        if (usedTokens + tokens > tokenBudget) break;
        parts.add(text);
        usedTokens += tokens;
      } catch (_) {}
    }

    // Reverse for temporal order (oldest first)
    final result = parts.reversed.join('\n\n');
    _episodicCache = result;
    _episodicFileCount = files.length;
    return result;
  }

  String _formatEpisodicEntry(Map<String, dynamic> data) {
    final buf = StringBuffer();
    final savedAt = data['savedAt'] ?? data['lastUpdated'] ?? '';
    buf.writeln('[Episode $savedAt]');
    if (data['summary'] != null) buf.writeln(data['summary']);
    if (data['topics'] != null) {
      buf.writeln('Topics: ${(data['topics'] as List).join(', ')}');
    }
    if (data['firstUserMessage'] != null) {
      buf.writeln('User asked: ${data['firstUserMessage']}');
    }
    return buf.toString().trim();
  }

  /// Get semantic entries (cached, parallel reads on first call).
  Future<List<_MemoryEntry>> _getSemanticEntries() async {
    if (_semanticCache != null) return _semanticCache!;

    final dir = Directory(p.join(_storage.rootPath, 'semantic_memory'));
    if (!await dir.exists()) return [];

    final files = await dir.list()
        .where((e) => e.path.endsWith('.json'))
        .toList();

    // Parallel read all files at once
    final contents = await Future.wait(
      files.map((f) => (f as File).readAsString(encoding: utf8).catchError((_) => '')),
    );

    final entries = <_MemoryEntry>[];
    for (var i = 0; i < files.length; i++) {
      if (contents[i].isEmpty) continue;
      try {
        final data = jsonDecode(contents[i]) as Map<String, dynamic>;
        final relPath = p.relative(files[i].path, from: _storage.rootPath);

        // Strip internal fields (revisions, notes list) to avoid confusing
        // the LLM with outdated information
        final contextData = Map<String, dynamic>.from(data)
          ..remove('revisions')
          ..remove('notes');
        final fullText = const JsonEncoder.withIndent('  ').convert(contextData);

        final triggerWords = <String>[];
        if (data['triggerWords'] is List) {
          triggerWords.addAll((data['triggerWords'] as List).map((e) => e.toString()));
        }
        triggerWords.add(p.basenameWithoutExtension(files[i].path).replaceAll('_', ' '));

        final relatedConcepts = <String>[];
        if (data['relatedConcepts'] is List) {
          relatedConcepts.addAll((data['relatedConcepts'] as List).map((e) => e.toString()));
        }

        final summary = data['summary'] as String?;

        entries.add(_MemoryEntry(
          path: relPath,
          data: data,
          triggerWords: triggerWords,
          relatedConcepts: relatedConcepts,
          summary: summary,
          fullText: fullText,
          fullTokens: estimateTokens(fullText),
          summaryTokens: summary != null ? estimateTokens(summary) : 0,
        ));
      } catch (_) {}
    }

    _semanticCache = entries;
    return entries;
  }

  bool _matchesTriggers(String normalizedScanText, List<String> triggers) {
    for (final trigger in triggers) {
      final nt = _normalize(trigger);
      if (nt.isEmpty) continue;
      if (normalizedScanText.contains(nt)) return true;
    }
    return false;
  }
}
