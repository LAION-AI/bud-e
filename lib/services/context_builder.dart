/// Context Builder — priority-based context construction from memory tiers.
///
/// Budget allocation (total max ~20K tokens / ~80K chars):
///   1. Recent conversation history: last ~5K tokens (always included)
///   2. Keyword-triggered semantic memories: 1st order matches (~5K tokens)
///   3. Related semantic memories: 2nd order via relatedConcepts (~3K tokens)
///   4. Recent episodic memories: last ~5K tokens (newest first)
///   5. Procedural/skills: keyword-triggered (~2K tokens)
///
/// Each tier only fills if budget remains. Summaries preferred over full text.
library;

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_storage_service.dart';
import 'debug_log.dart';

int estimateTokens(String text) => (text.length / 4).ceil();

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüß\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

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

  /// Compact representation: summary if available, else truncated full text.
  String get compactText {
    if (summary != null && summary!.isNotEmpty) return summary!;
    return fullText.length > 500 ? '${fullText.substring(0, 500)}...' : fullText;
  }
  int get compactTokens => estimateTokens(compactText);
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

  List<_MemoryEntry>? _semanticCache;
  String? _episodicCache;
  int _episodicFileCount = -1;

  ContextBuilder(this._storage);

  void invalidateCache() {
    _semanticCache = null;
    _episodicCache = null;
    _episodicFileCount = -1;
  }

  Future<BuiltContext> buildContext({
    int episodicBudget = 50000, // ignored, we use fixed allocation
    int totalBudget = 100000,   // ignored, we use fixed allocation
    String currentConversationText = '',
  }) async {
    final sw = Stopwatch()..start();

    // --- Hard budget limits (in tokens) ---
    const maxTotal = 20000;       // ~80K chars total context
    const maxEpisodic = 4000;     // ~16K chars for recent episodes
    const maxSemantic1st = 5000;  // ~20K chars for direct keyword matches
    const maxSemantic2nd = 3000;  // ~12K chars for related concepts
    const maxPerEntry = 800;      // ~3.2K chars per single entry

    // --- Step 1: Extract keywords from recent conversation ---
    final keywords = _extractKeywords(currentConversationText);

    // --- Step 2: Load and score semantic memories ---
    final allEntries = await _getSemanticEntries();

    // 1st order: direct keyword matches
    final firstOrder = <_MemoryEntry>[];
    final activated = <String>{};
    for (final entry in allEntries) {
      if (_matchesTriggers(_normalize(currentConversationText), entry.triggerWords)) {
        activated.add(entry.path);
        firstOrder.add(entry);
      }
    }

    // 2nd order: related concepts (1 hop only, max 10)
    final secondOrder = <_MemoryEntry>[];
    for (final entry in firstOrder) {
      for (final relatedId in entry.relatedConcepts) {
        if (activated.contains(relatedId) || secondOrder.length >= 10) break;
        final related = allEntries.where((e) =>
            e.path == relatedId ||
            p.basenameWithoutExtension(e.path) == relatedId
        ).firstOrNull;
        if (related != null && !activated.contains(related.path)) {
          activated.add(related.path);
          secondOrder.add(related);
        }
      }
    }

    // Sort both by recency
    firstOrder.sort(_byRecency);
    secondOrder.sort(_byRecency);

    // --- Step 3: Build semantic context with budget ---
    final semanticParts = <String>[];
    final activatedPaths = <String>[];
    var semanticTokens = 0;

    // 1st order fills first
    for (final entry in firstOrder) {
      if (semanticTokens >= maxSemantic1st) break;
      final text = _formatEntry(entry, maxPerEntry);
      final tokens = estimateTokens(text);
      if (semanticTokens + tokens > maxSemantic1st) continue;
      semanticParts.add(text);
      activatedPaths.add(entry.path);
      semanticTokens += tokens;
    }

    // 2nd order fills remaining budget
    for (final entry in secondOrder) {
      if (semanticTokens >= maxSemantic1st + maxSemantic2nd) break;
      final text = _formatEntry(entry, maxPerEntry);
      final tokens = estimateTokens(text);
      if (semanticTokens + tokens > maxSemantic1st + maxSemantic2nd) continue;
      semanticParts.add(text);
      activatedPaths.add('${entry.path} (related)');
      semanticTokens += tokens;
    }

    final semanticText = semanticParts.join('\n\n');

    // --- Step 4: Load episodic memory (budget-limited) ---
    final episodicText = await _loadEpisodicMemory(maxEpisodic);
    final episodicTokens = estimateTokens(episodicText);

    final totalTokens = episodicTokens + semanticTokens;

    debugLog(DebugSource.contextConstructor,
        'Built in ${sw.elapsedMilliseconds}ms: '
        'ep=$episodicTokens sem=$semanticTokens (1st=${firstOrder.length} 2nd=${secondOrder.length}) '
        'act=${activatedPaths.length} total=$totalTokens '
        'keywords=${keywords.take(5).join(",")}');

    return BuiltContext(
      episodicContext: episodicText,
      episodicTokens: episodicTokens,
      activatedMemories: activatedPaths,
      semanticContext: semanticText,
      semanticTokens: semanticTokens,
      totalTokens: totalTokens,
    );
  }

  /// Extract meaningful keywords from conversation text.
  List<String> _extractKeywords(String text) {
    final stopwords = {
      'der', 'die', 'das', 'und', 'ist', 'ich', 'du', 'wir', 'sie', 'er',
      'ein', 'eine', 'auf', 'in', 'mit', 'von', 'zu', 'den', 'dem', 'des',
      'für', 'fuer', 'nicht', 'auch', 'als', 'aber', 'oder', 'wenn', 'dass',
      'hat', 'habe', 'haben', 'bin', 'sind', 'war', 'wird', 'kann', 'was',
      'wie', 'noch', 'nur', 'nach', 'bei', 'the', 'and', 'for', 'that',
      'this', 'with', 'you', 'are', 'was', 'have', 'has', 'can', 'will',
    };
    return _normalize(text)
        .split(' ')
        .where((w) => w.length > 2 && !stopwords.contains(w))
        .toSet()
        .toList();
  }

  /// Format a memory entry for context, respecting per-entry token limit.
  String _formatEntry(_MemoryEntry entry, int maxTokens) {
    final name = p.basenameWithoutExtension(entry.path);
    final updated = entry.data['lastUpdated'] as String? ?? '';
    final header = '[$name${updated.isNotEmpty ? ' ($updated)' : ''}]';

    // Prefer summary for compactness
    if (entry.summary != null && entry.summaryTokens <= maxTokens) {
      return '$header ${entry.summary}';
    }

    // Truncate full text if needed
    if (entry.fullTokens <= maxTokens) {
      return '$header ${entry.fullText}';
    }

    final maxChars = maxTokens * 4;
    return '$header ${entry.fullText.substring(0, maxChars.clamp(0, entry.fullText.length))}...';
  }

  int _byRecency(_MemoryEntry a, _MemoryEntry b) {
    final aTime = a.data['lastUpdated'] as String? ?? '';
    final bTime = b.data['lastUpdated'] as String? ?? '';
    return bTime.compareTo(aTime);
  }

  /// Load episodic memory: most recent first, hard token budget.
  Future<String> _loadEpisodicMemory(int tokenBudget) async {
    final dir = Directory(p.join(_storage.rootPath, 'episodic_memory'));
    if (!await dir.exists()) return '';

    final files = await dir.list()
        .where((e) => e.path.endsWith('.json'))
        .toList();

    if (_episodicCache != null && _episodicFileCount == files.length) {
      // Re-check cached size against new budget
      if (estimateTokens(_episodicCache!) <= tokenBudget) return _episodicCache!;
    }

    // Most recent first, cap at 30 files (not 100!)
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    final capped = files.take(30).toList();

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

  Future<List<_MemoryEntry>> _getSemanticEntries() async {
    if (_semanticCache != null) return _semanticCache!;

    final dir = Directory(p.join(_storage.rootPath, 'semantic_memory'));
    if (!await dir.exists()) return [];

    final files = await dir.list()
        .where((e) => e.path.endsWith('.json'))
        .toList();

    final contents = await Future.wait(
      files.map((f) => (f as File).readAsString(encoding: utf8).catchError((_) => '')),
    );

    final entries = <_MemoryEntry>[];
    for (var i = 0; i < files.length; i++) {
      if (contents[i].isEmpty) continue;
      try {
        final data = jsonDecode(contents[i]) as Map<String, dynamic>;
        final relPath = p.relative(files[i].path, from: _storage.rootPath);

        // Compact representation: only key fields for context
        final contextData = <String, dynamic>{};
        for (final key in ['content', 'summary', 'category', 'triggerWords', 'lastUpdated']) {
          if (data[key] != null) contextData[key] = data[key];
        }
        final fullText = const JsonEncoder().convert(contextData);

        final triggerWords = <String>[];
        if (data['triggerWords'] is List) {
          triggerWords.addAll((data['triggerWords'] as List).map((e) => e.toString()));
        }
        triggerWords.add(p.basenameWithoutExtension(files[i].path).replaceAll('_', ' '));

        final relatedConcepts = <String>[];
        if (data['relatedConcepts'] is List) {
          relatedConcepts.addAll((data['relatedConcepts'] as List).map((e) => e.toString()));
        }

        final summary = data['summary'] as String? ?? data['content'] as String?;

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
      if (nt.isEmpty || nt.length < 3) continue;
      if (normalizedScanText.contains(nt)) return true;
    }
    return false;
  }
}
