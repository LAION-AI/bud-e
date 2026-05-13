/// Persistent memory store with three tiers:
///   - Working memory: current context window
///   - Episodic memory: conversation session summaries
///   - Semantic memory: facts, knowledge, user preferences
library;

import '../models/message.dart';
import '../services/file_storage_service.dart';
import '../services/debug_log.dart';

class MemoryStore {
  int maxContextMessages;
  final FileStorageService? _storage;
  final List<Message> _allMessages = [];
  final List<String> _summaries = [];

  MemoryStore({this.maxContextMessages = 40, FileStorageService? storage})
      : _storage = storage;

  List<Message> get allMessages => List.unmodifiable(_allMessages);

  void addMessage(Message m) {
    _allMessages.add(m);
  }

  void clear() {
    _allMessages.clear();
    _summaries.clear();
  }

  List<Message> contextWindow() {
    if (_allMessages.length <= maxContextMessages) {
      return List.of(_allMessages);
    }
    return _allMessages.sublist(_allMessages.length - maxContextMessages);
  }

  String? get memorySummary =>
      _summaries.isEmpty ? null : _summaries.join('\n\n');

  // ---------------------------------------------------------------------------
  // Working Memory persistence
  // ---------------------------------------------------------------------------

  Future<void> saveWorkingState({String? activeConversationId}) async {
    if (_storage == null) return;
    await _storage.saveWorkingMemory({
      'activeConversationId': activeConversationId,
      'messageCount': _allMessages.length,
      'contextWindowSize': contextWindow().length,
      'summaryCount': _summaries.length,
      'summaries': _summaries,
    });
    debugLog(DebugSource.memory, 'Working memory saved');
  }

  // ---------------------------------------------------------------------------
  // Episodic Memory — session summaries
  // ---------------------------------------------------------------------------

  Future<void> saveSessionSummary({
    required String conversationId,
    required String title,
  }) async {
    if (_storage == null || _allMessages.isEmpty) return;

    final userMsgs = _allMessages.where((m) => m.role == MessageRole.user);
    final assistantMsgs = _allMessages.where((m) => m.role == MessageRole.assistant);

    await _storage.saveEpisodicEntry({
      'conversationId': conversationId,
      'title': title,
      'userMessageCount': userMsgs.length,
      'assistantMessageCount': assistantMsgs.length,
      'totalMessages': _allMessages.length,
      'firstUserMessage': userMsgs.isNotEmpty
          ? (userMsgs.first.content.length > 200
              ? '${userMsgs.first.content.substring(0, 200)}...'
              : userMsgs.first.content)
          : null,
      'topics': _extractTopics(),
      'duration': _allMessages.length > 1
          ? _allMessages.last.timestamp
              .difference(_allMessages.first.timestamp)
              .inSeconds
          : 0,
    });
  }

  List<String> _extractTopics() {
    // Simple topic extraction: first few words of each user message
    return _allMessages
        .where((m) => m.role == MessageRole.user)
        .take(5)
        .map((m) {
          final words = m.content.split(' ').take(6).join(' ');
          return words.length > 50 ? '${words.substring(0, 50)}...' : words;
        })
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Semantic Memory — facts and knowledge
  // ---------------------------------------------------------------------------

  Future<void> addSemanticFact(String category, String fact) async {
    if (_storage == null) return;
    final data = await _storage.loadSemanticMemory('knowledge_base') ?? {
      'description': 'Facts and knowledge accumulated from conversations',
      'facts': [],
    };
    final facts = (data['facts'] as List?) ?? [];
    facts.add({
      'category': category,
      'fact': fact,
      'addedAt': DateTime.now().toIso8601String(),
    });
    data['facts'] = facts;
    await _storage.saveSemanticMemory('knowledge_base', data);
    debugLog(DebugSource.memory, 'Semantic fact added: $category');
  }

  Future<void> updateUserPreference(String key, dynamic value) async {
    if (_storage == null) return;
    final data = await _storage.loadSemanticMemory('user_preferences') ?? {
      'description': 'User preferences and learning profile',
      'preferences': {},
    };
    (data['preferences'] as Map<String, dynamic>? ?? {})[key] = value;
    await _storage.saveSemanticMemory('user_preferences', data);
    debugLog(DebugSource.memory, 'User preference updated: $key');
  }

  /// Placeholder for future LLM-powered summarisation.
  Future<void> summariseOlderMessages() async {
    // TODO: call LLM to summarise messages beyond the context window
  }
}
