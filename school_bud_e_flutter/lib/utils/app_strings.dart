/// Lightweight localization — language-aware UI strings.
///
/// Uses the persona's defaultLanguage setting to pick the right string.
/// Supports: Deutsch, English, Francais, Espanol.
library;

class S {
  S._();

  static String _lang = 'Deutsch';

  /// Set the active language. Call when persona switches.
  static void setLanguage(String language) {
    _lang = language;
  }

  static String get lang => _lang;
  static bool get isEnglish => _lang.toLowerCase().startsWith('en');
  static bool get isGerman => _lang.toLowerCase().startsWith('de') || _lang == 'Deutsch';

  // ─── Welcome Screen ───

  static String welcomeTitle(String name) => switch (_lang) {
    _ when isEnglish => 'Hey! I\'m $name',
    'Francais' => 'Salut ! Je suis $name',
    'Espanol' => '¡Hola! Soy $name',
    _ => 'Hey! Ich bin $name',
  };

  static String get welcomeSubtitle => switch (_lang) {
    _ when isEnglish => 'Your friendly assistant.\nType a message or tap the microphone.',
    'Francais' => 'Ton assistant amical.\nEcris-moi ou appuie sur le micro.',
    'Espanol' => 'Tu asistente amigable.\nEscribe o toca el microfono.',
    _ => 'Dein freundlicher Assistent.\nSchreib mir oder tippe aufs Mikrofon.',
  };

  static List<String> get welcomeSuggestions => switch (_lang) {
    _ when isEnglish => ['What can you do?', 'Tell me a joke', 'What is PERMA?'],
    'Francais' => ['Que sais-tu faire ?', 'Raconte-moi une blague', 'Qu\'est-ce que PERMA ?'],
    'Espanol' => ['Que puedes hacer?', 'Cuentame un chiste', 'Que es PERMA?'],
    _ => ['Was macht dich aus?', 'Erzaehl mir einen Witz', 'Was ist PERMA?'],
  };

  // ─── Chat Input ───

  static String get inputHint => switch (_lang) {
    _ when isEnglish => 'Type a message...',
    _ => 'Nachricht eingeben...',
  };

  static String get recordingHint => switch (_lang) {
    _ when isEnglish => 'Recording... tap to stop',
    _ => 'Aufnahme... tippe zum Stoppen',
  };

  // ─── Agent Status Messages ───

  static String agentStep(int step, int max) => switch (_lang) {
    _ when isEnglish => 'Step $step/$max',
    _ => 'Schritt $step/$max',
  };

  static String get agentGeneratingImage => switch (_lang) {
    _ when isEnglish => 'Generating image...',
    _ => 'Bild generieren...',
  };

  static String get agentSearchingWeb => switch (_lang) {
    _ when isEnglish => 'Searching the web...',
    _ => 'Websuche...',
  };

  static String get agentWritingFile => switch (_lang) {
    _ when isEnglish => 'Writing file...',
    _ => 'Datei schreiben...',
  };

  static String get agentResearching => switch (_lang) {
    _ when isEnglish => 'Researching...',
    _ => 'Recherche...',
  };

  static String get agentQualityCheck => switch (_lang) {
    _ when isEnglish => 'Quality check...',
    _ => 'Qualitaetskontrolle...',
  };

  // ─── Tool Results ───

  static String imageGenerated(String path) => switch (_lang) {
    _ when isEnglish => 'Here is the generated image:\nSaved to: $path',
    _ => 'Hier ist das generierte Bild:\nGespeichert unter: $path',
  };

  static String musicGenerated(String duration) => switch (_lang) {
    _ when isEnglish => 'Here is the generated music ($duration):',
    _ => 'Hier ist die generierte Musik ($duration):',
  };

  static String get musicFailed => switch (_lang) {
    _ when isEnglish => 'Music generation failed.',
    _ => 'Musikgenerierung fehlgeschlagen.',
  };

  static String get musicPolicyError => switch (_lang) {
    _ when isEnglish => 'Music generation was rejected by Google — '
        'the text or prompt contains terms that violate the content policy.\n\n'
        'Try rephrasing:\n'
        '- Avoid controversial or sensitive terms\n'
        '- Keep lyrics more general and positive\n'
        '- Write the prompt entirely in English\n\n'
        'Should I rewrite the prompt and lyrics for you?',
    _ => 'Die Musikgenerierung wurde von Google abgelehnt — '
        'der Text oder Prompt enthaelt Begriffe, die gegen die Content-Policy verstossen.\n\n'
        'Versuche den Text umzuformulieren:\n'
        '- Vermeide kontroverse oder sensible Begriffe\n'
        '- Halte Lyrics allgemeiner und positiver\n'
        '- Schreibe den Prompt komplett auf Englisch\n\n'
        'Soll ich den Prompt und die Lyrics fuer dich umschreiben?',
  };

  static String get noFilesCreated => switch (_lang) {
    _ when isEnglish => 'ERROR: No files were created! The task requires a file. Create it NOW with write_file.',
    _ => 'FEHLER: Du hast KEINE Dateien erstellt! Die Aufgabe verlangt eine Datei. Erstelle sie JETZT mit write_file.',
  };

  // ─── General UI ───

  static String get copied => switch (_lang) {
    _ when isEnglish => 'Copied',
    _ => 'Kopiert',
  };

  static String get editMessage => switch (_lang) {
    _ when isEnglish => 'Edit message',
    _ => 'Nachricht bearbeiten',
  };

  static String get editResponse => switch (_lang) {
    _ when isEnglish => 'Edit response',
    _ => 'Antwort bearbeiten',
  };

  static String get regenerate => switch (_lang) {
    _ when isEnglish => 'Regenerate',
    _ => 'Neu generieren',
  };

  static String get previousBranch => switch (_lang) {
    _ when isEnglish => 'Previous branch',
    _ => 'Vorheriger Branch',
  };

  static String get nextBranch => switch (_lang) {
    _ when isEnglish => 'Next branch',
    _ => 'Naechster Branch',
  };

  static String messagesCopied(int count) => switch (_lang) {
    _ when isEnglish => '$count messages copied',
    _ => '$count Nachrichten kopiert',
  };

  static String get conversations => switch (_lang) {
    _ when isEnglish => 'Conversations',
    _ => 'Konversationen',
  };

  static String get newChat => switch (_lang) {
    _ when isEnglish => 'New',
    _ => 'Neu',
  };

  static String get noConversations => switch (_lang) {
    _ when isEnglish => 'No saved conversations',
    _ => 'Keine gespeicherten Konversationen',
  };

  static String messagesCount(int n) => switch (_lang) {
    _ when isEnglish => '$n messages',
    _ => '$n Nachrichten',
  };

  // ─── Settings ───

  static String get settings => switch (_lang) {
    _ when isEnglish => 'Settings',
    _ => 'Einstellungen',
  };

  static String get loading => switch (_lang) {
    _ when isEnglish => 'Loading...',
    _ => 'Laden...',
  };
}
