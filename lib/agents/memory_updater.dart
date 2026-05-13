/// Background Memory Updater agent.
///
/// After each conversation exchange, runs in the background to:
///   1. Extract semantic concepts as individual JSON files with
///      triggerWords, summary, relatedConcepts
///   2. Update episodic memory with conversation summaries
///   3. Update procedural memory with interaction patterns
///   4. Ensure every semantic JSON has triggerWords, summary, and
///      relatedConcepts for the context builder's activation logic
library;

import 'dart:convert';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../services/file_storage_service.dart';
import '../services/debug_log.dart';

class MemoryUpdater {
  final ChatService _chatService = ChatService();
  final FileStorageService _storage;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  MemoryUpdater(this._storage);

  Future<void> updateAfterExchange({
    required String universalApiKey,
    required List<Message> recentMessages,
    required String conversationId,
  }) async {
    if (_isRunning) {
      debugLog(DebugSource.updater, 'Updater already running, skipping');
      return;
    }
    if (recentMessages.length < 2) return;

    _isRunning = true;
    debugLog(DebugSource.updater, 'Background memory update started...');
    final updateSw = Stopwatch()..start();
    final updatedFiles = <String>[];
    int conceptsCreated = 0, conceptsUpdated = 0;

    try {
      final msgs = recentMessages.length > 10
          ? recentMessages.sublist(recentMessages.length - 10)
          : recentMessages;

      final conversationText = msgs
          .map((m) => '${m.role.name}: ${m.content}')
          .join('\n\n');

      // Get list of existing concept IDs so the LLM can reuse them for updates
      final existingIds = await _getExistingConceptIds();
      final existingIdsStr = existingIds.isEmpty
          ? ''
          : '\n\nEXISTING CONCEPT IDs (reuse these for updates, do NOT create new IDs for the same topic):\n${existingIds.join(', ')}';

      final extractionPrompt = '''Analyze this conversation and extract structured memory updates.
Return ONLY valid JSON with these fields:

{
  "concepts": [
    {
      "id": "snake_case_concept_id",
      "title": "Human Readable Title",
      "content": "The CURRENT, UP-TO-DATE knowledge (replace outdated info)",
      "summary": "One paragraph summary of this concept",
      "triggerWords": ["word1", "word2", "phrase that activates this"],
      "relatedConcepts": ["other_concept_id"],
      "category": "science|history|math|language|user_info|general"
    }
  ],
  "user_preferences": {},
  "episodic_summary": "1-2 sentence summary",
  "procedural_notes": [],
  "topics_discussed": ["topic1"]
}

CRITICAL RULES:
- If info UPDATES an existing concept, reuse its EXACT id from the list below
- content should contain the LATEST correct information (not old + new mixed)
- If the user corrects something, the content must reflect the CORRECTION only
- triggerWords: include title, key terms, synonyms$existingIdsStr

Return ONLY the JSON, no markdown''';

      final response = await _chatService.chat(
        universalApiKey: universalApiKey,
        messages: [Message.user(conversationText)],
        systemPrompt: extractionPrompt,
      );

      if (response.startsWith('[Error]')) {
        debugLog(DebugSource.updater, 'LLM extraction failed: $response');
        return;
      }

      final parsed = _parseJsonResponse(response);
      if (parsed == null) {
        debugLog(DebugSource.updater, 'Could not parse LLM response as JSON');
        return;
      }

      // --- Save all in parallel (concepts + prefs + episodic + procedural) ---
      final saveFutures = <Future>[];

      final concepts = parsed['concepts'] as List?;
      if (concepts != null) {
        for (final c in concepts) {
          if (c is Map<String, dynamic>) {
            saveFutures.add(_saveConceptFile(c).then((wasUpdate) {
              final cid = c['id'] ?? 'unknown';
              updatedFiles.add('semantic_memory/$cid.json');
              if (wasUpdate) { conceptsUpdated++; } else { conceptsCreated++; }
            }));
          }
        }
      }

      final prefs = parsed['user_preferences'] as Map<String, dynamic>?;
      if (prefs != null && prefs.isNotEmpty) {
        saveFutures.add(_updateUserPreferences(prefs));
      }

      final summary = parsed['episodic_summary'] as String?;
      final topics = (parsed['topics_discussed'] as List?)
          ?.map((e) => e.toString()).toList();
      if (summary != null && summary.isNotEmpty) {
        saveFutures.add(_storage.saveEpisodicEntry({
          'type': 'auto_summary',
          'conversationId': conversationId,
          'summary': summary,
          'topics': topics ?? [],
          'messageCount': msgs.length,
        }));
      }

      final procedural = parsed['procedural_notes'] as List?;
      if (procedural != null && procedural.isNotEmpty) {
        saveFutures.add(_updateProceduralMemory(procedural));
      }

      // Wait for all saves to complete in parallel
      await Future.wait(saveFutures.map((f) => f.catchError((_) {})));

      updateSw.stop();
      debugLog(DebugSource.updater,
          'Update complete in ${updateSw.elapsedMilliseconds}ms: '
          '$conceptsCreated new, $conceptsUpdated updated');

      DebugLog.instance.addMemoryUpdate(MemoryUpdateRecord(
        timestamp: DateTime.now(),
        conversationId: conversationId,
        conceptsCreated: conceptsCreated,
        conceptsUpdated: conceptsUpdated,
        updatedFiles: updatedFiles,
        episodicSummary: summary,
        durationMs: updateSw.elapsedMilliseconds,
      ));
    } catch (e) {
      updateSw.stop();
      debugLog(DebugSource.updater, 'Memory update error: $e');
      DebugLog.instance.addMemoryUpdate(MemoryUpdateRecord(
        timestamp: DateTime.now(),
        conversationId: conversationId,
        error: e.toString(),
        durationMs: updateSw.elapsedMilliseconds,
      ));
    } finally {
      _isRunning = false;
    }
  }

