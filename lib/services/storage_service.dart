/// Persistent settings storage using SharedPreferences.
library;

import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class StorageService {
  static const _keyUniversalApiKey = 'universal_api_key';
  static const _keyTtsEnabled = 'tts_enabled';
  static const _keySystemPrompt = 'system_prompt';

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- Universal API Key ---------------------------------------------------

  String get universalApiKey =>
      _prefs.getString(_keyUniversalApiKey) ?? kDefaultUniversalKey;

  Future<void> setUniversalApiKey(String key) =>
      _prefs.setString(_keyUniversalApiKey, key);

  // --- TTS toggle ----------------------------------------------------------

  bool get ttsEnabled => _prefs.getBool(_keyTtsEnabled) ?? true;

  Future<void> setTtsEnabled(bool v) => _prefs.setBool(_keyTtsEnabled, v);

  // --- System prompt -------------------------------------------------------

  static const _defaultSystemPrompt =
      'You are School Bud-E, a friendly and empathetic AI learning assistant. '
      'You help students learn by answering questions clearly, encouraging '
      'curiosity, and adapting to each learner. Keep answers concise unless '
      'the student asks for more detail.';

  String get systemPrompt =>
      _prefs.getString(_keySystemPrompt) ?? _defaultSystemPrompt;

  Future<void> setSystemPrompt(String p) =>
      _prefs.setString(_keySystemPrompt, p);
}
