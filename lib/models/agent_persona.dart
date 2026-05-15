/// Agent persona model — each persona has its own memory, skills, and personality.
library;

class AgentPersona {
  final String id;
  String displayName;
  String avatarEmoji;
  String systemPrompt;
  String greeting;
  String defaultLanguage;
  List<String> traits;
  List<String> enabledSkills;
  List<String> suggestedPrompts;
  final DateTime createdAt;
  DateTime updatedAt;
  String? clonedFrom;

  AgentPersona({
    required this.id,
    required this.displayName,
    this.avatarEmoji = '🤖',
    this.systemPrompt = '',
    this.greeting = '',
    this.defaultLanguage = 'Deutsch',
    List<String>? traits,
    List<String>? enabledSkills,
    List<String>? suggestedPrompts,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.clonedFrom,
  })  : traits = traits ?? ['empathetic', 'curious', 'encouraging'],
        enabledSkills = enabledSkills ?? _allSkillIds,
        suggestedPrompts = suggestedPrompts ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Directory name for this persona's data.
  String get directoryName => id;

  /// Clone this persona with a new ID and name.
  AgentPersona clone({required String newId, required String newName}) =>
      AgentPersona(
        id: newId,
        displayName: newName,
        avatarEmoji: avatarEmoji,
        systemPrompt: systemPrompt,
        greeting: greeting,
        defaultLanguage: defaultLanguage,
        traits: List.of(traits),
        enabledSkills: List.of(enabledSkills),
        suggestedPrompts: List.of(suggestedPrompts),
        clonedFrom: id,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'avatarEmoji': avatarEmoji,
        'systemPrompt': systemPrompt,
        'greeting': greeting,
        'defaultLanguage': defaultLanguage,
        'traits': traits,
        'enabledSkills': enabledSkills,
        'suggestedPrompts': suggestedPrompts,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (clonedFrom != null) 'clonedFrom': clonedFrom,
      };

  factory AgentPersona.fromJson(Map<String, dynamic> json) => AgentPersona(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? json['id'] as String,
        avatarEmoji: json['avatarEmoji'] as String? ?? '🤖',
        systemPrompt: json['systemPrompt'] as String? ?? '',
        greeting: json['greeting'] as String? ?? '',
        defaultLanguage: json['defaultLanguage'] as String? ?? 'Deutsch',
        traits: (json['traits'] as List?)?.cast<String>(),
        enabledSkills: (json['enabledSkills'] as List?)?.cast<String>(),
        suggestedPrompts: (json['suggestedPrompts'] as List?)?.cast<String>(),
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
        clonedFrom: json['clonedFrom'] as String?,
      );

  static const _allSkillIds = [
    'memory_search', 'wikipedia', 'memory_save', 'weather', 'news',
    'generate_image', 'generate_music', 'bildungsplan_search', 'run_agent',
  ];

  /// All available skill definitions for the skill explorer.
  static List<Map<String, String>> get allSkillDefinitions => [
    {'id': 'memory_search', 'name': 'Memory Search', 'icon': '🧠', 'category': 'memory',
     'description': 'Search through stored memories and facts'},
    {'id': 'memory_save', 'name': 'Memory Save', 'icon': '💾', 'category': 'memory',
     'description': 'Save facts and preferences to long-term memory'},
    {'id': 'wikipedia', 'name': 'Wikipedia', 'icon': '📚', 'category': 'research',
     'description': 'Look up facts on Wikipedia'},
    {'id': 'weather', 'name': 'Weather', 'icon': '🌤️', 'category': 'research',
     'description': 'Get current weather and forecasts'},
    {'id': 'news', 'name': 'News', 'icon': '📰', 'category': 'research',
     'description': 'Get latest news from tagesschau.de'},
    {'id': 'generate_image', 'name': 'Image Generation', 'icon': '🎨', 'category': 'creative',
     'description': 'Generate and edit images (Gemini, Imagen, FLUX.2)'},
    {'id': 'generate_music', 'name': 'Music Generation', 'icon': '🎵', 'category': 'creative',
     'description': 'Generate songs with vocals and lyrics (Lyria 3 Pro)'},
    {'id': 'bildungsplan_search', 'name': 'Curriculum Search', 'icon': '🏫', 'category': 'education',
     'description': 'Search through education curricula (BM25)'},
    {'id': 'run_agent', 'name': 'Sub-Agent', 'icon': '🤖', 'category': 'files',
     'description': 'Create documents, presentations, research tasks'},
  ];
}