  /// Get all existing concept IDs so the LLM can reuse them for updates.
  Future<List<String>> _getExistingConceptIds() async {
    try {
      final entries = await _storage.listDirectory('semantic_memory');
      return entries
          .where((e) => e.path.endsWith('.json'))
          .map((e) => e.path.split(RegExp(r'[/\\]')).last.replaceAll('.json', ''))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Save a concept. Returns true if it was an UPDATE, false if new.
  /// and keep a revision history for the old value.
  Future<bool> _saveConceptFile(Map<String, dynamic> concept) async {
    final id = concept['id'] as String? ?? 'unknown';
    final existing = await _storage.loadSemanticMemory(id);
    final now = DateTime.now().toIso8601String();

    final merged = <String, dynamic>{
      ...?existing,
      'id': id,
      'title': concept['title'] ?? existing?['title'] ?? id,
      'category': concept['category'] ?? existing?['category'] ?? 'general',
    };

    // Content: REPLACE with new (not merge), keep revision history
    final newContent = concept['content'] as String? ?? '';
    final oldContent = existing?['content'] as String? ?? '';
    if (newContent.isNotEmpty) {
      merged['content'] = newContent;
      // Track revisions so we know what changed
      final revisions = List<Map<String, dynamic>>.from(
          existing?['revisions'] as List? ?? []);
      if (oldContent.isNotEmpty && oldContent != newContent) {
        revisions.add({
          'content': oldContent,
          'replacedAt': now,
        });
        // Keep last 5 revisions
        if (revisions.length > 5) {
          revisions.removeRange(0, revisions.length - 5);
        }
      }
      merged['revisions'] = revisions;
    }

    // Summary: always use new if provided
    merged['summary'] = concept['summary'] ?? existing?['summary'] ?? '';

    // Trigger words: union
    final triggers = <String>{
      ...(existing?['triggerWords'] as List?)?.map((e) => e.toString()) ?? [],
      ...(concept['triggerWords'] as List?)?.map((e) => e.toString()) ?? [],
    };
    merged['triggerWords'] = triggers.toList();

    // Related concepts: union
    final related = <String>{
      ...(existing?['relatedConcepts'] as List?)?.map((e) => e.toString()) ?? [],
      ...(concept['relatedConcepts'] as List?)?.map((e) => e.toString()) ?? [],
    };
    merged['relatedConcepts'] = related.toList();

    await _storage.saveSemanticMemory(id, merged);
    debugLog(DebugSource.updater,
        'Concept ${existing != null ? "UPDATED" : "CREATED"}: $id');
    return existing != null;
  }

  Future<void> _updateUserPreferences(Map<String, dynamic> prefs) async {
    final data = await _storage.loadSemanticMemory('user_preferences') ?? {
      'description': 'User preferences and learning profile',
      'preferences': <String, dynamic>{},
      'triggerWords': ['preferences', 'settings', 'like', 'prefer', 'favorite'],
      'summary': 'User preferences and learning profile.',
      'relatedConcepts': [],
    };
    final existing = Map<String, dynamic>.from(
        data['preferences'] as Map<String, dynamic>? ?? {});
    existing.addAll(prefs);
    data['preferences'] = existing;

    // Auto-generate trigger words from preference keys
    final triggers = <String>{
      'preferences', 'settings', 'like', 'prefer', 'favorite',
      ...prefs.keys.map((k) => k.toLowerCase()),
    };
    data['triggerWords'] = triggers.toList();
    data['summary'] = 'User preferences: ${existing.entries.take(10).map(
        (e) => '${e.key}=${e.value}').join(', ')}';

    await _storage.saveSemanticMemory('user_preferences', data);
    debugLog(DebugSource.updater, 'Prefs updated: ${prefs.keys.join(', ')}');
  }

