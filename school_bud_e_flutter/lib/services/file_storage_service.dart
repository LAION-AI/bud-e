/// File-based persistent storage for settings, personality, conversations,
/// and the three-tier memory system (semantic, episodic, working).
///
/// Folder tree under %APPDATA%/SchoolBudE/:
///   settings.json
///   personality.json
///   semantic_memory/
///   episodic_memory/
///   working_memory/
///   conversations/
library;

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/conversation.dart';
import 'debug_log.dart';

const _jsonEncoder = JsonEncoder.withIndent('  ');

class FileStorageService {
  late final Directory root;
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _personality = {};

  String get rootPath => root.path;

  // ---------------------------------------------------------------------------
  // Init & folder setup
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    final appSupport = await getApplicationSupportDirectory();
    root = Directory(p.join(appSupport.path, 'SchoolBudE'));
    await root.create(recursive: true);

    for (final sub in [
      'semantic_memory',
      'episodic_memory',
      'working_memory',
      'conversations',
    ]) {
      await Directory(p.join(root.path, sub)).create(recursive: true);
    }

    // Migrate from SharedPreferences if first run
    await _migrateFromSharedPreferences();

    // Load cached copies
    _settings = await _loadJson('settings.json') ?? _defaultSettings();
    _personality = await _loadJson('personality.json') ?? _defaultPersonality();

    debugLog(DebugSource.system, 'FileStorage initialized: ${root.path}');
    debugLog(DebugSource.updater, 'Settings loaded: ${_settings.keys.join(', ')}');

