/// Central state management for the chat.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/message.dart';
import '../models/conversation.dart';
import '../models/agent_task.dart';
import '../services/chat_service.dart';
import '../services/tts_service.dart';
import '../services/asr_service.dart';
import '../services/file_storage_service.dart';
import '../services/context_builder.dart';
import '../services/memory_search.dart';
import '../services/debug_log.dart';
import '../memory/memory_store.dart';
import '../config/api_config.dart';
import '../agents/agent_registry.dart';
import '../agents/memory_updater.dart';
import '../agents/wikipedia_agent.dart';
import '../agents/sub_agent_runner.dart';
import '../services/bildungsplan_search.dart';
import '../utils/app_strings.dart';
import '../agents/tools/web_tools.dart' as web_tools;
import '../services/image_registry.dart';
import '../agents/tools/pdf_tools.dart' as pdf_tools;

/// Tool-call patterns using [[...]] syntax.
final _memorySearchRegex = RegExp(
    r'\[\[tool:memory_search\s+query="([^"]+)"\]\]');
final _wikiRegex = RegExp(
    r'\[\[tool:wikipedia\s+query="([^"]+)"(?:\s+depth="(summary|abstract|full)")?\]\]');
final _memorySaveRegex = RegExp(
    r'\[\[tool:memory_save\s+id="([^"]+)"\s+content="([^"]+)"\]\]');
final _runAgentRegex = RegExp(
    r'\[\[tool:run_agent\s+instruction="((?:[^"\\]|\\.)*)"\s*(?:files="([^"]*)")?\s*\]\]');
final _weatherRegex = RegExp(
    r'\[\[tool:weather\s+location="([^"]+)"\]\]');
final _imageGenRegex = RegExp(
    r'\[\[tool:generate_image\s+prompt="([^"]+)"(?:\s+model="([^"]*)")?(?:\s+size="([^"]*)")?(?:\s+aspect="([^"]*)")?(?:\s+ref="([^"]*)")?\]\]');
final _musicGenRegex = RegExp(
    r'\[\[tool:generate_music\s+prompt="([^"]+)"(?:\s+negative_prompt="([^"]*)")?\]\]');
final _bildungsplanRegex = RegExp(
    r'\[\[tool:bildungsplan_search\s+query="([^"]+)"(?:\s+fach="([^"]*)")?(?:\s+schulform="([^"]*)")?\]\]');
final _newsRegex = RegExp(
    r'\[\[tool:news(?:\s+topic="([^"]*)")?\]\]');

/// Matches any [[...]] block for TTS stripping.
final _toolBlockRegex = RegExp(r'\[\[.*?\]\]', dotAll: true);