  Future<void> _updateProceduralMemory(List notes) async {
    final data = await _storage.loadSemanticMemory('procedural') ?? {
      'description': 'Interaction patterns and communication style notes',
      'notes': [],
      'triggerWords': ['communicate', 'explain', 'style', 'help', 'teach'],
      'summary': 'Communication and teaching style observations.',
      'relatedConcepts': ['user_preferences'],
    };
    final existing = (data['notes'] as List?) ?? [];
    final allTriggers = <String>{
      ...(data['triggerWords'] as List?)?.map((e) => e.toString()) ?? [],
    };

    for (final note in notes) {
      if (note is Map<String, dynamic>) {
        existing.add({
          'note': note['note'] ?? note.toString(),
          'addedAt': DateTime.now().toIso8601String(),
        });
        // Add trigger words from procedural notes
        if (note['triggerWords'] is List) {
          allTriggers.addAll(
              (note['triggerWords'] as List).map((e) => e.toString()));
        }
      } else {
        existing.add({
          'note': note.toString(),
          'addedAt': DateTime.now().toIso8601String(),
        });
      }
    }

    // Keep last 50
    if (existing.length > 50) {
      data['notes'] = existing.sublist(existing.length - 50);
    } else {
      data['notes'] = existing;
    }

    data['triggerWords'] = allTriggers.toList();
    // Update summary
    final recentNotes = (data['notes'] as List)
        .take(5)
        .map((n) => n is Map ? n['note'] : n.toString())
        .join('; ');
    data['summary'] = 'Communication patterns: $recentNotes';

    await _storage.saveSemanticMemory('procedural', data);
    debugLog(DebugSource.updater, 'Procedural: +${notes.length} notes');
  }