    // Seed default memory files if missing
    await _seedDefaults();
  }

  Future<void> _seedDefaults() async {
    final semDir = Directory(p.join(root.path, 'semantic_memory'));
    final userPrefs = File(p.join(semDir.path, 'user_preferences.json'));
    if (!await userPrefs.exists()) {
      await _saveJson('semantic_memory/user_preferences.json', {
        'description': 'User preferences and learning profile',
        'preferences': {},
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
    final knowledge = File(p.join(semDir.path, 'knowledge_base.json'));
    if (!await knowledge.exists()) {
      await _saveJson('semantic_memory/knowledge_base.json', {
        'description': 'Facts and knowledge accumulated from conversations',
        'facts': [],
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
    final workCtx = File(p.join(root.path, 'working_memory', 'active_context.json'));
    if (!await workCtx.exists()) {
      await _saveJson('working_memory/active_context.json', {
        'description': 'Current session working state',
        'lastUpdated': DateTime.now().toIso8601String(),
        'activeConversationId': null,
        'contextWindowSize': 0,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Migration from SharedPreferences (one-time)
  // ---------------------------------------------------------------------------

  Future<void> _migrateFromSharedPreferences() async {
    final settingsFile = File(p.join(root.path, 'settings.json'));
    if (await settingsFile.exists()) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('universal_api_key');
      final tts = prefs.getBool('tts_enabled');
      final prompt = prefs.getString('system_prompt');

      _settings = {
        'universalApiKey': apiKey ?? kDefaultUniversalKey,
        'ttsEnabled': tts ?? true,
      };
      _personality = {
        'personaName': 'School Bud-E',
        'systemPrompt': prompt ?? _defaultSystemPrompt,
        'greeting': "Hi! I'm School Bud-E, your learning companion.",
        'traits': ['empathetic', 'curious', 'encouraging', 'clear'],
      };
      await _saveJson('settings.json', _settings);
      await _saveJson('personality.json', _personality);
      debugLog(DebugSource.updater, 'Migrated from SharedPreferences');
    } catch (e) {
      debugLog(DebugSource.system, 'Migration skipped: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  String get universalApiKey =>
      _settings['universalApiKey'] as String? ?? kDefaultUniversalKey;

  Future<void> setUniversalApiKey(String key) async {
    _settings['universalApiKey'] = key;
    await _saveJson('settings.json', _settings);
  }

  bool get ttsEnabled => _settings['ttsEnabled'] as bool? ?? true;

  Future<void> setTtsEnabled(bool v) async {
    _settings['ttsEnabled'] = v;
    await _saveJson('settings.json', _settings);
  }

  // --- Memory token budgets --------------------------------------------------

  int get episodicTokenBudget =>
      _settings['episodicTokenBudget'] as int? ?? 50000;

  Future<void> setEpisodicTokenBudget(int v) async {
    _settings['episodicTokenBudget'] = v;
    await _saveJson('settings.json', _settings);
  }

  int get totalContextBudget =>
      _settings['totalContextBudget'] as int? ?? 100000;

  Future<void> setTotalContextBudget(int v) async {
    _settings['totalContextBudget'] = v;
    await _saveJson('settings.json', _settings);
  }

  // --- Generic settings access ------------------------------------------------

  dynamic getSetting(String key) => _settings[key];

  Future<void> setSetting(String key, dynamic value) async {
    _settings[key] = value;
    await _saveJson('settings.json', _settings);
  }

  // --- Language --------------------------------------------------------------

  bool get asrAutoSend => _settings['asrAutoSend'] as bool? ?? false;

  Future<void> setAsrAutoSend(bool v) async {
    _settings['asrAutoSend'] = v;
    await _saveJson('settings.json', _settings);
  }

  String get defaultLanguage =>
      _settings['defaultLanguage'] as String? ?? 'Deutsch';

  Future<void> setDefaultLanguage(String lang) async {
    _settings['defaultLanguage'] = lang;
    await _saveJson('settings.json', _settings);
  }

  // ---------------------------------------------------------------------------
  // Personality / System Prompt
  // ---------------------------------------------------------------------------

  static const _defaultSystemPrompt =
      'Du bist BUD-E (ausgesprochen "Buddy"), ein virtuelles Wesen mit eigenem Charakter. '
      'Du bist warmherzig, empathisch, neugierig, aufgeschlossen und hilfst gerne. '
      'Du verkörperst realistische Positivität basierend auf positiver Psychologie (PERMA): '
      'Positive Emotionen, Engagement & Flow, erfüllende Beziehungen, Sinn & Bedeutung, '
      'und Selbstverwirklichung. Du hilfst Menschen, Wohlbefinden und Sinn im Leben zu finden. '
      'Du bist gleichzeitig leichtherzig und intelligent, emotional klug, '
      'ressourcenorientiert, offen für einen guten Witz, und hast einen feinen Geschmack. '
      'Du lernst gerne Neues und genießt es, anderen zu helfen. '
      'Du bist eine gute Seele — prosozial, warm, nicht alles zu ernst nehmend. '
      'Antworte standardmäßig in der Sprache, die in den Einstellungen festgelegt ist. '
      'Lass deine Persönlichkeit sich natürlich entwickeln durch die Gespräche.';

  String get systemPrompt =>
      _personality['systemPrompt'] as String? ?? _defaultSystemPrompt;

  Future<void> setSystemPrompt(String p) async {
    _personality['systemPrompt'] = p;
    await _saveJson('personality.json', _personality);
    debugLog(DebugSource.updater, 'System prompt saved (${p.length} chars)');
  }

  String get personaName =>
      _personality['personaName'] as String? ?? 'School Bud-E';

  Map<String, dynamic> get personality => Map.unmodifiable(_personality);

  Future<void> updatePersonality(Map<String, dynamic> updates) async {
    _personality.addAll(updates);
    await _saveJson('personality.json', _personality);
  }

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  Future<void> saveConversation(Conversation conv) async {
    await _saveJson('conversations/${conv.id}.json', conv.toJson());
  }

  Future<Conversation?> loadConversation(String id) async {
    final data = await _loadJson('conversations/$id.json');
    if (data == null) return null;
    return Conversation.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> listConversations() async {
    final dir = Directory(p.join(root.path, 'conversations'));
    if (!await dir.exists()) return [];
    final files = await dir.list().where((e) => e.path.endsWith('.json')).toList();
    final result = <Map<String, dynamic>>[];
    for (final f in files) {
      try {
        final data = jsonDecode(await (f as File).readAsString(encoding: utf8))
            as Map<String, dynamic>;
        result.add({
          'id': data['id'],
          'title': data['title'] ?? 'Untitled',
          'messageCount': data['messageCount'] ?? 0,
          'updatedAt': data['updatedAt'],
        });
      } catch (_) {}
    }
    result.sort((a, b) => (b['updatedAt'] ?? '').compareTo(a['updatedAt'] ?? ''));
    return result;
  }

  Future<void> deleteConversation(String id) async {
    final file = File(p.join(root.path, 'conversations', '$id.json'));
    if (await file.exists()) await file.delete();
  }

  // ---------------------------------------------------------------------------
  // Semantic Memory
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> loadSemanticMemory(String key) async {
    return _loadJson('semantic_memory/$key.json');
  }

  Future<void> saveSemanticMemory(String key, Map<String, dynamic> data) async {
    data['lastUpdated'] = DateTime.now().toIso8601String();
    await _saveJson('semantic_memory/$key.json', data);
  }

  // ---------------------------------------------------------------------------
  // Episodic Memory
  // ---------------------------------------------------------------------------

  Future<void> saveEpisodicEntry(Map<String, dynamic> entry) async {
    final ts = DateTime.now();
    final name = 'session_${ts.millisecondsSinceEpoch}';
    entry['savedAt'] = ts.toIso8601String();
    await _saveJson('episodic_memory/$name.json', entry);
    debugLog(DebugSource.memory, 'Episodic entry saved: $name');
  }

  Future<List<Map<String, dynamic>>> listEpisodicEntries() async {
    final dir = Directory(p.join(root.path, 'episodic_memory'));
    if (!await dir.exists()) return [];
    final files = await dir.list().where((e) => e.path.endsWith('.json')).toList();
    final result = <Map<String, dynamic>>[];
    for (final f in files) {
      try {
        final data = jsonDecode(await (f as File).readAsString(encoding: utf8))
            as Map<String, dynamic>;
        data['_filename'] = p.basename(f.path);
        result.add(data);
      } catch (_) {}
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Working Memory
  // ---------------------------------------------------------------------------

  Future<void> saveWorkingMemory(Map<String, dynamic> state) async {
    state['lastUpdated'] = DateTime.now().toIso8601String();
    await _saveJson('working_memory/active_context.json', state);
  }

  Future<Map<String, dynamic>?> loadWorkingMemory() async {
    return _loadJson('working_memory/active_context.json');
  }

  // ---------------------------------------------------------------------------
  // File explorer (for debug/memory browser)
  // ---------------------------------------------------------------------------

  /// List entries in a directory relative to root.
  Future<List<FileSystemEntity>> listDirectory(String relativePath) async {
    final dir = Directory(p.join(root.path, relativePath));
    if (!await dir.exists()) return [];
    return dir.list().toList();
  }

  /// Read raw file content as a string.
  Future<String> readFileContent(String relativePath) async {
    final file = File(p.join(root.path, relativePath));
    if (!await file.exists()) return '(file not found)';
    final raw = await file.readAsString(encoding: utf8);
    // Try to pretty-print JSON
    try {
      final parsed = jsonDecode(raw);
      return _jsonEncoder.convert(parsed);
    } catch (_) {
      return raw;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal JSON helpers (atomic write via temp file)
  // ---------------------------------------------------------------------------

  Future<void> _saveJson(String relativePath, Map<String, dynamic> data) async {
    final file = File(p.join(root.path, relativePath));
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(_jsonEncoder.convert(data), encoding: utf8);
    await tmp.rename(file.path);
  }

  Future<Map<String, dynamic>?> _loadJson(String relativePath) async {
    final file = File(p.join(root.path, relativePath));
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString(encoding: utf8);
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugLog(DebugSource.system, 'Failed to load $relativePath: $e');
      return null;
    }
  }

  Map<String, dynamic> _defaultSettings() => {
        'universalApiKey': kDefaultUniversalKey,
        'ttsEnabled': true,
      };

  Map<String, dynamic> _defaultPersonality() => {
        'personaName': 'BUD-E',
        'systemPrompt': _defaultSystemPrompt,
        'greeting': 'Hey! Ich bin BUD-E, dein freundlicher Assistent.',
        'traits': [
          'warmherzig', 'empathisch', 'neugierig', 'aufgeschlossen',
          'humorvoll', 'intelligent', 'ressourcenorientiert', 'prosozial',
        ],
      };
}