/// Strip tool call/result blocks from text.
String stripToolBlocks(String text) =>
    text.replaceAll(_toolBlockRegex, '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

class ChatProvider extends ChangeNotifier {
  final ChatService _chatService = ChatService();
  final TtsService _ttsService = TtsService();
  final AsrService _asrService = AsrService();
  final WikipediaAgent _wikiAgent = WikipediaAgent();
  final FileStorageService storage;
  late final MemoryStore memory;
  late final ContextBuilder contextBuilder;
  late final MemorySearch memorySearch;
  late final BildungsplanSearch bildungsplanSearch;
  final AgentRegistry agents = AgentRegistry();

  Conversation _conversation = Conversation(id: '0');
  bool _isLoading = false;
  bool _isRecording = false;
  StreamSubscription<String>? _streamSub;

  late final MemoryUpdater _memoryUpdater;
  BuiltContext? lastBuiltContext;

  /// Active sub-agent tasks.
  final Map<String, AgentTask> _agentTasks = {};
  Map<String, AgentTask> get agentTasks => Map.unmodifiable(_agentTasks);

  /// Workspace path for file uploads and agent outputs.
  String get workspacePath => p.join(storage.rootPath, 'agent_workspace');

  /// Image registry — tracks all images with unique IDs.
  final ImageRegistry imageRegistry = ImageRegistry();

  ChatProvider({required this.storage}) {
    memory = MemoryStore(storage: storage);
    contextBuilder = ContextBuilder(storage);
    memorySearch = MemorySearch(storage);
    bildungsplanSearch = BildungsplanSearch(
        p.join(storage.rootPath, 'bildungsplaene'));
    _memoryUpdater = MemoryUpdater(storage);
    S.setLanguage(storage.defaultLanguage);
    debugLog(DebugSource.system, 'ChatProvider initialized');

    // Build BM25 indexes in background
    memorySearch.buildIndex().catchError((_) {});
    bildungsplanSearch.buildIndex().catchError((_) {});

    // Check if daily memory consolidation is needed
    _checkDailyConsolidation();
  }

  void _checkDailyConsolidation() {
    final lastStr = storage.getSetting('lastConsolidation') as String?;
    final now = DateTime.now();
    bool needsConsolidation = true;

    if (lastStr != null) {
      try {
        final last = DateTime.parse(lastStr);
        needsConsolidation = now.difference(last).inHours >= 24;
      } catch (_) {}
    }

    if (needsConsolidation && storage.universalApiKey.isNotEmpty) {
      debugLog(DebugSource.updater, 'Starting daily memory consolidation...');
      _memoryUpdater.consolidateMemory(
        universalApiKey: storage.universalApiKey,
      ).then((_) {
        contextBuilder.invalidateCache();
        memorySearch.markDirty();
      }).catchError((_) {});
    }
  }

  // --- Getters ---------------------------------------------------------------

  List<Message> get messages => _conversation.messages;
  bool get isLoading => _isLoading;
  bool get isRecording => _isRecording;
  bool get ttsEnabled => storage.ttsEnabled;
  String get universalApiKey => storage.universalApiKey;
  Conversation get conversation => _conversation;

  /// Exposed for the replay button in message bubbles.
  TtsService get ttsServiceForReplay => _ttsService;

  // --- Settings --------------------------------------------------------------

  Future<void> setTtsEnabled(bool v) async {
    await storage.setTtsEnabled(v);
    notifyListeners();
  }

  Future<void> setUniversalApiKey(String key) async {
    await storage.setUniversalApiKey(key);
    notifyListeners();
  }

  // --- File management -------------------------------------------------------

  /// Copy a file into the agent workspace. Returns the destination path.
  Future<String?> copyFileToWorkspace(String sourcePath) async {
    try {
      final dir = Directory(workspacePath);
      if (!await dir.exists()) await dir.create(recursive: true);
      final name = p.basename(sourcePath);
      final dest = p.join(workspacePath, name);
      await File(sourcePath).copy(dest);
      debugLog(DebugSource.system, 'File copied to workspace: $name');
      return dest;
    } catch (e) {
      debugLog(DebugSource.system, 'File copy failed: $e');
      return null;
    }
  }

  /// Send a message with file attachments.
  /// Images/PDFs are sent as multimodal content, text files are inlined.
  Future<void> sendMessageWithFiles(
      String text, List<String> filePaths) async {
    final multimodalFiles = <String>[]; // images, small PDFs → sent as base64
    final textContents = <String>[]; // text files + PDF text → inlined
    final largePdfFiles = <String>[]; // large PDFs → route to sub-agent

    final audioFiles = <String>[]; // audio files → shown with player

    for (final fp in filePaths) {
      final ext = p.extension(fp).toLowerCase();
      if ({'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'}.contains(ext)) {
        multimodalFiles.add(fp);
        final imgId = imageRegistry.register(fp, source: 'uploaded');
        textContents.add('[Bild hochgeladen: ${p.basename(fp)}, ID: $imgId]');
      } else if ({'.wav', '.mp3', '.ogg', '.m4a', '.flac', '.aac'}.contains(ext)) {
        audioFiles.add(fp);
        textContents.add('[Audio-Datei: ${p.basename(fp)}]');
      } else if (ext == '.pdf') {
        // Smart PDF routing based on size and content
        try {
          final bytes = await File(fp).readAsBytes();
          final pageCount = pdf_tools.estimatePageCount(bytes);
          final sizeMb = bytes.length / (1024 * 1024);

          if (sizeMb > 2 || pageCount > 10) {
            // Large PDF → extract text if possible, otherwise route to agent
            final extracted = pdf_tools.extractTextBasic(bytes);
            final totalChars = extracted.values.fold(0, (s, t) => s + t.length);
            if (totalChars > 100) {
              // Good text extraction — include ALL pages as text context
              // BUD-E can answer directly, NO agent needed
              final buf = StringBuffer('--- PDF: ${p.basename(fp)} ($pageCount Seiten) ---\n');
              for (final e in extracted.entries) {
                buf.writeln('[Seite ${e.key}] ${e.value}');
              }
              textContents.add(buf.toString());
              debugLog(DebugSource.mainAgent,
                  'PDF text extracted: ${extracted.length} pages, $totalChars chars');
            } else {
              // No text extractable → agent must handle it
              largePdfFiles.add(fp);
              textContents.add('[PDF: ${p.basename(fp)} - $pageCount Seiten, ${sizeMb.toStringAsFixed(1)} MB - '
                  'wird von Agent im Hintergrund analysiert]');
            }
          } else {
            // Small PDF → send directly as multimodal
            // But also try text extraction as backup
            final extracted = pdf_tools.extractTextBasic(bytes);
            final totalChars = extracted.values.fold(0, (s, t) => s + t.length);
            if (totalChars > 50) {
              // Include extracted text AND the PDF binary
              final buf = StringBuffer('--- PDF-Text: ${p.basename(fp)} ---\n');
              for (final e in extracted.entries) {
                buf.writeln('[Seite ${e.key}] ${e.value}');
              }
              textContents.add(buf.toString());
            }
            multimodalFiles.add(fp);
          }
        } catch (e) {
          debugLog(DebugSource.mainAgent, 'PDF processing error: $e');
          // Route to agent on any error (including stack overflow)
          largePdfFiles.add(fp);
          textContents.add('[PDF: ${p.basename(fp)} - Fehler bei Vorverarbeitung, '
              'wird von Agent analysiert]');
        }
      } else {
        // Text files → read and inline
        try {
          final content = await File(fp).readAsString();
          final name = p.basename(fp);
          final capped = content.length > 30000
              ? '${content.substring(0, 30000)}\n...(abgeschnitten)'
              : content;
          textContents.add('--- Datei: $name ---\n$capped');
        } catch (_) {
          textContents.add('--- Datei: ${p.basename(fp)} (nicht lesbar) ---');
        }
      }
    }

    // Build message text
    final parts = <String>[];
    if (text.isNotEmpty) parts.add(text);
    if (textContents.isNotEmpty) parts.addAll(textContents);
    if (multimodalFiles.isNotEmpty) {
      parts.add('[Angehängte Mediendateien: ${multimodalFiles.map((f) => p.basename(f)).join(", ")}]');
    }
    // For large PDFs, auto-spawn agent after sending the message
    if (largePdfFiles.isNotEmpty) {
      parts.add('[Grosse PDFs werden von einem Agenten im Hintergrund analysiert: '
          '${largePdfFiles.map((f) => p.basename(f)).join(", ")}]');
    }

    _pendingFiles = filePaths;

    // Detect exam grading request — force agent spawn
    final lowerText = text.toLowerCase();
    final isExamGrading = filePaths.any((f) => f.toLowerCase().endsWith('.pdf')) &&
        (lowerText.contains('korrigier') || lowerText.contains('korrektur') ||
         lowerText.contains('bewert') || lowerText.contains('klausur') ||
         lowerText.contains('klassenarbeit') || lowerText.contains('pruef') ||
         lowerText.contains('prüf') || lowerText.contains('grade') ||
         lowerText.contains('note'));

    if (isExamGrading) {
      // Don't inline PDF text — let the agent handle everything
      // Check if there's an Erwartungshorizont
      final hasEH = filePaths.any((f) {
        final name = p.basename(f).toLowerCase();
        return name.contains('erwartung') || name.contains('horizont') ||
               name.contains('kriterien') || name.contains('bewertung') ||
               name.contains('loesung');
      });
      if (!hasEH && !lowerText.contains('erwartung') && !lowerText.contains('kriterien')) {
        // No EH detected — ask the user
        final askMsg = Message.assistant(
          'Ich sehe Klassenarbeiten zum Korrigieren. Hast du auch einen '
          'Erwartungshorizont oder Bewertungskriterien? Wenn ja, lade ihn '
          'bitte auch hoch oder beschreibe die Kriterien. Wenn nicht, '
          'korrigiere ich nach bestem Wissen.');
        _conversation.addMessage(Message.user(parts.join('\n\n')));
        _conversation.addMessage(askMsg);
        memory.addMessage(askMsg);
        _isLoading = false;
        notifyListeners();
        _pendingFiles = null;
        return;
      }
      // Force agent spawn — pre-transcribe PDFs so agent has actual content
      final userMsg = Message.user(parts.join('\n\n'));
      _conversation.addMessage(userMsg);
      memory.addMessage(userMsg);
      _conversation.autoTitle();
      notifyListeners();

      final agentMsg = Message.assistant(
        'Ich starte einen Agenten, der die Klassenarbeiten analysiert und korrigiert. '
        'Das kann einen Moment dauern...');
      _conversation.addMessage(agentMsg);
      memory.addMessage(agentMsg);
      notifyListeners();

      // Pre-transcribe PDF content so the agent has the actual text
      final transcription = StringBuffer();
      for (final fp in filePaths) {
        if (!fp.toLowerCase().endsWith('.pdf')) continue;
        final name = p.basename(fp);
        try {
          final bytes = await File(fp).readAsBytes();
          final extracted = pdf_tools.extractTextBasic(bytes);
          if (extracted.isNotEmpty) {
            transcription.writeln('=== $name (Text extrahiert) ===');
            for (final e in extracted.entries) {
              transcription.writeln('[Seite ${e.key}] ${e.value}');
            }
          } else {
            transcription.writeln('=== $name (kein Text extrahierbar - Agent muss analyze_pdf_pages nutzen) ===');
          }
        } catch (_) {
          transcription.writeln('=== $name (Fehler bei Text-Extraktion) ===');
        }
      }

      final fileNames = filePaths.map((f) => p.basename(f)).join(', ');
      _pendingFiles = filePaths;
      _spawnSubAgent(
        'Korrigiere die folgenden Klassenarbeiten. $text\n\n'
        'TRANSKRIPTION DER DATEIEN:\n${transcription.toString()}\n\n'
        'AUFGABE:\n'
        '1. Identifiziere ALLE Schueler anhand der Namen in der Transkription.\n'
        '2. Ordne alle Seiten den richtigen Schuelern zu.\n'
        '3. Bewerte JEDE Teilaufgabe einzeln mit Punkten und Begruendung.\n'
        '4. Erstelle fuer JEDEN Schueler eine separate .docx Datei (Word-Format).\n'
        '   Dateiname: korrektur_[vorname_nachname].docx\n'
        '5. Nenne am Ende die absoluten Dateipfade.\n'
        'Dateien im Workspace: $fileNames\n'
        'Workspace-Pfad: $workspacePath',
        '',
        agentMsg,
      );
      _pendingFiles = null;
      return;
    }

    // Create user message with attached media files
    // Combine all media files for the message (images + audio)
    final allMediaFiles = [...multimodalFiles, ...audioFiles];
    final userMsg = Message.user(
      parts.join('\n\n'),
      files: allMediaFiles.isNotEmpty ? allMediaFiles : null,
    );
    _conversation.addMessage(userMsg);
    memory.addMessage(userMsg);
    _conversation.autoTitle();
    _isLoading = true;
    notifyListeners();

    debugLog(DebugSource.mainAgent,
        'User (${multimodalFiles.length} media, ${textContents.length} text files): '
        '"${text.length > 60 ? '${text.substring(0, 60)}...' : text}"');

    try {
      BuiltContext builtCtx;
      try {
        final currentConvoText = memory.allMessages
            .map((m) => '${m.role.name}: ${m.content}')
            .join('\n');
        builtCtx = await contextBuilder.buildContext(
          episodicBudget: storage.episodicTokenBudget,
          totalBudget: storage.totalContextBudget,
          currentConversationText: currentConvoText,
        ).timeout(const Duration(seconds: 10));
        lastBuiltContext = builtCtx;
      } catch (e) {
        builtCtx = BuiltContext(
          episodicContext: '', episodicTokens: 0, activatedMemories: [],
          semanticContext: '', semanticTokens: 0, totalTokens: 0,
        );
      }

      final fullSystemPrompt = _buildSystemPrompt(builtCtx);

      final assistantMsg = Message.assistant('');
      _conversation.addMessage(assistantMsg);
      notifyListeners();

      await _streamResponse(
        assistantMsg: assistantMsg,
        systemPrompt: fullSystemPrompt,
        streamTts: true,
      );

      _isLoading = false;
      _conversation.updatedAt = DateTime.now();
      notifyListeners();

      _processToolCallsAsync(assistantMsg, fullSystemPrompt);

      // Auto-spawn agent for large PDFs
      if (largePdfFiles.isNotEmpty) {
        final instruction = text.isNotEmpty
            ? '$text (Dateien: ${largePdfFiles.map((f) => p.basename(f)).join(", ")})'
            : 'Analysiere diese PDFs und erstelle eine Zusammenfassung: '
              '${largePdfFiles.map((f) => p.basename(f)).join(", ")}';
        // Override _pendingFiles to only include the large PDFs
        _pendingFiles = largePdfFiles;
        _spawnSubAgent(instruction, '', assistantMsg);
      }
    } catch (e) {
      debugLog(DebugSource.mainAgent, 'Fatal error: $e');
      _isLoading = false;
      notifyListeners();
    }
    _pendingFiles = null;
  }

  List<String>? _pendingFiles;

  // --- Chat ------------------------------------------------------------------

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    final userMsg = Message.user(text);
    _conversation.addMessage(userMsg);
    memory.addMessage(userMsg);
    _conversation.autoTitle();
    _isLoading = true;
    notifyListeners();

    debugLog(DebugSource.mainAgent,
        'User: "${text.length > 80 ? '${text.substring(0, 80)}...' : text}"');

    try {
      // Build context (with timeout to prevent freeze)
      BuiltContext builtCtx;
      try {
        final currentConvoText = memory.allMessages
            .map((m) => '${m.role.name}: ${m.content}')
            .join('\n');

        builtCtx = await contextBuilder.buildContext(
          episodicBudget: storage.episodicTokenBudget,
          totalBudget: storage.totalContextBudget,
          currentConversationText: currentConvoText,
        ).timeout(const Duration(seconds: 10));
        lastBuiltContext = builtCtx;
      } catch (e) {
        debugLog(DebugSource.contextConstructor, 'Context build failed: $e');
        // Fallback: empty context
        builtCtx = BuiltContext(
          episodicContext: '',
          episodicTokens: 0,
          activatedMemories: [],
          semanticContext: '',
          semanticTokens: 0,
          totalTokens: 0,
        );
      }

      final fullSystemPrompt = _buildSystemPrompt(builtCtx);
      debugLog(DebugSource.contextConstructor,
          'System prompt: ${fullSystemPrompt.length} chars (~${estimateTokens(fullSystemPrompt)} tokens)');

      // Record context snapshot for debug screen
      DebugLog.instance.addContextSnapshot(ContextSnapshot(
        timestamp: DateTime.now(),
        userMessage: text,
        episodicTokens: builtCtx.episodicTokens,
        semanticTokens: builtCtx.semanticTokens,
        totalTokens: builtCtx.totalTokens,
        episodicContext: builtCtx.episodicContext,
        semanticContext: builtCtx.semanticContext,
        activatedMemories: builtCtx.activatedMemories,
        systemPrompt: fullSystemPrompt,
      ));

      // --- First LLM call ---
      final assistantMsg = Message.assistant('');
      _conversation.addMessage(assistantMsg);
      notifyListeners();

      await _streamResponse(
        assistantMsg: assistantMsg,
        systemPrompt: fullSystemPrompt,
        streamTts: true,
      );

      // --- Release input IMMEDIATELY after streaming ---
      _isLoading = false;
      _conversation.updatedAt = DateTime.now();
      notifyListeners();

      // --- Check for tool calls → execute → follow-up (non-blocking) ---
      _processToolCallsAsync(assistantMsg, fullSystemPrompt);

      // Safety net: if user asked for file creation but BUD-E didn't spawn agent
      if (!assistantMsg.content.contains('tool:run_agent') &&
          _shouldForceAgent(text, assistantMsg.content)) {
        debugLog(DebugSource.mainAgent,
            'Force-spawning agent for file creation task');
        _spawnSubAgent(text, '', assistantMsg);
      }

      // Safety net: if LLM wrote run_agent but regex didn't match, extract manually
      if (!assistantMsg.content.contains('agentTaskId') &&
          assistantMsg.content.contains('tool:run_agent') &&
          _agentTasks.values.every((t) =>
              t.status == AgentTaskStatus.completed || t.status == AgentTaskStatus.error)) {
        // Extract instruction from content even with bad escaping
        final fallbackMatch = RegExp(r'instruction="(.*?)"', dotAll: true)
            .firstMatch(assistantMsg.content);
        if (fallbackMatch != null) {
          final instr = fallbackMatch.group(1)!
              .replaceAll('\\"', '"').replaceAll('\\n', '\n');
          debugLog(DebugSource.mainAgent, 'Fallback agent spawn from malformed tool call');
          _spawnSubAgent(instr, '', assistantMsg);
        }
      }

      // Safety net: force bildungsplan search if LLM didn't use ANY tool
      if (!assistantMsg.content.contains('[[tool:') &&
          _looksLikeBildungsplanQuery(text)) {
        debugLog(DebugSource.mainAgent,
            'Force-triggering bildungsplan_search for: $text');
        _forceBildungsplanSearch(text, assistantMsg, fullSystemPrompt);
      }
    } catch (e) {
      debugLog(DebugSource.mainAgent, 'Fatal error: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Detect if user asks about Bildungspläne/Lehrpläne.
  bool _looksLikeBildungsplanQuery(String text) {
    final lower = text.toLowerCase();
    final keywords = ['lehrplan', 'bildungsplan', 'curriculum', 'unterrichtsinhalt',
        'schulfach', 'rahmenplan', 'kerncurriculum', 'bildungsstandard',
        'kompetenzbereich', 'themenfeld'];
    final subjectKeywords = ['informatik', 'mathematik', 'deutsch', 'englisch',
        'biologie', 'chemie', 'physik', 'geschichte', 'geographie', 'sport',
        'religion', 'wirtschaft', 'sachunterricht', 'psychologie'];
    // Must mention a curriculum-related keyword
    final hasCurrKeyword = keywords.any((k) => lower.contains(k));
    // Or must mention a subject + school context
    final hasSubject = subjectKeywords.any((k) => lower.contains(k));
    final hasSchoolCtx = ['schule', 'klasse', 'jahrgang', 'sekundar', 'grundschule',
        'gymnasium', 'stadtteilschule', 'oberstufe', 'stufe'].any((k) => lower.contains(k));
    return hasCurrKeyword || (hasSubject && hasSchoolCtx);
  }

  /// Force a bildungsplan search and append results directly.
  Future<void> _forceBildungsplanSearch(
      String userText, Message assistantMsg, String systemPrompt) async {
    final query = userText.replaceAll(RegExp(r'[?!.,]'), '').trim();

    await bildungsplanSearch.buildIndex();
    final results = bildungsplanSearch.search(query, limit: 5);
    if (results.isEmpty) return;

    // Build a direct answer with links (don't rely on LLM to format)
    final buf = StringBuffer('\n\nIch habe den Bildungsplan-Index durchsucht:\n\n');
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buf.writeln('**${r.page.sourceRef}** (Relevanz: ${r.score.toStringAsFixed(1)})');
      buf.writeln('> ${r.snippet}');
      if (r.page.pdfPageLink.isNotEmpty) {
        buf.writeln('${r.page.pdfPageLink}');
      }
      buf.writeln();
    }

    // Append directly to the existing assistant message
    assistantMsg.content += buf.toString();
    notifyListeners();
    storage.saveConversation(_conversation).catchError((_) {});
  }

  /// Detect if user wants file creation but BUD-E answered inline.
  bool _shouldForceAgent(String userText, String assistantResponse) {
    final lower = userText.toLowerCase();
    // User explicitly asked for a file
    final wantsFile = lower.contains('.docx') || lower.contains('.doc ') ||
        lower.contains('word-datei') || lower.contains('word datei') ||
        lower.contains('als datei') || lower.contains('als dokument') ||
        lower.contains('.pptx') || lower.contains('powerpoint') ||
        lower.contains('praesentation') || lower.contains('präsentation') ||
        (lower.contains('speicher') && (lower.contains('datei') || lower.contains('dokument')));
    if (!wantsFile) return false;

    // BUD-E already handled it with a tool call
    if (assistantResponse.contains('[[tool:')) return false;

    return true;
  }

  /// Process tool calls asynchronously without blocking the UI.
  void _processToolCallsAsync(Message assistantMsg, String systemPrompt) {
    debugLog(DebugSource.mainAgent,
        'Processing tool calls (${assistantMsg.content.length} chars)...');
    _processToolCalls(assistantMsg, systemPrompt).then((hasToolCall) {
      debugLog(DebugSource.mainAgent, 'Tool calls done: hasToolCall=$hasToolCall');
      if (!hasToolCall) {
        memory.addMessage(assistantMsg);
      }
      _finishExchange(hasToolCall
          ? _conversation.messages.last
          : assistantMsg);
    }).catchError((e, stack) {
      debugLog(DebugSource.mainAgent, 'Tool call processing CRASHED: $e\n$stack');
      memory.addMessage(assistantMsg);
      _finishExchange(assistantMsg);
    });
  }

  /// Check for tool calls, execute them, and do a follow-up LLM call.
  /// Returns true if a tool call was processed.
  Future<bool> _processToolCalls(
      Message assistantMsg, String systemPrompt) async {
    final memMatch = _memorySearchRegex.firstMatch(assistantMsg.content);
    final wikiMatch = _wikiRegex.firstMatch(assistantMsg.content);
    final saveMatch = _memorySaveRegex.firstMatch(assistantMsg.content);
    final agentMatch = _runAgentRegex.firstMatch(assistantMsg.content);
    final weatherMatch = _weatherRegex.firstMatch(assistantMsg.content);
    final newsMatch = _newsRegex.firstMatch(assistantMsg.content);
    final imageMatch = _imageGenRegex.firstMatch(assistantMsg.content);
    final musicMatch = _musicGenRegex.firstMatch(assistantMsg.content);
    final bildungsplanMatch = _bildungsplanRegex.firstMatch(assistantMsg.content);

    // memory_save is fire-and-forget (no follow-up needed)
    if (saveMatch != null) {
      final id = saveMatch.group(1)!;
      final content = saveMatch.group(2)!;
      debugLog(DebugSource.mainAgent, 'Tool: memory_save("$id")');
      await _executeMemorySave(id, content);
    }

    // generate_music: call music generation API
    if (musicMatch != null) {
      final prompt = musicMatch.group(1)!;
      final negPrompt = musicMatch.group(2) ?? '';
      debugLog(DebugSource.mainAgent, 'Tool: generate_music("$prompt")');
      await _executeMusicGeneration(prompt, negPrompt, assistantMsg);
      return true;
    }

    // generate_image: call image generation API
    if (imageMatch != null) {
      final prompt = imageMatch.group(1)!;
      final model = imageMatch.group(2) ?? '';
      var size = imageMatch.group(3) ?? '1024x1024';
      final aspect = imageMatch.group(4) ?? '';
      final refStr = imageMatch.group(5) ?? '';
      // Resolve aspect ratio to size
      if (aspect.isNotEmpty) {
        size = switch (aspect.toLowerCase()) {
          'square' || '1:1' => '1024x1024',
          'landscape' || '16:9' || 'quer' => '1792x1024',
          'portrait' || '9:16' || 'hoch' => '1024x1792',
          'photo' || '4:3' => '1365x1024',
          'wide' || '21:9' => '2048x1024',
          _ => size,
        };
      }
      debugLog(DebugSource.mainAgent, 'Tool: generate_image("$prompt", size=$size, ref=$refStr)');
      await _executeImageGeneration(prompt, model, size, refStr, assistantMsg, systemPrompt);
      return true;
    }

    // run_agent: spawn sub-agent in background
    if (agentMatch != null) {
      final instruction = agentMatch.group(1)!
          .replaceAll('\\"', '"').replaceAll('\\n', '\n');
      final filesStr = agentMatch.group(2) ?? '';
      debugLog(DebugSource.mainAgent, 'Tool: run_agent("${instruction.substring(0, instruction.length.clamp(0, 80))}...")');
      _spawnSubAgent(instruction, filesStr, assistantMsg);

      // Proactive health checks: verify agent is running at 2s, 5s, 10s
      for (final delay in [2, 5, 10]) {
        Future.delayed(Duration(seconds: delay), () {
          final taskId = assistantMsg.metadata['agentTaskId'] as String?;
          if (taskId == null) return;
          final task = _agentTasks[taskId];
          if (task == null) {
            debugLog(DebugSource.agentRegistry,
                'Agent task $taskId missing at ${delay}s check — restarting');
            _spawnSubAgent(instruction, filesStr, assistantMsg);
            return;
          }
          if (task.status == AgentTaskStatus.pending && delay >= 5) {
            debugLog(DebugSource.agentRegistry,
                'Agent still pending at ${delay}s — forcing status update');
            task.setRunning();
          }
          notifyListeners();
        });
      }
      return true;
    }

    if (memMatch == null && wikiMatch == null &&
        weatherMatch == null && newsMatch == null &&
        bildungsplanMatch == null) return saveMatch != null;

    String toolResultText = '';

    if (memMatch != null) {
      final query = memMatch.group(1)!;
      debugLog(DebugSource.mainAgent, 'Tool: memory_search("$query")');
      toolResultText += await _executeMemorySearch(query);
    }

    if (wikiMatch != null) {
      final query = wikiMatch.group(1)!;
      final depth = wikiMatch.group(2) ?? 'summary';
      debugLog(DebugSource.mainAgent, 'Tool: wikipedia("$query", $depth)');
      toolResultText += '\n${await _executeWikipedia(query, depth)}';
    }

    if (weatherMatch != null) {
      final location = weatherMatch.group(1)!;
      debugLog(DebugSource.mainAgent, 'Tool: weather("$location")');
      toolResultText += '\n${await web_tools.toolWeather(location)}';
    }

    if (newsMatch != null) {
      final topic = newsMatch.group(1);
      debugLog(DebugSource.mainAgent,
          'Tool: news(${topic ?? "aktuell"})');
      toolResultText +=
          '\n${await web_tools.toolTagesschauNews(topic: topic)}';
    }

    if (bildungsplanMatch != null) {
      final query = bildungsplanMatch.group(1)!;
      final fach = bildungsplanMatch.group(2);
      final schulform = bildungsplanMatch.group(3);
      debugLog(DebugSource.mainAgent,
          'Tool: bildungsplan_search("$query", fach=$fach, schulform=$schulform)');
      await bildungsplanSearch.buildIndex(); // ensure fresh
      final results = bildungsplanSearch.search(query,
          limit: 5, fach: fach, schulform: schulform);
      if (results.isEmpty) {
        toolResultText += '\nKeine Ergebnisse im Bildungsplan-Index gefunden fuer "$query".'
            '\nVerfuegbare Faecher: ${bildungsplanSearch.availableFaecher.join(", ")}'
            '\nVerfuegbare Schulformen: ${bildungsplanSearch.availableSchulformen.join(", ")}';
      } else {
        final buf = StringBuffer('\nBildungsplan-Suchergebnisse fuer "$query" (${results.length} Treffer):\n\n');
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          buf.writeln('TREFFER ${i + 1}: ${r.page.sourceRef}');
          buf.writeln('Relevanz: ${r.score.toStringAsFixed(2)}');
          buf.writeln('PDF-Link: ${r.page.pdfPageLink}');
          buf.writeln('Originalzitat: "${r.snippet}"');
          buf.writeln();
        }
        buf.writeln('ANWEISUNG (STRIKT EINHALTEN!):\n'
            '1. Fasse die Ergebnisse fuer den Nutzer zusammen.\n'
            '2. Nenne bei JEDEM Treffer: Fach, Schulform, Bundesland und Seitenzahl.\n'
            '3. Zitiere die relevantesten Passagen WOERTLICH in Anfuehrungszeichen.\n'
            '4. WICHTIG - Gib zu JEDEM Treffer den VOLLSTAENDIGEN klickbaren PDF-Link:\n'
            '   Schreibe den Link IMMER so: URL#page=X (der Nutzer kann ihn dann anklicken)\n'
            '   Beispiel: https://www.hamburg.de/.../informatik-data.pdf#page=27\n'
            '5. Liste ALLE gefundenen Seiten auf, nicht nur die beste!\n'
            '6. Der Nutzer MUSS die Links direkt anklicken koennen.');
        toolResultText += buf.toString();
      }
    }

    if (toolResultText.isEmpty) return true; // only save, no follow-up

    // Add the assistant's tool-call message to memory first
    memory.addMessage(assistantMsg);

    // Inject tool result — instruct LLM to use ONLY this data
    final toolResultMsg = Message.user(
      '[[tool_result]]\n${toolResultText.trim()}\n[[/tool_result]]\n\n'
      'Oben sind die Ergebnisse deiner Werkzeug-Abfrage. '
      'Antworte dem Nutzer NUR basierend auf diesen Daten. '
      'Erfinde NICHTS dazu.',
    );
    _conversation.addMessage(toolResultMsg);
    memory.addMessage(toolResultMsg);
    notifyListeners();

    debugLog(DebugSource.mainAgent,
        'Tool result injected (${toolResultText.length} chars), follow-up call...');

    // Follow-up LLM call
    final followUpMsg = Message.assistant('');
    _conversation.addMessage(followUpMsg);
    notifyListeners();

    await _streamResponse(
      assistantMsg: followUpMsg,
      systemPrompt: systemPrompt,
      streamTts: ttsEnabled,
    );

    memory.addMessage(followUpMsg);
    debugLog(DebugSource.mainAgent,
        'Follow-up response: ${followUpMsg.content.length} chars');

    // CRITICAL: Check follow-up for additional tool calls
    final followUpAgent = _runAgentRegex.firstMatch(followUpMsg.content);
    if (followUpAgent != null) {
      final instruction = followUpAgent.group(1)!;
      final filesStr = followUpAgent.group(2) ?? '';
      debugLog(DebugSource.mainAgent, 'Follow-up spawns agent: $instruction');
      _spawnSubAgent(instruction, filesStr, followUpMsg);
    }
    // Check for image/music in follow-up
    final followUpImage = _imageGenRegex.firstMatch(followUpMsg.content);
    if (followUpImage != null) {
      final prompt = followUpImage.group(1)!;
      final model = followUpImage.group(2) ?? '';
      var fSize = followUpImage.group(3) ?? '1024x1024';
      final fAspect = followUpImage.group(4) ?? '';
      final refStr = followUpImage.group(5) ?? '';
      if (fAspect.isNotEmpty) {
        fSize = switch (fAspect.toLowerCase()) {
          'square' || '1:1' => '1024x1024',
          'landscape' || '16:9' => '1792x1024',
          'portrait' || '9:16' => '1024x1792',
          'photo' || '4:3' => '1365x1024',
          _ => fSize,
        };
      }
      _executeImageGeneration(prompt, model, fSize, refStr, followUpMsg, systemPrompt);
    }
    final followUpMusic = _musicGenRegex.firstMatch(followUpMsg.content);
    if (followUpMusic != null) {
      _executeMusicGeneration(followUpMusic.group(1)!, followUpMusic.group(2) ?? '', followUpMsg);
    }

    return true;
  }

  /// Stream an LLM response into [assistantMsg] with retry logic.
  /// If [streamTts] is true, feeds chunks to TTS in real-time.
  Future<void> _streamResponse({
    required Message assistantMsg,
    required String systemPrompt,
    bool streamTts = false,
    int maxRetries = 2,
  }) async {
    final contextMessages = memory.contextWindow();

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        debugLog(DebugSource.mainAgent, 'Retry attempt $attempt...');
        assistantMsg.content = ''; // Reset for retry
        notifyListeners();
        await Future.delayed(Duration(seconds: attempt)); // Back-off
      }

      if (streamTts && ttsEnabled) {
        _ttsService.beginStream(universalApiKey);
      }

      try {
        int chunkCount = 0;
        final stream = _chatService.streamChat(
          universalApiKey: universalApiKey,
          messages: contextMessages,
          systemPrompt: systemPrompt,
        );

        await for (final chunk in stream) {
          assistantMsg.content += chunk;
          chunkCount++;
          notifyListeners();

          if (streamTts && ttsEnabled) {
            _ttsService.feedChunk(chunk);
          }
        }

        if (streamTts && ttsEnabled) {
          _ttsService.endStream();
        }

        debugLog(DebugSource.mainAgent,
            'Streamed: $chunkCount chunks, ${assistantMsg.content.length} chars');

        // Check for error responses
        if (assistantMsg.content.startsWith('[Error]') &&
            attempt < maxRetries) {
          debugLog(DebugSource.mainAgent,
              'Got error response, will retry');
          continue;
        }

        // Check for empty response
        if (assistantMsg.content.trim().isEmpty && attempt < maxRetries) {
          debugLog(DebugSource.mainAgent,
              'Empty response, will retry');
          continue;
        }

        return; // Success
      } catch (e) {
        debugLog(DebugSource.mainAgent, 'Stream error (attempt $attempt): $e');
        if (attempt >= maxRetries) {
          // Final failure — user-friendly message
          final lang = storage.defaultLanguage;
          final isDE = lang.toLowerCase().startsWith('deutsch');
          assistantMsg.content = isDE
              ? 'Entschuldigung, ich konnte gerade keine Verbindung herstellen. '
                'Bitte versuche es in einem Moment noch einmal.'
              : 'Sorry, I could not connect right now. '
                'Please try again in a moment.';
        }
      }
    }
  }

  /// Generate music via the middleware API.
  Future<void> _executeMusicGeneration(
      String prompt, String negativePrompt, Message triggerMsg) async {
    final url = middlewareUrl(universalApiKey, '/v1/audio/generations');
    if (url == null) return;

    debugLog(DebugSource.mainAgent, 'Music gen: "$prompt"');
    memory.addMessage(triggerMsg);

    // Show loading state immediately
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $universalApiKey',
        },
        body: jsonEncode({
          'model': 'lyria-3-pro-preview',
          'prompt': prompt,
          if (negativePrompt.isNotEmpty) 'negative_prompt': negativePrompt,
          'n': 1,
          'response_format': 'b64_json',
        }),
      ).timeout(const Duration(seconds: 300));

      if (response.statusCode != 200) {
        debugLog(DebugSource.mainAgent,
            'Music gen error: ${response.statusCode} ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');

        // Parse error details for user-friendly message
        String userMessage;
        try {
          final errJson = jsonDecode(response.body) as Map<String, dynamic>;
          final detail = errJson['detail'];
          final errMsg = detail is Map ? (detail['message'] ?? detail['error'] ?? '') : '$detail';
          final errStr = '$errMsg';

          if (errStr.contains('Prohibited Use') || errStr.contains('sensitive words') ||
              response.statusCode == 400) {
            userMessage = S.musicPolicyError;
          } else {
            userMessage = 'Musikgenerierung fehlgeschlagen (${response.statusCode}): '
                '${errStr.length > 200 ? '${errStr.substring(0, 200)}...' : errStr}';
          }
        } catch (_) {
          userMessage = 'Musikgenerierung fehlgeschlagen (${response.statusCode}). '
              'Bitte versuche es erneut.';
        }

        final errorMsg = Message.assistant(userMessage);
        _conversation.addMessage(errorMsg);
        _isLoading = false;
        notifyListeners();
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (json['data'] as List?)?.firstOrNull as Map<String, dynamic>?;
      if (data == null) return;

      final b64 = data['b64_json'] as String?;
      if (b64 == null || b64.isEmpty) {
        final errorMsg = Message.assistant('Keine Musik generiert.');
        _conversation.addMessage(errorMsg);
        notifyListeners();
        return;
      }

      // Save audio to workspace — detect format from response
      final mime = data['mime_type'] as String? ?? 'audio/wav';
      final ext = mime.contains('mpeg') || mime.contains('mp3') ? 'mp3' : 'wav';
      final fileName = 'music_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = p.join(workspacePath, fileName);
      final wsDir = Directory(workspacePath);
      if (!await wsDir.exists()) await wsDir.create(recursive: true);
      await File(filePath).writeAsBytes(base64Decode(b64));

      // Extract lyrics if present (Lyria 3 Pro)
      final lyrics = json['lyrics'] as String? ?? '';
      final duration = data['duration_seconds'];

      debugLog(DebugSource.mainAgent,
          'Music saved: $filePath (${b64.length ~/ 1024} KB, ${duration ?? "?"}s)');

      final lyricsInfo = lyrics.isNotEmpty ? '\n\nText:\n$lyrics' : '';
      final durationInfo = duration != null ? ' (${duration}s)' : '';
      final musicMsg = Message.assistant(
        'Hier ist die generierte Musik$durationInfo:\n\n'
        '*$prompt*$lyricsInfo\n\n'
        'Gespeichert unter: $filePath\n'
        'Klicke auf die Datei um sie abzuspielen.',
        files: [filePath],
      );
      _conversation.addMessage(musicMsg);
      memory.addMessage(musicMsg);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugLog(DebugSource.mainAgent, 'Music gen error: $e');
      final errorMsg = Message.assistant('Musikgenerierung fehlgeschlagen: $e');
      _conversation.addMessage(errorMsg);
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Generate an image via the middleware API and display inline.
  Future<void> _executeImageGeneration(
      String prompt, String model, String size, String refStr,
      Message triggerMsg, String systemPrompt) async {
    final url = middlewareUrl(universalApiKey, '/v1/images/generations');
    if (url == null) return;

    debugLog(DebugSource.mainAgent,
        'Image gen: "$prompt" model=$model size=$size ref=$refStr');

    memory.addMessage(triggerMsg);

    // Show loading state
    _isLoading = true;
    notifyListeners();

    try {
      final body = <String, dynamic>{
        'prompt': prompt,
        'n': 1,
        'size': size.isEmpty ? '1024x1024' : size,
        'response_format': 'b64_json',
      };
      if (model.isNotEmpty) body['model'] = model;

      // Only send reference images if explicitly specified via ref= parameter
      if (refStr.isNotEmpty) {
        final refIds = refStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
        final refImages = <String>[];
        for (final refId in refIds) {
          final img = imageRegistry.findById(refId);
          if (img != null) {
            try {
              final bytes = await File(img.filePath).readAsBytes();
              final b64 = base64Encode(bytes);
              final ext = p.extension(img.filePath).toLowerCase();
              final mime = ext == '.png' ? 'image/png' : 'image/jpeg';
              refImages.add('data:$mime;base64,$b64');
              debugLog(DebugSource.mainAgent, 'Ref image: ${img.id} -> ${img.filePath}');
            } catch (_) {}
          } else {
            debugLog(DebugSource.mainAgent, 'Ref image not found: $refId');
          }
        }
        if (refImages.isNotEmpty) {
          body['input_images'] = refImages;
        }
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $universalApiKey',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        debugLog(DebugSource.mainAgent,
            'Image gen error: ${response.statusCode}');
        final errorMsg = Message.assistant(
            'Bildgenerierung fehlgeschlagen (${response.statusCode}). '
            'Bitte versuche es erneut.');
        _conversation.addMessage(errorMsg);
        memory.addMessage(errorMsg);
        notifyListeners();
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (json['data'] as List?)?.firstOrNull as Map<String, dynamic>?;
      if (data == null) return;

      final b64 = data['b64_json'] as String?;
      final mime = data['mime_type'] as String? ?? 'image/png';
      final revisedPrompt = data['revised_prompt'] as String?;

      if (b64 == null || b64.isEmpty) {
        final errorMsg = Message.assistant('Kein Bild generiert. Bitte versuche einen anderen Prompt.');
        _conversation.addMessage(errorMsg);
        memory.addMessage(errorMsg);
        notifyListeners();
        return;
      }

      // Save image to workspace
      final ext = mime.contains('jpeg') ? 'jpg' : 'png';
      final fileName = 'generated_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = p.join(workspacePath, fileName);
      final wsDir = Directory(workspacePath);
      if (!await wsDir.exists()) await wsDir.create(recursive: true);
      await File(filePath).writeAsBytes(base64Decode(b64));

      // Register in image registry
      final imageId = imageRegistry.register(filePath,
          source: 'generated', prompt: prompt);

      debugLog(DebugSource.mainAgent,
          'Image saved: $imageId -> $filePath (${b64.length ~/ 1024} KB)');

      // Create message with inline image and ID
      final imageMsg = Message.assistant(
        'Hier ist das generierte Bild [$imageId]:'
        '${revisedPrompt != null ? '\n\n*$revisedPrompt*' : ''}\n\n'
        'Gespeichert unter: $filePath\n'
        'Bild-ID: $imageId (verwende diese ID als Referenz fuer Bearbeitungen)',
        files: [filePath],
      );
      imageMsg.metadata['inlineImageB64'] = b64;
      imageMsg.metadata['inlineImageMime'] = mime;
      imageMsg.metadata['imagePrompt'] = prompt;
      imageMsg.metadata['imageId'] = imageId;

      _conversation.addMessage(imageMsg);
      memory.addMessage(imageMsg);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugLog(DebugSource.mainAgent, 'Image gen error: $e');
      final errorMsg = Message.assistant('Bildgenerierung fehlgeschlagen: $e');
      _conversation.addMessage(errorMsg);
      memory.addMessage(errorMsg);
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Post-exchange: save + background memory update.
  void _finishExchange(Message assistantMsg) {
    // Parallel saves (both independent)
    Future.wait([
      storage.saveConversation(_conversation).catchError((_) {}),
      memory.saveWorkingState(activeConversationId: _conversation.id).catchError((_) {}),
    ]);

    // Background memory updater — invalidate caches when done
    _memoryUpdater.updateAfterExchange(
      universalApiKey: universalApiKey,
      recentMessages: List.of(memory.allMessages),
      conversationId: _conversation.id,
    ).then((_) {
      // Invalidate caches so next message picks up new data
      contextBuilder.invalidateCache();
      memorySearch.markDirty(); // lazy rebuild on next search
    }).catchError((_) {});
  }

  Future<String> _executeMemorySearch(String query) async {
    try {
      await memorySearch.ensureFresh();
      final results = memorySearch.search(query, limit: 5);
      if (results.isEmpty) return 'Memory search: no results for "$query".';

      final buf = StringBuffer('Memory search results for "$query":\n');
      for (final r in results) {
        final title = r.doc.data['title'] ?? r.doc.path.split('/').last;
        final summary = r.doc.data['summary'] as String? ??
            r.doc.text.substring(0, r.doc.text.length.clamp(0, 200));
        buf.writeln('- $title: $summary');
      }
      return buf.toString();
    } catch (e) {
      return 'Memory search error: $e';
    }
  }

  Future<String> _executeWikipedia(String query, String depth) async {
    try {
      // Use language from settings
      final lang = storage.defaultLanguage.toLowerCase().startsWith('deutsch')
          ? 'de' : storage.defaultLanguage.toLowerCase().startsWith('en')
          ? 'en' : 'de';

      final result = await _wikiAgent.search(query, lang: lang, depth: depth);
      if (result == null) return 'Wikipedia: no results for "$query".';

      final text = depth == 'summary'
          ? result.summary
          : (result.fullExtract ?? result.summary);

      // Cap at 10k chars
      final capped = text.length > 10000 ? '${text.substring(0, 10000)}...' : text;

      return 'Wikipedia: ${result.title}\n'
          'URL: ${result.url}\n'
          '---\n$capped';
    } catch (e) {
      return 'Wikipedia error: $e';
    }
  }

  /// Spawn a background sub-agent to handle a complex task.
  void _spawnSubAgent(
      String instruction, String filesStr, Message triggerMsg) {
    final taskId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

    // Resolve file paths
    final fileNames =
        filesStr.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty);
    final filePaths = <String>[
      // Files from pending upload
      ...?_pendingFiles,
      // Files mentioned in the tool call
      ...fileNames.map((f) => p.join(workspacePath, f)),
    ];

    // Presentations need more steps for image generation per slide
    final instrLower = instruction.toLowerCase();
    final isPresentation = instrLower.contains('praesentation') ||
        instrLower.contains('präsentation') || instrLower.contains('powerpoint') ||
        instrLower.contains('pptx') || instrLower.contains('folien');

    final task = AgentTask(
      id: taskId,
      instruction: instruction,
      inputFiles: filePaths,
      maxSteps: isPresentation ? 20 : 25,
    );

    _agentTasks[taskId] = task;

    // Store task ID in the trigger message metadata
    triggerMsg.metadata['agentTaskId'] = taskId;

    // Listen for status changes to update UI
    task.addListener(notifyListeners);

    // Notify UI immediately so the agent widget appears
    notifyListeners();

    // Give UI time to render, then verify task is visible
    Future.delayed(const Duration(milliseconds: 200), notifyListeners);

    debugLog(DebugSource.agentRegistry,
        'Agent task created: $taskId, instruction: ${instruction.substring(0, (instruction.length).clamp(0, 80))}...');

    // Run in background
    final runner = SubAgentRunner(
      universalApiKey: universalApiKey,
      workspacePath: workspacePath,
      imageRegistry: imageRegistry,
    );

    runner.run(task).then((_) async {
      debugLog(DebugSource.agentRegistry,
          'Agent finished: status=${task.status.name}, '
          'files=${task.generatedFiles.length}, result=${task.result.length} chars');

      if (task.status == AgentTaskStatus.completed) {
        // Build file list with ABSOLUTE paths
        final fileBuf = StringBuffer();
        if (task.generatedFiles.isNotEmpty) {
          fileBuf.writeln('\n\nErstellte Dateien:');
          for (final f in task.generatedFiles) {
            final exists = await File(f).exists();
            final size = exists ? await File(f).length() : 0;
            fileBuf.writeln('- $f (${exists ? "${size} bytes" : "FEHLT"})');
          }
        }

        // Truncate result to prevent context overflow
        var result = task.result;
        if (result.length > 3000) {
          result = '${result.substring(0, 3000)}\n...(truncated)';
        }

        final resultMsg = Message.user(
          '[[tool_result]]\nAgent fertig.\n$result${fileBuf.toString()}\n[[/tool_result]]\n\n'
          'Fasse kurz zusammen und nenne die Dateipfade.',
        );
        _conversation.addMessage(resultMsg);
        memory.addMessage(resultMsg);
        notifyListeners();

        // BUD-E presents the result (with timeout to prevent hang)
        try {
          await _presentAgentResult().timeout(const Duration(seconds: 60));
        } catch (e) {
          debugLog(DebugSource.agentRegistry, 'Present result failed: $e');
        }
        // Ensure generated files appear as clickable chips on the result message
        if (task.generatedFiles.isNotEmpty) {
          final uniqueFiles = task.generatedFiles.toSet().toList();
          final docFiles = uniqueFiles.where((f) =>
              f.endsWith('.docx') || f.endsWith('.pdf') || f.endsWith('.pptx') ||
              f.endsWith('.html') || f.endsWith('.rtf') || f.endsWith('.md')).toList();
          if (docFiles.isNotEmpty) {
            // Find the last non-empty assistant message and attach files
            for (final msg in _conversation.messages.reversed) {
              if (msg.role == MessageRole.assistant && msg.content.isNotEmpty) {
                // Only add files not already attached
                for (final f in docFiles) {
                  if (!msg.attachedFiles.contains(f)) msg.attachedFiles.add(f);
                }
                break;
              }
            }
            notifyListeners();
          }
        }

        // Remove empty assistant messages (failed LLM follow-ups)
        _conversation.messages.removeWhere((m) =>
            m.role == MessageRole.assistant && m.content.trim().isEmpty &&
            m.attachedFiles.isEmpty);
        notifyListeners();

        // Save conversation with attached files (persistence!)
        storage.saveConversation(_conversation).catchError((_) {});
      } else if (task.status == AgentTaskStatus.error) {
        debugLog(DebugSource.agentRegistry, 'Agent error: ${task.error}');
        final errorMsg = Message.assistant(
          'Der Agent hatte einen Fehler: ${task.error}\n\n'
          'Soll ich es nochmal versuchen?',
        );
        _conversation.addMessage(errorMsg);
        memory.addMessage(errorMsg);
        notifyListeners();
      }
      notifyListeners();
    }).catchError((e) {
      debugLog(DebugSource.agentRegistry, 'Agent runner crashed: $e');
      task.fail('Agent abgestuerzt: $e');
      final errorMsg = Message.assistant('Agent-Fehler: $e');
      _conversation.addMessage(errorMsg);
      notifyListeners();
    });
  }

  /// Let BUD-E present a sub-agent's result to the user.
  Future<void> _presentAgentResult() async {
    try {
      final builtCtx = await contextBuilder
          .buildContext(
            episodicBudget: storage.episodicTokenBudget,
            totalBudget: storage.totalContextBudget,
            currentConversationText: '',
          )
          .timeout(const Duration(seconds: 5))
          .catchError((_) => BuiltContext(
                episodicContext: '', episodicTokens: 0,
                activatedMemories: [], semanticContext: '',
                semanticTokens: 0, totalTokens: 0,
              ));

      final systemPrompt = _buildSystemPrompt(builtCtx);
      final followUp = Message.assistant('');
      _conversation.addMessage(followUp);
      notifyListeners();

      await _streamResponse(
        assistantMsg: followUp,
        systemPrompt: systemPrompt,
        streamTts: ttsEnabled,
      );
      memory.addMessage(followUp);
      notifyListeners();
    } catch (e) {
      debugLog(DebugSource.agentRegistry, 'Error presenting result: $e');
    }
  }

  /// Let BUD-E react to a sub-agent error.
  Future<void> _handleAgentError(Message errorMsg) async {
    try {
      final builtCtx = await contextBuilder
          .buildContext(
            episodicBudget: storage.episodicTokenBudget,
            totalBudget: storage.totalContextBudget,
            currentConversationText: '',
          )
          .timeout(const Duration(seconds: 5))
          .catchError((_) => BuiltContext(
                episodicContext: '',
                episodicTokens: 0,
                activatedMemories: [],
                semanticContext: '',
                semanticTokens: 0,
                totalTokens: 0,
              ));

      final systemPrompt = _buildSystemPrompt(builtCtx);
      final followUp = Message.assistant('');
      _conversation.addMessage(followUp);
      notifyListeners();

      await _streamResponse(
        assistantMsg: followUp,
        systemPrompt: systemPrompt,
        streamTts: ttsEnabled,
      );
      memory.addMessage(followUp);
      notifyListeners();
    } catch (_) {}
  }

  /// Directly save/update a fact in semantic memory.
  Future<void> _executeMemorySave(String id, String content) async {
    try {
      final existing = await storage.loadSemanticMemory(id);
      final now = DateTime.now().toIso8601String();

      final data = <String, dynamic>{
        ...?existing,
        'id': id,
        'title': existing?['title'] ?? id.replaceAll('_', ' '),
        'content': content,
        'summary': content.length > 200 ? '${content.substring(0, 200)}...' : content,
        'triggerWords': <String>{
          ...(existing?['triggerWords'] as List?)?.map((e) => e.toString()) ?? [],
          ...id.replaceAll('_', ' ').toLowerCase().split(' '),
        }.toList(),
        'relatedConcepts': existing?['relatedConcepts'] ?? [],
        'category': existing?['category'] ?? 'personal',
      };

      // Keep revision history
      final oldContent = existing?['content'] as String?;
      if (oldContent != null && oldContent != content) {
        final revisions = List<Map<String, dynamic>>.from(
            existing?['revisions'] as List? ?? []);
        revisions.add({'content': oldContent, 'replacedAt': now});
        if (revisions.length > 5) revisions.removeRange(0, revisions.length - 5);
        data['revisions'] = revisions;
      }

      await storage.saveSemanticMemory(id, data);
      contextBuilder.invalidateCache();
      memorySearch.markDirty();
      debugLog(DebugSource.updater, 'Direct save: $id');
    } catch (e) {
      debugLog(DebugSource.updater, 'Save error: $e');
    }
  }

  String _buildSystemPrompt(BuiltContext builtCtx) {
    final basePrompt = storage.systemPrompt;
    final agentDesc = agents.agentDescriptions();
    final lang = storage.defaultLanguage;

    final parts = <String>[
      basePrompt,
      'Deine Standard-Sprache ist $lang.\n'
      'WICHTIG: Antworte IMMER in der Sprache, in der der Nutzer zuletzt mit dir gesprochen hat. '
      'Wenn der Nutzer auf Englisch schreibt, antworte auf Englisch. '
      'Wenn der Nutzer auf Deutsch schreibt, antworte auf Deutsch. '
      'Wechsle die Sprache nur wenn der Nutzer es explizit verlangt oder selbst die Sprache wechselt.\n'
      'Passe die Laenge deiner Antwort an die Frage an: kurze Fragen = kurze Antworten, '
      'komplexe Fragen = ausfuehrliche, detaillierte Antworten. '
      'Scheue dich nicht vor langen Erklaerungen wenn das Thema es erfordert.',
    ];
    if (agentDesc.isNotEmpty) parts.add(agentDesc);
    parts.add(_toolDescription());

    if (builtCtx.episodicContext.isNotEmpty) {
      parts.add('=== Erinnerungen (zeitlich geordnet) ===\n${builtCtx.episodicContext}');
    }
    if (builtCtx.semanticContext.isNotEmpty) {
      parts.add('=== Aktiviertes Wissen ===\n${builtCtx.semanticContext}');
    }

    // Add image registry context
    final imgCtx = imageRegistry.buildContextSummary();
    if (imgCtx.isNotEmpty) parts.add(imgCtx);

    // Add active agent status
    if (_agentTasks.isNotEmpty) {
      final agentBuf = StringBuffer('=== Agent-Status ===\n');
      for (final t in _agentTasks.values) {
        agentBuf.write('${t.id}: ${t.status.name}');
        if (t.steps.isNotEmpty) agentBuf.write(' (${t.steps.last})');
        if (t.generatedFiles.isNotEmpty) {
          agentBuf.write(' Dateien: ${t.generatedFiles.map((f) => p.basename(f)).join(", ")}');
        }
        agentBuf.writeln();
      }
      parts.add(agentBuf.toString());
    }

    return parts.join('\n\n');
  }

  String _toolDescription() {
    return '''Du hast Zugang zu folgenden Werkzeugen:

1. Gedächtnis-Suche — wenn der Nutzer nach etwas aus der Vergangenheit fragt:
[[tool:memory_search query="Suchbegriffe"]]

2. Wikipedia — wenn du Fakten nachschlagen musst:
[[tool:wikipedia query="Suchbegriff" depth="summary"]]

3. Gedächtnis speichern — wenn der Nutzer dich bittet, etwas zu merken oder zu aktualisieren:
[[tool:memory_save id="snake_case_id" content="Der aktuelle Fakt oder die Information"]]

4. Wetter — aktuelles Wetter und Vorhersage abrufen:
[[tool:weather location="Hamburg"]]

5. Nachrichten — aktuelle Nachrichten von tagesschau.de:
[[tool:news topic="Thema"]]
Ohne topic= für allgemeine aktuelle Nachrichten: [[tool:news]]

6. Bild generieren oder bearbeiten:
[[tool:generate_image prompt="Beschreibung auf Englisch" model="" size="1024x1024" aspect="" ref=""]]
- Neues Bild: ref="" weglassen → generiert komplett neues Bild
- Bild bearbeiten: ref="IMG_abc123" → nutzt dieses Bild als Referenz
- Mehrere Referenzen: ref="IMG_abc123,IMG_def456"
- Modelle: leer lassen fuer Standard, oder: imagen-4.0-generate-001, flux-2-pro
- Formate (aspect): square (1:1), landscape (16:9), portrait (9:16), photo (4:3)
- Groessen: 1024x1024, 1792x1024 (quer), 1024x1792 (hoch) — oder aspect benutzen
Jedes Bild hat eine eindeutige ID (z.B. IMG_a7x3kp). Nenne die ID wenn der User ein bestehendes Bild bearbeiten will.

7. Musik generieren — Lieder MIT Gesang und instrumentale Musik (Lyria 3 Pro):
[[tool:generate_music prompt="Detaillierte Beschreibung auf Englisch" negative_prompt="optional"]]
WICHTIG: Du nutzt Lyria 3 Pro und KANNST ganze Lieder MIT Gesang und Lyrics generieren (bis 3 Minuten)!
Behaupte NIEMALS, du koenntest nur instrumentale Musik machen!

WORKFLOW fuer Musikgenerierung (IMMER einhalten!):
1. SCHRITT 1 - ENTWURF: Erstelle zuerst einen detaillierten Prompt (Genre, Stimmung, Instrumente, Tempo)
   UND schreibe Lyrics/Songtext (mit [Verse], [Chorus], [Bridge] Tags) falls Gesang gewuenscht.
   Zeige beides dem Nutzer und frage: "Soll ich den Song so generieren?"
2. SCHRITT 2 - GENERIERUNG: Erst NACH Bestaetigung des Nutzers: Rufe generate_music auf.
   Baue die Lyrics direkt in den Prompt ein: "Lyrics: [Verse] text... [Chorus] text..."

Prompt-Tipps:
- Schreibe den Prompt auf Englisch (bessere Ergebnisse)
- Beschreibe Genre, Stimmung, Instrumente, Tempo, Gesangsstil
- Fuer Lyrics: Verwende [Verse], [Chorus], [Bridge], [Outro] Tags
- negative_prompt nur wenn der Nutzer explizit etwas ausschliessen will

8. Bildungsplan-Suche — durchsucht Hamburger Bildungsplaene:
[[tool:bildungsplan_search query="Suchbegriffe" fach="Informatik" schulform="Gymnasium"]]
Durchsucht transkribierte Bildungsplaene mit BM25-Ranking.
Optionale Filter: fach (z.B. Informatik, Mathematik), schulform (z.B. Gymnasium, Stadtteilschule).
WICHTIG - Bei JEDER Antwort auf Bildungsplan-Fragen MUSST du:
1. Zu JEDEM Treffer den VOLLSTAENDIGEN PDF-Link mit Seitenzahl angeben: URL#page=X
2. Die Links muessen IMMER als vollstaendige URL im Text stehen (klickbar!)
3. Relevante Passagen WOERTLICH zitieren
4. ALLE gefundenen Seiten auflisten, nicht nur die beste
Beispiel-Antwort: "Auf Seite 27 steht: '...' (https://www.hamburg.de/.../informatik-data.pdf#page=27)"

9. Python-Code ausfuehren (ueber den Unteragenten):
Der Unteragent kann Python-Code ausfuehren mit [[tool:run_python code="..."]].
Nutze das wenn der User Code testen, rechnen oder programmieren will.

10. Arbeitsblatt erstellen — fuer Lehrer:
Wenn der Nutzer ein Arbeitsblatt, Uebungsblatt oder Aufgabenblatt fuer den Unterricht will:
Erstelle es mit run_agent als .docx UND .pdf. Enthalte:
- Schueler-Name/Datum-Felder oben
- Klare Aufgabenstellungen mit Nummerierung
- Lueckentexte, Rechenaufgaben, Multiple-Choice oder offene Fragen
- Platz fuer Antworten (Linien oder Kaestchen)
- Erwartungshorizont/Loesungen auf separater Seite
Der Agent prueft das Layout selbst und korrigiert Fehler.

11. Unteragent — fuer komplexe mehrstufige Aufgaben:
[[tool:run_agent instruction="Aufgabenbeschreibung"]]
Der Agent kann: Web-Suche (Brave Search), Webseiten scrapen, Wikipedia, Dateien lesen/schreiben (DOCX/HTML/PDF/PPTX), Bilder generieren und einbetten.

WANN run_agent BENUTZEN:
- Dateien erstellen (Word, HTML, PDF, PowerPoint)
- Praesentationen erstellen (PPTX mit generierten Bildern pro Folie)
- Recherche mit mehreren Quellen (Agent sucht, scrapt, fasst zusammen)
- Klassenarbeiten korrigieren
- Dateien analysieren oder umformatieren

RECHERCHE-AUFGABEN:
Wenn der Nutzer nach einer Person, Firma, Thema, Ort etc. fragt und du es nicht sicher weisst:
1. Benutze ZUERST [[tool:wikipedia query="..." depth="full"]] fuer einen Ueberblick
2. Wenn Wikipedia nichts findet oder der Nutzer mehr will: Starte einen Agent der mit web_search bei Brave sucht, Webseiten scrapt und ein Referat erstellt.
Der Agent soll IMMER Quellenangaben machen (URLs).

REGELN:
- Du MUSST [[tool:weather ...]] benutzen wenn nach Wetter gefragt wird.
- Du MUSST [[tool:news ...]] benutzen wenn nach Nachrichten gefragt wird.
- Du MUSST [[tool:generate_music ...]] benutzen wenn Musik gewuenscht wird.
- Du MUSST [[tool:run_agent ...]] benutzen wenn Dateien erstellt werden sollen.
- Du MUSST [[tool:bildungsplan_search ...]] benutzen wenn nach Lehrplaenen, Bildungsplaenen, Curricula, Unterrichtsinhalten oder Schulfaechern gefragt wird.
  AUCH WENN du glaubst die Antwort zu kennen: Benutze TROTZDEM den Tool-Call!
  Der Nutzer erwartet exakte Seitenzahlen und klickbare PDF-Links.
  Ohne Tool-Call hast du KEINE zuverlaessigen Seitenangaben!
- Benutze [[tool:wikipedia ...]] UND dann ggf. run_agent fuer tiefere Recherche.
- Text in [[...]] wird NICHT vorgelesen.
- Wenn du ein Tool benutzt, schreibe NUR den Tool-Call.''';
  }

  void cancelStream() {
    _streamSub?.cancel();
    _streamSub = null;
    _isLoading = false;
    notifyListeners();
  }

  // --- ASR -------------------------------------------------------------------

  /// Last transcription result — the UI reads this to fill the text field.
  String? lastTranscription;

  Future<void> startRecording() async {
    final ok = await _asrService.startRecording();
    if (ok) {
      _isRecording = true;
      notifyListeners();
    }
  }

  /// Stop recording, transcribe, and either auto-send or put text in field.
  Future<void> stopRecordingAndTranscribe() async {
    _isRecording = false;
    notifyListeners();

    final text = await _asrService.stopAndTranscribe(universalApiKey);
    if (text == null || text.trim().isEmpty) return;

    // Always route through the widget so attached files are included.
    // The widget checks asrAutoSend and sends with files if present.
    lastTranscription = text;
    notifyListeners();
  }

  Future<void> stopTts() async {
    await _ttsService.stop();
    notifyListeners();
  }

  // --- Conversation management -----------------------------------------------

  /// Regenerate an assistant message at the given index.
  /// Creates a new branch and generates a fresh response.
  Future<void> regenerateMessage(int index) async {
    if (index < 0 || index >= _conversation.messages.length) return;
    final msg = _conversation.messages[index];
    if (msg.role != MessageRole.assistant) return;
    if (_isLoading) return;

    debugLog(DebugSource.mainAgent, 'Regenerating message at index $index');

    // Prepare regeneration: truncate active path at this message
    _conversation.prepareRegenerate(index);

    // The last message in the path should now be the user message
    final userMsg = _conversation.messages.isNotEmpty
        ? _conversation.messages.last : null;
    if (userMsg == null || userMsg.role != MessageRole.user) return;

    // Generate a new assistant response directly (without re-adding user msg)
    _isLoading = true;
    notifyListeners();

    try {
      BuiltContext builtCtx;
      try {
        final currentConvoText = memory.allMessages
            .map((m) => '${m.role.name}: ${m.content}')
            .join('\n');
        builtCtx = await contextBuilder.buildContext(
          episodicBudget: storage.episodicTokenBudget,
          totalBudget: storage.totalContextBudget,
          currentConversationText: currentConvoText,
        ).timeout(const Duration(seconds: 10));
        lastBuiltContext = builtCtx;
      } catch (_) {
        builtCtx = BuiltContext(
          episodicContext: '', episodicTokens: 0, activatedMemories: [],
          semanticContext: '', semanticTokens: 0, totalTokens: 0,
        );
      }

      final fullSystemPrompt = _buildSystemPrompt(builtCtx);
      final assistantMsg = Message.assistant('');
      _conversation.addMessage(assistantMsg);
      notifyListeners();

      await _streamResponse(
        assistantMsg: assistantMsg,
        systemPrompt: fullSystemPrompt,
        streamTts: true,
      );

      _isLoading = false;
      _conversation.updatedAt = DateTime.now();
      notifyListeners();

      _processToolCallsAsync(assistantMsg, fullSystemPrompt);
      _finishExchange(assistantMsg);
    } catch (e) {
      debugLog(DebugSource.mainAgent, 'Regeneration error: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Switch to a sibling branch at the given message.
  /// [delta] is -1 for previous, +1 for next.
  void switchBranch(String messageId, int delta) {
    if (_conversation.switchBranch(messageId, delta)) {
      debugLog(DebugSource.mainAgent, 'Switched branch for $messageId (delta=$delta)');
      notifyListeners();
      storage.saveConversation(_conversation).catchError((_) {});
    }
  }

  /// Get branch info for a message: (index, total) or null.
  ({int index, int total})? getBranchInfo(String messageId) =>
      _conversation.getBranchInfo(messageId);

  Future<void> clearConversation() async {
    try {
      if (_conversation.messages.isNotEmpty) {
        await memory.saveSessionSummary(
          conversationId: _conversation.id,
          title: _conversation.title,
        );
        await storage.saveConversation(_conversation);
      }
    } catch (_) {}

    _conversation = Conversation(
        id: DateTime.now().millisecondsSinceEpoch.toRadixString(36));
    memory.clear();
    imageRegistry.clear();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadConversation(String id) async {
    try {
      final conv = await storage.loadConversation(id);
      if (conv == null) return;
      _conversation = conv;
      memory.clear();
      for (final m in conv.messages) {
        memory.addMessage(m);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listConversations() async {
    try {
      return await storage.listConversations();
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _asrService.dispose();
    _streamSub?.cancel();
    super.dispose();
  }
}