  /// Daily memory consolidation — reviews all concepts for consistency,
  /// updates cross-references, and merges duplicates.
  /// Call this at most once per day (check lastConsolidation in settings).
  Future<void> consolidateMemory({
    required String universalApiKey,
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    debugLog(DebugSource.updater, 'Daily memory consolidation started...');

    try {
      final conceptIds = await _getExistingConceptIds();
      if (conceptIds.isEmpty) {
        debugLog(DebugSource.updater, 'No concepts to consolidate');
        return;
      }

      // Load all concepts
      final concepts = <String, Map<String, dynamic>>{};
      for (final id in conceptIds) {
        final data = await _storage.loadSemanticMemory(id);
        if (data != null) concepts[id] = data;
      }

      // Build a summary of all concepts for the LLM
      final conceptSummaries = concepts.entries.map((e) {
        final d = e.value;
        final tw = (d['triggerWords'] as List?)?.join(', ') ?? '';
        final rc = (d['relatedConcepts'] as List?)?.join(', ') ?? '';
        return '- ${e.key}: "${d['title'] ?? e.key}" '
            '(triggers: [$tw], related: [$rc], '
            'content: ${(d['content'] as String? ?? '').length} chars)';
      }).join('\n');

      // Ask LLM to review and suggest improvements
      final consolidationPrompt = '''Review these memory concepts and suggest improvements.
Return ONLY valid JSON.

CONCEPTS:
$conceptSummaries

Return this structure:
{
  "cross_references": [
    {"from": "concept_id_1", "to": "concept_id_2", "reason": "why related"}
  ],
  "missing_triggers": [
    {"id": "concept_id", "add_triggers": ["new_trigger1", "new_trigger2"]}
  ],
  "duplicates": [
    {"keep": "concept_id_to_keep", "merge": "concept_id_to_merge", "reason": "why duplicate"}
  ]
}

Rules:
- Only suggest cross_references between clearly related concepts
- Only add triggers that would realistically help find the concept
- Only flag true duplicates (same topic, different IDs)
- Return empty arrays if nothing to improve''';

      final response = await _chatService.chat(
        universalApiKey: universalApiKey,
        messages: [Message.user(consolidationPrompt)],
        systemPrompt: 'You are a memory organization assistant. Return only JSON.',
      );

      if (response.startsWith('[Error]')) {
        debugLog(DebugSource.updater, 'Consolidation LLM call failed: $response');
        return;
      }

      final parsed = _parseJsonResponse(response);
      if (parsed == null) {
        debugLog(DebugSource.updater, 'Could not parse consolidation response');
        return;
      }

      int updatedCount = 0;

      // Apply cross-references
      final crossRefs = parsed['cross_references'] as List? ?? [];
      for (final ref in crossRefs) {
        if (ref is! Map<String, dynamic>) continue;
        final from = ref['from'] as String?;
        final to = ref['to'] as String?;
        if (from == null || to == null) continue;
        if (!concepts.containsKey(from) || !concepts.containsKey(to)) continue;

        final fromData = concepts[from]!;
        final related = Set<String>.from(
            (fromData['relatedConcepts'] as List?)?.map((e) => e.toString()) ?? []);
        if (related.add(to)) {
          fromData['relatedConcepts'] = related.toList();
          await _storage.saveSemanticMemory(from, fromData);
          updatedCount++;
        }
        // Also add reverse reference
        final toData = concepts[to]!;
        final toRelated = Set<String>.from(
            (toData['relatedConcepts'] as List?)?.map((e) => e.toString()) ?? []);
        if (toRelated.add(from)) {
          toData['relatedConcepts'] = toRelated.toList();
          await _storage.saveSemanticMemory(to, toData);
          updatedCount++;
        }
      }

      // Apply missing triggers
      final missingTriggers = parsed['missing_triggers'] as List? ?? [];
      for (final mt in missingTriggers) {
        if (mt is! Map<String, dynamic>) continue;
        final id = mt['id'] as String?;
        final newTriggers = (mt['add_triggers'] as List?)
            ?.map((e) => e.toString()).toList() ?? [];
        if (id == null || newTriggers.isEmpty || !concepts.containsKey(id)) continue;

        final data = concepts[id]!;
        final triggers = Set<String>.from(
            (data['triggerWords'] as List?)?.map((e) => e.toString()) ?? []);
        final sizeBefore = triggers.length;
        triggers.addAll(newTriggers);
        if (triggers.length > sizeBefore) {
          data['triggerWords'] = triggers.toList();
          await _storage.saveSemanticMemory(id, data);
          updatedCount++;
        }
      }

      // Record consolidation timestamp
      await _storage.setSetting('lastConsolidation', DateTime.now().toIso8601String());

      debugLog(DebugSource.updater,
          'Consolidation complete: $updatedCount updates, '
          '${crossRefs.length} cross-refs, '
          '${missingTriggers.length} trigger additions');

      DebugLog.instance.addMemoryUpdate(MemoryUpdateRecord(
        timestamp: DateTime.now(),
        conversationId: 'consolidation',
        conceptsUpdated: updatedCount,
        updatedFiles: [],
        episodicSummary: 'Daily consolidation: $updatedCount updates',
        durationMs: 0,
      ));
    } catch (e) {
      debugLog(DebugSource.updater, 'Consolidation error: $e');
    } finally {
      _isRunning = false;
    }
  }

  Map<String, dynamic>? _parseJsonResponse(String response) {
    var text = response.trim();
    if (text.startsWith('```')) {
      final start = text.indexOf('\n');
      final end = text.lastIndexOf('```');
      if (start > 0 && end > start) {
        text = text.substring(start + 1, end).trim();
      }
    }
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (match != null) {
        try {
          return jsonDecode(match.group(0)!) as Map<String, dynamic>;
        } catch (_) {}
      }
      return null;
    }
  }
}
