/// Sub-agent runner — text-based tool calling (works with any LLM).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../config/api_config.dart';
import '../models/agent_task.dart';
import '../services/debug_log.dart';
import 'tools/file_tools.dart';
import 'tools/web_tools.dart';
import 'tools/document_tools.dart';
import 'tools/pdf_tools.dart';
import 'tools/rtf_tools.dart';
import 'tools/docx_tools.dart';
import '../services/image_registry.dart';

/// Regex to parse tool calls from LLM text output.
/// Matches both inline args and block content format.
/// Supports escaped quotes (\") inside argument values.
final _toolCallRegex = RegExp(
    r'\[\[tool:(\w+)\s+((?:[a-z_]+="(?:[^"\\]|\\.)*"\s*)*)\]\]');

/// Regex for block content: [[tool:write_file path="x"]] followed by <<<CONTENT...CONTENT>>>
final _blockContentRegex = RegExp(
    r'\[\[tool:write_file\s+path="([^"]+)"\]\]\s*<<<CONTENT\n([\s\S]*?)\nCONTENT>>>',
    multiLine: true);

/// Parses key="value" pairs from a tool call string.
/// Handles escaped quotes (\") inside values.
Map<String, String> _parseToolArgs(String argsStr) {
  final map = <String, String>{};
  for (final m in RegExp(r'(\w+)="((?:[^"\\]|\\.)*)"').allMatches(argsStr)) {
    map[m.group(1)!] = m.group(2)!.replaceAll('\\"', '"').replaceAll('\\n', '\n');
  }
  return map;
}

class SubAgentRunner {
  final String universalApiKey;
  final String workspacePath;
  final ImageRegistry? imageRegistry;

  SubAgentRunner({
    required this.universalApiKey,
    required this.workspacePath,
    this.imageRegistry,
  });

  /// Track image generation count per run to prevent excessive retries.
  int _imageGenCount = 0;
  static const _maxImageGens = 10;

  Future<void> run(AgentTask task) async {
    _imageGenCount = 0;
    task.setRunning();
    debugLog(DebugSource.agentRegistry, 'Sub-agent started: ${task.instruction}');

    final url = middlewareUrl(universalApiKey, '/v1/chat/completions');
    if (url == null) {
      task.fail('Cannot decode middleware URL');
      return;
    }

    final wsDir = Directory(workspacePath);
    if (!await wsDir.exists()) await wsDir.create(recursive: true);

    var qcRetries = 0; // Limit QC feedback loops
    var fileRetries = 0; // Limit "no files" retries

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(task)},
      {'role': 'user', 'content': _userPrompt(task)},
    ];

    try {
      for (var step = 0; step < task.maxSteps; step++) {
        debugLog(DebugSource.agentRegistry, 'Sub-agent step ${step + 1}/${task.maxSteps}');
        final stepLabel = step == 0 ? 'Analyzing task...'
            : task.generatedFiles.isEmpty ? 'Working... (${step + 1}/${task.maxSteps})'
            : 'Finalizing... (${step + 1}/${task.maxSteps})';
        task.addStep(stepLabel);

        String? content;
        try {
          content = await _callLlm(url, messages)
              .timeout(const Duration(seconds: 200));
        } catch (e) {
          debugLog(DebugSource.agentRegistry, 'Step ${step + 1} timeout/error: $e');
          if (step > 0 && task.generatedFiles.isNotEmpty) {
            // Had some progress — complete with what we have
            task.complete('Agent wurde nach ${step + 1} Schritten beendet (Timeout). '
                'Erstellte Dateien: ${task.generatedFiles.map((f) => p.basename(f)).join(", ")}');
            return;
          }
          task.fail('Agent-Timeout nach ${step + 1} Schritten: $e');
          return;
        }

        if (content == null) {
          task.fail('LLM gab keine Antwort (Schritt ${step + 1})');
          return;
        }

        // FIRST: check for block-content write_file calls (handles HTML/JSON with quotes)
        final blockMatches = _blockContentRegex.allMatches(content).toList();
        if (blockMatches.isNotEmpty) {
          messages.add({'role': 'assistant', 'content': content});
          final results = await Future.wait(blockMatches.map((m) async {
            final path = m.group(1)!;
            final blockContent = m.group(2)!;
            task.addStep('write_file($path, ${blockContent.length} chars)');
            debugLog(DebugSource.agentRegistry,
                'Block write: $path (${blockContent.length} chars)');
            return _executeTool('write_file', {'path': path, 'content': blockContent}, task);
          }));
          final resultBuf = StringBuffer();
          for (var i = 0; i < blockMatches.length; i++) {
            resultBuf.writeln('=== ${blockMatches[i].group(1)} ===');
            resultBuf.writeln(results[i]);
          }
          messages.add({
            'role': 'user',
            'content': '[[tool_result]]\n${resultBuf.toString().trim()}\n[[/tool_result]]\n\n'
                'Dateien geschrieben. Verifiziere mit list_files oder antworte mit dem Endergebnis.',
          });
          continue;
        }

        // Check for inline tool calls
        final toolMatches = _toolCallRegex.allMatches(content).toList();

        if (toolMatches.isEmpty) {
          // No tool calls → agent thinks it's done
          final cleanResult = content
              .replaceAll(RegExp(r'\[\[DONE\]\]', caseSensitive: false), '')
              .trim();

          // VERIFICATION PHASE
          // 0. Check if task expects file output but none generated
          final instrLow = task.instruction.toLowerCase();
          final expectsFile = instrLow.contains('pptx') || instrLow.contains('praesentation') ||
              instrLow.contains('präsentation') || instrLow.contains('powerpoint') ||
              instrLow.contains('.docx') || instrLow.contains('.html') ||
              instrLow.contains('.pdf') || instrLow.contains('datei');
          if (expectsFile && task.generatedFiles.isEmpty && step < task.maxSteps - 3 && fileRetries < 2) {
            fileRetries++;
            task.addStep('Keine Dateien erstellt - Nacharbeit ($fileRetries/2)...');
            debugLog(DebugSource.agentRegistry, 'No files generated, retry $fileRetries/2');
            messages.add({'role': 'assistant', 'content': content});
            messages.add({
              'role': 'user',
              'content': '[[tool_result]]\nFEHLER: Du hast KEINE Dateien erstellt!\n'
                  'Benutze write_file mit path="dateiname.pptx" oder path="dateiname.docx".\n'
                  'Schreibe den Inhalt als Markdown (# Titel, - Stichpunkte, IMG_xxx fuer Bilder).\n'
                  'Speichere im Arbeitsverzeichnis: $workspacePath/\n'
                  '[[/tool_result]]',
            });
            continue;
          }

          // 1. Check files exist
          final fileCheck = await _verifyGeneratedFiles(task);
          if (fileCheck != null && step < task.maxSteps - 3) {
            task.addStep('Datei-Check: fehlende Dateien, Nacharbeit...');
            debugLog(DebugSource.agentRegistry, 'File check failed: $fileCheck');
            messages.add({'role': 'assistant', 'content': content});
            messages.add({
              'role': 'user',
              'content': '[[tool_result]]\nDATEI-CHECK FEHLGESCHLAGEN:\n$fileCheck\n[[/tool_result]]\n\n'
                  'Erstelle die fehlenden Dateien jetzt mit write_file.',
            });
            continue;
          }

          // 2. Quality control (max 1 retry to prevent endless loops)
          if (task.generatedFiles.isNotEmpty && qcRetries < 1 && step < task.maxSteps - 2) {
            final qcResult = await _qualityControl(url, task, cleanResult);
            if (qcResult != null) {
              qcRetries++;
              task.addStep('QC: $qcResult');
              debugLog(DebugSource.agentRegistry, 'QC feedback (retry $qcRetries): $qcResult');
              messages.add({'role': 'assistant', 'content': content});
              messages.add({
                'role': 'user',
                'content': '[[tool_result]]\nQUALITAETSKONTROLLE:\n$qcResult\n[[/tool_result]]\n\n'
                    'Behebe die Probleme. Dies ist dein LETZTER Versuch.',
              });
              continue;
            }
          }

          task.complete(cleanResult);
          debugLog(DebugSource.agentRegistry,
              'Sub-agent completed in ${step + 1} steps, '
              '${task.generatedFiles.length} files verified');
          return;
        }

        // Add assistant message
        messages.add({'role': 'assistant', 'content': content});

        // Parse all tool calls
        final toolCalls = toolMatches.map((match) {
          final toolName = match.group(1)!;
          final args = _parseToolArgs(match.group(2) ?? '');
          task.addStep('$toolName(${args.values.take(2).join(", ")})');
          debugLog(DebugSource.agentRegistry, 'Tool: $toolName($args)');
          return (name: toolName, args: args);
        }).toList();

        // Execute ALL tool calls in PARALLEL
        final results = await Future.wait(
          toolCalls.map((tc) => _executeTool(tc.name, tc.args, task)),
        );

        final resultBuf = StringBuffer();
        for (var i = 0; i < toolCalls.length; i++) {
          resultBuf.writeln('=== Ergebnis von ${toolCalls[i].name} ===');
          resultBuf.writeln(results[i]);
          resultBuf.writeln();
        }

        // Inject tool results — truncate if too long to prevent context overflow
        var toolResults = resultBuf.toString().trim();
        if (toolResults.length > 4000) {
          toolResults = '${toolResults.substring(0, 4000)}\n...(gekuerzt, ${toolResults.length} Zeichen gesamt)';
        }
        messages.add({
          'role': 'user',
          'content': '[[tool_result]]\n$toolResults\n[[/tool_result]]\n\n'
              'Fahre mit der Aufgabe fort. Wenn du fertig bist, antworte mit deinem Endergebnis als normalen Text OHNE Tool-Calls.',
        });
      }

      task.complete(
          'Agent hat die maximale Schrittzahl (${task.maxSteps}) erreicht.\n'
          'Letzte Schritte: ${task.steps.join(", ")}');
    } catch (e) {
      task.fail('Agent-Fehler: $e');
      debugLog(DebugSource.agentRegistry, 'Sub-agent error: $e');
    }
  }

  Future<String?> _callLlm(
      String url, List<Map<String, dynamic>> messages) async {
    // Trim context if too many messages (keep system + last 12 exchanges)
    if (messages.length > 20) {
      final system = messages.first;
      final kept = messages.sublist(messages.length - 12);
      // Summarize dropped middle messages
      final dropped = messages.length - 13;
      messages
        ..clear()
        ..add(system)
        ..add({'role': 'user', 'content': '(Vorherige $dropped Nachrichten zusammengefasst: Agent hat recherchiert und Bilder generiert. Fahre jetzt mit der Aufgabe fort - erstelle die PPTX-Datei mit den generierten Bildern.)'})
        ..addAll(kept);
      debugLog(DebugSource.agentRegistry, 'Trimmed context: dropped $dropped messages, keeping ${messages.length}');
    }

    // Also truncate individual message contents that are too long
    for (final msg in messages) {
      final content = msg['content'] as String? ?? '';
      if (content.length > 3000 && msg['role'] != 'system') {
        msg['content'] = '${content.substring(0, 3000)}\n...(gekuerzt)';
      }
    }

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $universalApiKey',
        },
        body: jsonEncode({
          'model': 'auto',
          'stream': false,
          'messages': messages,
        }),
      ).timeout(const Duration(seconds: 180));

      if (response.statusCode != 200) {
        debugLog(DebugSource.agentRegistry,
            'LLM error: ${response.statusCode} ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      return (choices[0]['message'] as Map<String, dynamic>?)?['content']
          as String?;
    } catch (e) {
      debugLog(DebugSource.agentRegistry, 'LLM call failed: $e');
      return null;
    }
  }

  Future<String> _executeTool(
      String name, Map<String, String> args, AgentTask task) async {
    return switch (name) {
      'read_file' => toolReadFile(args['path'] ?? '', workspacePath),
      'write_file' => () async {
          var filePath = args['path'] ?? 'output.txt';
          var content = args['content'] ?? '';
          final ext = p.extension(filePath).toLowerCase();

          // For .html: auto-embed image references as base64
          if (ext == '.html' || ext == '.htm') {
            var htmlContent = content;

            // 1. Replace IMG_xxx image IDs with base64
            if (imageRegistry != null) {
              for (final img in imageRegistry!.images) {
                if (htmlContent.contains(img.id)) {
                  try {
                    final bytes = await File(img.filePath).readAsBytes();
                    final b64 = base64Encode(bytes);
                    final imgExt = p.extension(img.filePath).toLowerCase();
                    final mime = imgExt == '.png' ? 'image/png' : 'image/jpeg';
                    final dataUrl = 'data:$mime;base64,$b64';
                    // Replace all variations
                    htmlContent = htmlContent.replaceAll('src="${img.id}"', 'src="$dataUrl"');
                    htmlContent = htmlContent.replaceAll("src='${img.id}'", "src='$dataUrl'");
                    htmlContent = htmlContent.replaceAll('src="${img.id}.png"', 'src="$dataUrl"');
                    htmlContent = htmlContent.replaceAll('src="${img.id}.jpg"', 'src="$dataUrl"');
                    // Also replace standalone references (not in src=)
                    htmlContent = htmlContent.replaceAll(img.id, dataUrl);
                  } catch (_) {}
                }
              }
            }

            // 2. Also embed workspace images referenced by filename
            final imgPattern = RegExp(r'src="([^"]*\.(png|jpg|jpeg|webp))"', caseSensitive: false);
            for (final m in imgPattern.allMatches(htmlContent).toList().reversed) {
              final src = m.group(1)!;
              if (src.startsWith('data:') || src.startsWith('http')) continue;
              // Try to find the file in workspace
              final imgPath = p.isAbsolute(src) ? src : p.join(workspacePath, src);
              if (await File(imgPath).exists()) {
                try {
                  final bytes = await File(imgPath).readAsBytes();
                  final b64 = base64Encode(bytes);
                  final imgExt = p.extension(imgPath).toLowerCase();
                  final mime = imgExt == '.png' ? 'image/png' : 'image/jpeg';
                  htmlContent = htmlContent.replaceAll(
                      'src="$src"', 'src="data:$mime;base64,$b64"');
                } catch (_) {}
              }
            }

            final resolved = p.isAbsolute(filePath) ? filePath : p.join(workspacePath, filePath);
            final dir = Directory(p.dirname(resolved));
            if (!await dir.exists()) await dir.create(recursive: true);
            await File(resolved).writeAsString(htmlContent);
            task.addGeneratedFile(resolved);
            final embeddedCount = 'data:image/'.allMatches(htmlContent).length;
            return 'HTML erstellt: ${p.basename(resolved)} (${htmlContent.length} chars, $embeddedCount Bilder eingebettet)';
          }

          // For .pptx: generate PowerPoint with slide images
          if (ext == '.pptx') {
            // Check if content references any images
            final hasImgRefs = imageRegistry != null &&
                imageRegistry!.images.any((img) => content.contains(img.id));
            final imgCount = imageRegistry?.images.length ?? 0;

            // Block writing PPTX without images on first attempt
            if (imgCount == 0 && !task.generatedFiles.any((f) => f.endsWith('.pptx'))) {
              return 'STOPP: Du hast noch KEINE Bilder generiert! '
                  'Generiere ZUERST Bilder mit generate_image (aspect="square") fuer jede Folie, '
                  'DANN schreibe die PPTX mit den IMG_IDs im Content. '
                  'Ohne Bilder sieht die Praesentation nicht gut aus!';
            }
            // Warn if images exist but aren't referenced
            if (!hasImgRefs && imgCount > 0 && !task.generatedFiles.any((f) => f.endsWith('.pptx'))) {
              return 'HINWEIS: Du hast $imgCount Bilder generiert aber keine IMG_IDs im Content. '
                  'Fuege die IMG_IDs (${imageRegistry!.images.map((i) => i.id).take(3).join(", ")}) '
                  'unter den Folientiteln ein. Format: # Titel\\n- Punkt 1\\nIMG_xxxxx';
            }

            var resolved = p.isAbsolute(filePath) ? filePath : p.join(workspacePath, filePath);
            // If file is locked (open in another app), use a new filename
            try {
              await _writePptx(content, resolved);
            } on FileSystemException {
              final base = p.basenameWithoutExtension(resolved);
              resolved = p.join(p.dirname(resolved), '${base}_${DateTime.now().millisecondsSinceEpoch}.pptx');
              await _writePptx(content, resolved);
            }
            task.addGeneratedFile(resolved);
            final slideCount = content.split(RegExp(r'^#\s', multiLine: true)).length - 1;
            final resolvedImgs = imageRegistry != null
                ? imageRegistry!.images.where((img) => content.contains(img.id)).length
                : 0;
            return 'PowerPoint erstellt: ${p.basename(resolved)} '
                '($slideCount Folien, $resolvedImgs Bilder eingebettet)';
          }

          // For .pdf: generate PDF
          if (ext == '.pdf') {
            final resolved = p.isAbsolute(filePath) ? filePath : p.join(workspacePath, filePath);
            await _writePdf(content, resolved);
            task.addGeneratedFile(resolved);
            return 'PDF erstellt: ${p.basename(resolved)}';
          }

          // For .docx/.doc: generate real Word DOCX with optional images
          if (ext == '.docx' || ext == '.doc') {
            final docxPath = filePath.endsWith('.doc')
                ? filePath.replaceAll('.doc', '.docx') : filePath;
            final resolved = p.isAbsolute(docxPath) ? docxPath : p.join(workspacePath, docxPath);
            // Safety: strip HTML tags if LLM wrote HTML instead of Markdown
            if (RegExp(r'<(div|h[1-6]|br|hr|p |span|style|table|ul|ol|li|img|a )', caseSensitive: false).hasMatch(content)) {
              content = content
                  .replaceAll(RegExp(r'<br\s*/?>'), '\n')
                  .replaceAll(RegExp(r'<hr[^>]*>'), '\n---\n')
                  .replaceAll(RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false, dotAll: true), '# \$1\n')
                  .replaceAll(RegExp(r'<h2[^>]*>(.*?)</h2>', caseSensitive: false, dotAll: true), '## \$1\n')
                  .replaceAll(RegExp(r'<h3[^>]*>(.*?)</h3>', caseSensitive: false, dotAll: true), '### \$1\n')
                  .replaceAll(RegExp(r'<h4[^>]*>(.*?)</h4>', caseSensitive: false, dotAll: true), '#### \$1\n')
                  .replaceAll(RegExp(r'<b[^>]*>(.*?)</b>', caseSensitive: false, dotAll: true), '**\$1**')
                  .replaceAll(RegExp(r'<strong[^>]*>(.*?)</strong>', caseSensitive: false, dotAll: true), '**\$1**')
                  .replaceAll(RegExp(r'<i[^>]*>(.*?)</i>', caseSensitive: false, dotAll: true), '*\$1*')
                  .replaceAll(RegExp(r'<em[^>]*>(.*?)</em>', caseSensitive: false, dotAll: true), '*\$1*')
                  .replaceAll(RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false, dotAll: true), '- \$1\n')
                  .replaceAll(RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true), '\$1\n\n')
                  .replaceAll(RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '')
                  .replaceAll(RegExp(r'<[^>]+>'), '') // strip remaining tags
                  .replaceAll('&amp;', '&')
                  .replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"')
                  .replaceAll('&#39;', "'").replaceAll('&nbsp;', ' ')
                  .replaceAll(RegExp(r'\n{3,}'), '\n\n'); // collapse excessive newlines
            }
            // Build image map from registry
            Map<String, String>? imgMap;
            if (imageRegistry != null && imageRegistry!.images.isNotEmpty) {
              imgMap = {};
              for (final img in imageRegistry!.images) {
                if (content.contains(img.id)) {
                  imgMap[img.id] = img.filePath;
                }
              }
              if (imgMap.isEmpty) imgMap = null;
            }
            final actualPath = await writeDocx(content, resolved,
                imageFiles: imgMap);
            task.addGeneratedFile(actualPath);
            return 'Word-Datei erstellt: ${p.basename(actualPath)}';
          }

          // For .rtf: convert to RTF
          if (ext == '.rtf') {
            final rtfContent = markdownToRtf(content);
            final result = await toolWriteFile(filePath, rtfContent, workspacePath);
            final resolved = p.isAbsolute(filePath) ? filePath : p.join(workspacePath, filePath);
            task.addGeneratedFile(resolved);
            return result;
          }

          final result = await toolWriteFile(filePath, content, workspacePath);
          final resolved = p.isAbsolute(filePath) ? filePath : p.join(workspacePath, filePath);
          task.addGeneratedFile(resolved);
          return result;
        }(),
      'list_files' => toolListFiles(workspacePath,
          subDir: args['directory'] ?? ''),
      'analyze_document' => toolAnalyzeDocument(
          _resolvePath(args['file_path'] ?? '', workspacePath),
          args['instruction'] ?? 'Analyze this document',
          universalApiKey,
        ),
      'pdf_info' => toolPdfInfo(
          _resolvePath(args['file_path'] ?? '', workspacePath)),
      'pdf_extract_text' => toolPdfExtractText(
          _resolvePath(args['file_path'] ?? '', workspacePath),
          startPage: int.tryParse(args['start_page'] ?? '1') ?? 1,
          endPage: int.tryParse(args['end_page'] ?? '999') ?? 999,
        ),
      'analyze_pdf_pages' => toolAnalyzePdfPages(
          _resolvePath(args['file_path'] ?? '', workspacePath),
          args['instruction'] ?? 'Analysiere diese Seiten',
          universalApiKey,
          startPage: int.tryParse(args['start_page'] ?? '1') ?? 1,
          endPage: int.tryParse(args['end_page'] ?? '5') ?? 5,
        ),
      'wikipedia' => () async {
          final result = await toolWikipedia(args['query'] ?? '',
              lang: args['language'] ?? 'de');
          // Truncate long Wikipedia articles to prevent context overflow
          return result.length > 2000 ? '${result.substring(0, 2000)}\n...(Artikel gekuerzt)' : result;
        }(),
      'weather' => toolWeather(args['location'] ?? 'Berlin'),
      'news' => toolTagesschauNews(topic: args['topic']),
      'web_fetch' => toolWebFetch(args['url'] ?? ''),
      'web_scrape' => () async {
          final result = await toolWebScrape(args['url'] ?? '');
          return result.length > 2000 ? '${result.substring(0, 2000)}\n...(Seite gekuerzt)' : result;
        }(),
      'web_search' => toolWebSearch(args['query'] ?? ''),
      'transcribe_audio' => () async {
          final audioPath = args['file_path'] ?? args['path'] ?? '';
          final resolved = _resolvePath(audioPath, workspacePath);
          if (!await File(resolved).exists()) return 'Audio file not found: $audioPath';

          final url = middlewareUrl(universalApiKey, '/v1/audio/transcriptions');
          if (url == null) return 'Error: Cannot decode middleware URL';

          try {
            final bytes = await File(resolved).readAsBytes();
            final fileName = p.basename(resolved);

            // Multipart POST
            final boundary = '----BudE${DateTime.now().millisecondsSinceEpoch}';
            final body = <int>[];
            void addPart(String name, dynamic value, {String? filename, String? contentType}) {
              body.addAll(utf8.encode('--$boundary\r\n'));
              if (filename != null) {
                body.addAll(utf8.encode('Content-Disposition: form-data; name="$name"; filename="$filename"\r\n'));
                body.addAll(utf8.encode('Content-Type: ${contentType ?? "application/octet-stream"}\r\n\r\n'));
                body.addAll(value as List<int>);
              } else {
                body.addAll(utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
                body.addAll(utf8.encode(value.toString()));
              }
              body.addAll(utf8.encode('\r\n'));
            }

            addPart('file', bytes, filename: fileName, contentType: 'audio/wav');
            addPart('model', 'whisper-1');
            addPart('language', 'de');
            body.addAll(utf8.encode('--$boundary--\r\n'));

            final response = await http.post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'multipart/form-data; boundary=$boundary',
                'Authorization': 'Bearer $universalApiKey',
              },
              body: Uint8List.fromList(body),
            ).timeout(const Duration(seconds: 120));

            if (response.statusCode != 200) {
              return 'Transcription error: HTTP ${response.statusCode}';
            }

            final json = jsonDecode(response.body) as Map<String, dynamic>;
            final text = json['text'] as String? ?? '';
            return 'Transkription von $fileName:\n---\n$text';
          } catch (e) {
            return 'Transcription error: $e';
          }
        }(),
      'generate_image' => () async {
          final prompt = args['prompt'] ?? '';
          final aspect = args['aspect'] ?? '';
          // Resolve size from aspect ratio or explicit size
          var size = args['size'] ?? '1024x1024';
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
          final refId = args['ref'] ?? '';
          if (prompt.isEmpty) return 'Error: prompt is required';

          // Hard limit on image generations per agent run
          _imageGenCount++;
          if (_imageGenCount > _maxImageGens) {
            return 'LIMIT: Maximale Bildanzahl ($_maxImageGens) erreicht. '
                'Erstelle die PPTX jetzt mit den vorhandenen Bildern!';
          }

          final url = middlewareUrl(universalApiKey, '/v1/images/generations');
          if (url == null) return 'Error: Cannot decode middleware URL';

          final body = <String, dynamic>{
            'prompt': prompt,
            'n': 1,
            'size': size,
            'response_format': 'b64_json',
          };

          // Add reference images if specified
          if (refId.isNotEmpty && imageRegistry != null) {
            final refImages = <String>[];
            for (final rid in refId.split(',').map((s) => s.trim())) {
              final img = imageRegistry!.findById(rid);
              if (img != null) {
                try {
                  final bytes = await File(img.filePath).readAsBytes();
                  final b64 = base64Encode(bytes);
                  final ext = p.extension(img.filePath).toLowerCase();
                  final mime = ext == '.png' ? 'image/png' : 'image/jpeg';
                  refImages.add('data:$mime;base64,$b64');
                } catch (_) {}
              }
            }
            if (refImages.isNotEmpty) body['input_images'] = refImages;
          }

          try {
            final response = await http.post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $universalApiKey',
              },
              body: jsonEncode(body),
            ).timeout(const Duration(seconds: 120));

            if (response.statusCode != 200) {
              return 'Image generation error: HTTP ${response.statusCode}';
            }

            final json = jsonDecode(response.body) as Map<String, dynamic>;
            final data = (json['data'] as List?)?.firstOrNull as Map<String, dynamic>?;
            final b64 = data?['b64_json'] as String?;
            if (b64 == null) return 'No image generated';

            // Save image
            final ext = (data?['mime_type'] as String? ?? '').contains('jpeg') ? 'jpg' : 'png';
            final fileName = 'slide_${DateTime.now().millisecondsSinceEpoch}.$ext';
            final filePath = p.join(workspacePath, fileName);
            await File(filePath).writeAsBytes(base64Decode(b64));

            // Register in image registry
            String? imgId;
            if (imageRegistry != null) {
              imgId = imageRegistry!.register(filePath, source: 'generated', prompt: prompt);
            }
            task.addGeneratedFile(filePath);

            return 'Bild generiert: $fileName${imgId != null ? " (ID: $imgId)" : ""}\nPfad: $filePath';
          } catch (e) {
            return 'Image generation error: $e';
          }
        }(),
      'get_image_path' => () async {
          final imgId = args['id'] ?? '';
          if (imageRegistry == null) return 'Kein Image-Registry verfuegbar';
          final img = imageRegistry!.findById(imgId);
          if (img == null) return 'Bild nicht gefunden: $imgId\nVerfuegbare Bilder: ${imageRegistry!.images.map((i) => "${i.id}: ${i.filePath}").join(", ")}';
          return 'Bild $imgId gefunden:\nPfad: ${img.filePath}\nQuelle: ${img.source}\nPrompt: ${img.prompt ?? "n/a"}';
        }(),
      'embed_image_base64' => () async {
          final imgId = args['id'] ?? args['path'] ?? '';
          String filePath;
          if (imageRegistry != null) {
            final img = imageRegistry!.findById(imgId);
            filePath = img?.filePath ?? _resolvePath(imgId, workspacePath);
          } else {
            filePath = _resolvePath(imgId, workspacePath);
          }
          final file = File(filePath);
          if (!await file.exists()) return 'Bild nicht gefunden: $imgId';
          final bytes = await file.readAsBytes();
          final b64 = base64Encode(bytes);
          final ext = p.extension(filePath).toLowerCase();
          final mime = ext == '.png' ? 'image/png' : 'image/jpeg';
          // Store full data URL in a temp variable the agent can reference
          // but DON'T return the full base64 to the LLM (too large!)
          final dataUrl = 'data:$mime;base64,$b64';
          // Save to a temp file so write_file can reference it
          final tempPath = p.join(workspacePath, '_embed_${p.basename(filePath)}.b64');
          await File(tempPath).writeAsString(dataUrl);
          return 'Base64-Daten gespeichert in: $tempPath (${b64.length} chars)\n'
              'Verwende in HTML: <img src="inhalt_von_$tempPath">\n'
              'ODER kopiere die Datei $filePath direkt neben die HTML-Datei und verwende: <img src="${p.basename(filePath)}">';
        }(),
      'delete_file' => () async {
          final path = args['path'] ?? '';
          final resolved = _resolvePath(path, workspacePath);
          final file = File(resolved);
          if (await file.exists()) {
            await file.delete();
            return 'Datei geloescht: $path';
          }
          return 'Datei nicht gefunden: $path';
        }(),
      'run_python' => () async {
          final code = args['code'] ?? '';
          if (code.isEmpty) return 'Error: code is required';

          // Try server-side execution via middleware
          final url = middlewareUrl(universalApiKey, '/v1/code/execute');
          if (url == null) {
            // Fallback: try local Python
            try {
              final result = await Process.run('python', ['-c', code],
                  workingDirectory: workspacePath)
                  .timeout(const Duration(seconds: 10));
              return 'Exit: ${result.exitCode}\nStdout:\n${(result.stdout as String).length > 5000 ? (result.stdout as String).substring(0, 5000) : result.stdout}\n'
                  '${(result.stderr as String).isNotEmpty ? "Stderr:\n${result.stderr}" : ""}';
            } catch (e) {
              return 'Python execution failed: $e';
            }
          }

          try {
            final response = await http.post(Uri.parse(url),
                headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $universalApiKey'},
                body: jsonEncode({'code': code, 'timeout': 10}),
            ).timeout(const Duration(seconds: 15));

            if (response.statusCode != 200) return 'Code execution error: HTTP ${response.statusCode}';
            final json = jsonDecode(response.body) as Map<String, dynamic>;
            final stdout = json['stdout'] as String? ?? '';
            final stderr = json['stderr'] as String? ?? '';
            final exitCode = json['exit_code'] as int? ?? -1;
            return 'Exit: $exitCode\n${stdout.isNotEmpty ? "Output:\n$stdout" : "(no output)"}'
                '${stderr.isNotEmpty ? "\nErrors:\n$stderr" : ""}';
          } catch (e) {
            return 'Code execution failed: $e';
          }
        }(),
      'search_workspace' => () async {
          final query = args['query'] ?? '';
          final dir = Directory(workspacePath);
          if (!await dir.exists()) return 'Workspace leer';
          final files = <String>[];
          await for (final entity in dir.list()) {
            if (entity is File) {
              final name = p.basename(entity.path).toLowerCase();
              if (query.isEmpty || name.contains(query.toLowerCase())) {
                final size = await entity.length();
                files.add('${p.basename(entity.path)} (${(size / 1024).toStringAsFixed(0)} KB)');
              }
            }
          }
          if (files.isEmpty) return 'Keine Dateien gefunden fuer "$query"';
          return 'Dateien im Workspace (${files.length}):\n${files.join("\n")}';
        }(),
      'html_to_docx' => () async {
          final htmlPath = args['html_path'] ?? args['path'] ?? '';
          final outputPath = args['output_path'] ?? htmlPath.replaceAll('.html', '.docx').replaceAll('.htm', '.docx');
          final resolved = _resolvePath(htmlPath, workspacePath);
          if (!await File(resolved).exists()) return 'HTML-Datei nicht gefunden: $htmlPath';
          var html = await File(resolved).readAsString();
          // Convert HTML to Markdown for DOCX generation
          final md = html
              .replaceAll(RegExp(r'<br\s*/?>'), '\n')
              .replaceAll(RegExp(r'<hr[^>]*>'), '\n---\n')
              .replaceAll(RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false, dotAll: true), '# \$1\n')
              .replaceAll(RegExp(r'<h2[^>]*>(.*?)</h2>', caseSensitive: false, dotAll: true), '## \$1\n')
              .replaceAll(RegExp(r'<h3[^>]*>(.*?)</h3>', caseSensitive: false, dotAll: true), '### \$1\n')
              .replaceAll(RegExp(r'<b[^>]*>(.*?)</b>', caseSensitive: false, dotAll: true), '**\$1**')
              .replaceAll(RegExp(r'<strong[^>]*>(.*?)</strong>', caseSensitive: false, dotAll: true), '**\$1**')
              .replaceAll(RegExp(r'<i[^>]*>(.*?)</i>', caseSensitive: false, dotAll: true), '*\$1*')
              .replaceAll(RegExp(r'<em[^>]*>(.*?)</em>', caseSensitive: false, dotAll: true), '*\$1*')
              .replaceAll(RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false, dotAll: true), '- \$1\n')
              .replaceAll(RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true), '\$1\n\n')
              .replaceAll(RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '')
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>')
              .replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n');
          final resolvedOut = _resolvePath(outputPath, workspacePath);
          final actualPath = await writeDocx(md, resolvedOut);
          task.addGeneratedFile(actualPath);
          return 'DOCX erstellt aus HTML: ${p.basename(actualPath)}';
        }(),
      'html_to_pdf' => () async {
          final htmlPath = args['html_path'] ?? args['path'] ?? '';
          final outputPath = args['output_path'] ?? htmlPath.replaceAll('.html', '.pdf').replaceAll('.htm', '.pdf');
          final resolved = _resolvePath(htmlPath, workspacePath);
          if (!await File(resolved).exists()) return 'HTML-Datei nicht gefunden: $htmlPath';
          var html = await File(resolved).readAsString();
          // Convert HTML to Markdown for PDF generation
          final md = html
              .replaceAll(RegExp(r'<br\s*/?>'), '\n')
              .replaceAll(RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false, dotAll: true), '# \$1\n')
              .replaceAll(RegExp(r'<h2[^>]*>(.*?)</h2>', caseSensitive: false, dotAll: true), '## \$1\n')
              .replaceAll(RegExp(r'<h3[^>]*>(.*?)</h3>', caseSensitive: false, dotAll: true), '### \$1\n')
              .replaceAll(RegExp(r'<b[^>]*>(.*?)</b>', caseSensitive: false, dotAll: true), '**\$1**')
              .replaceAll(RegExp(r'<strong[^>]*>(.*?)</strong>', caseSensitive: false, dotAll: true), '**\$1**')
              .replaceAll(RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false, dotAll: true), '- \$1\n')
              .replaceAll(RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true), '\$1\n\n')
              .replaceAll(RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '')
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>')
              .replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n');
          final resolvedOut = _resolvePath(outputPath, workspacePath);
          await _writePdf(md, resolvedOut);
          task.addGeneratedFile(resolvedOut);
          return 'PDF erstellt aus HTML: ${p.basename(resolvedOut)}';
        }(),
      _ => 'Unbekanntes Tool: $name',
    };
  }

  /// Quality control: use a separate LLM call to evaluate the agent's output.
  /// Returns null if quality is OK, or feedback string if rework needed.
  Future<String?> _qualityControl(
      String url, AgentTask task, String agentResult) async {
    // Read back generated DOCX files to verify their content
    final fileContents = StringBuffer();
    for (final filePath in task.generatedFiles) {
      final file = File(filePath);
      if (!await file.exists()) continue;

      final ext = p.extension(filePath).toLowerCase();
      if (ext == '.pptx') {
        // PPTX is binary - just verify it exists and has reasonable size
        final size = await file.length();
        if (size > 5000) {
          // PPTX with content exists - skip QC for binary files
          fileContents.writeln('=== ${p.basename(filePath)} ===');
          fileContents.writeln('PowerPoint-Datei erstellt: ${(size / 1024).toStringAsFixed(0)} KB, OK');
          fileContents.writeln();
        } else {
          fileContents.writeln('=== ${p.basename(filePath)} ===');
          fileContents.writeln('WARNUNG: PPTX zu klein (${size} bytes) - moeglicherweise leer!');
          fileContents.writeln();
        }
      } else if (ext == '.docx') {
        // Read DOCX content
        final text = await toolReadFile(filePath, workspacePath);
        fileContents.writeln('=== ${p.basename(filePath)} ===');
        fileContents.writeln(text.length > 2000 ? '${text.substring(0, 2000)}...' : text);
        fileContents.writeln();
      } else {
        try {
          final content = await file.readAsString();
          fileContents.writeln('=== ${p.basename(filePath)} ===');
          fileContents.writeln(content.length > 2000 ? '${content.substring(0, 2000)}...' : content);
          fileContents.writeln();
        } catch (_) {}
      }
    }

    if (fileContents.isEmpty) return null; // No files to check

    // Ask the QC agent to evaluate
    try {
      final qcResponse = await _callLlm(url, [
        {
          'role': 'system',
          'content': 'Du bist ein Qualitaetskontroll-Agent. Deine Aufgabe ist zu pruefen ob ein '
              'Arbeits-Agent seine Aufgabe KORREKT und VOLLSTAENDIG erledigt hat.\n\n'
              'Pruefe:\n'
              '1. Hat der Agent die RICHTIGE Aufgabe erledigt (nicht eine andere)?\n'
              '2. Sind die erstellten Dateien VOLLSTAENDIG und nicht leer?\n'
              '3. Stimmt das FORMAT (wurde .docx verlangt und .docx geliefert? Oder .html/.pdf?)?\n'
              '4. Ist der INHALT korrekt und relevant fuer die Aufgabe?\n\n'
              'Antworte "OK" wenn alles stimmt.\n'
              'Wenn Probleme: beschreibe sie in 1-3 Saetzen mit konkreten Anweisungen zur Behebung.',
        },
        {
          'role': 'user',
          'content': 'ORIGINAL-AUFGABE DES NUTZERS:\n${task.instruction}\n\n'
              'AGENT-ANTWORT:\n${agentResult.length > 800 ? '${agentResult.substring(0, 800)}...' : agentResult}\n\n'
              'ERSTELLTE DATEIEN UND INHALT:\n${fileContents.toString()}\n\n'
              'Wurde die Aufgabe korrekt erledigt?',
        },
      ]);

      if (qcResponse == null) return null; // QC failed, accept result
      final trimmed = qcResponse.trim();
      if (trimmed.toUpperCase() == 'OK' || trimmed.length < 5) return null;

      // QC found issues
      debugLog(DebugSource.agentRegistry, 'QC agent says: $trimmed');
      task.addStep('QC: $trimmed');
      return trimmed;
    } catch (e) {
      debugLog(DebugSource.agentRegistry, 'QC error: $e');
      return null; // Accept on error
    }
  }

  /// Verify that all generated files exist and have content.
  /// Returns null if all OK, or a description of problems.
  Future<String?> _verifyGeneratedFiles(AgentTask task) async {
    if (task.generatedFiles.isEmpty) return null; // No files expected

    final problems = <String>[];
    final validFiles = <String>[];

    for (final filePath in task.generatedFiles) {
      final file = File(filePath);
      if (!await file.exists()) {
        problems.add('- FEHLT: ${p.basename(filePath)}');
      } else {
        final size = await file.length();
        if (size < 50) {
          problems.add('- LEER/ZU KLEIN: ${p.basename(filePath)} ($size bytes)');
        } else {
          validFiles.add(filePath);
        }
      }
    }

    if (problems.isEmpty) return null;

    return '${problems.join("\n")}\n\n'
        'Vorhandene Dateien: ${validFiles.map((f) => p.basename(f)).join(", ")}\n'
        'Erstelle die fehlenden Dateien mit [[tool:write_file path="..." content="..."]]';
  }

  /// Generate a simple PDF from text content.
  Future<void> _writePdf(String markdown, String outputPath) async {
    final dir = Directory(p.dirname(outputPath));
    if (!await dir.exists()) await dir.create(recursive: true);

    // Clean up literal \n
    final text = markdown.replaceAll('\\n', '\n').replaceAll('\r\n', '\n');
    final allLines = text.split('\n');

    // Split into pages (~40 lines per page)
    final pages = <List<String>>[];
    for (var i = 0; i < allLines.length; i += 40) {
      pages.add(allLines.sublist(i, (i + 40).clamp(0, allLines.length)));
    }
    if (pages.isEmpty) pages.add(['(empty)']);

    // Build PDF
    var objId = 1;
    final catalogId = objId++;
    final pagesId = objId++;
    final fontId = objId++;
    final boldFontId = objId++;
    final pageIds = <int>[];
    final contentIds = <int>[];
    for (var i = 0; i < pages.length; i++) {
      pageIds.add(objId++);
      contentIds.add(objId++);
    }

    final pdf = BytesBuilder();
    final offsets = <int, int>{};

    void addObj(int id, List<int> data) {
      offsets[id] = pdf.length;
      pdf.add(utf8.encode('$id 0 obj\n'));
      pdf.add(data);
      pdf.add(utf8.encode('\nendobj\n'));
    }

    pdf.add(utf8.encode('%PDF-1.4\n'));
    addObj(fontId, utf8.encode('<</Type/Font/Subtype/Type1/BaseFont/Helvetica/Encoding/WinAnsiEncoding>>'));
    addObj(boldFontId, utf8.encode('<</Type/Font/Subtype/Type1/BaseFont/Helvetica-Bold/Encoding/WinAnsiEncoding>>'));
    final kids = pageIds.map((id) => '$id 0 R').join(' ');
    addObj(pagesId, utf8.encode('<</Type/Pages/Kids[$kids]/Count ${pages.length}>>'));
    addObj(catalogId, utf8.encode('<</Type/Catalog/Pages $pagesId 0 R>>'));

    // Helper: wrap long text into lines that fit page width
    // ~85 chars at 10pt Helvetica fits within 495pt (595 - 50 left - 50 right margin)
    List<String> wrapText(String text, int maxChars) {
      if (text.length <= maxChars) return [text];
      final words = text.split(' ');
      final lines = <String>[];
      var current = StringBuffer();
      for (final word in words) {
        if (current.length + word.length + 1 > maxChars && current.isNotEmpty) {
          lines.add(current.toString());
          current = StringBuffer(word);
        } else {
          if (current.isNotEmpty) current.write(' ');
          current.write(word);
        }
      }
      if (current.isNotEmpty) lines.add(current.toString());
      return lines;
    }

    for (var pi = 0; pi < pages.length; pi++) {
      final lines = pages[pi];
      final stream = StringBuffer();
      var y = 780.0;
      for (final line in lines) {
        if (y < 50) break;
        final stripped = line.replaceAll('*', '').replaceAll('#', '').trim();

        if (line.trimLeft().startsWith('# ') && !line.trimLeft().startsWith('## ')) {
          for (final wl in wrapText(stripped, 55)) {
            if (y < 50) break;
            stream.write('BT /F2 16 Tf 1 0 0 1 50 $y Tm (${_pdfEsc(wl)}) Tj ET\n');
            y -= 22;
          }
          y -= 4;
        } else if (line.trimLeft().startsWith('## ')) {
          for (final wl in wrapText(stripped, 65)) {
            if (y < 50) break;
            stream.write('BT /F2 13 Tf 1 0 0 1 50 $y Tm (${_pdfEsc(wl)}) Tj ET\n');
            y -= 18;
          }
          y -= 2;
        } else if (line.trimLeft().startsWith('### ')) {
          stream.write('BT /F2 11 Tf 1 0 0 1 50 $y Tm (${_pdfEsc(stripped)}) Tj ET\n');
          y -= 16;
        } else if (line.trim().isEmpty) {
          y -= 8;
        } else if (line.trimLeft().startsWith('- ') || line.trimLeft().startsWith('* ')) {
          final bulletText = stripped.startsWith('- ') ? stripped.substring(2) : stripped;
          for (var j = 0; j < wrapText(bulletText, 80).length; j++) {
            if (y < 50) break;
            final wl = wrapText(bulletText, 80)[j];
            final prefix = j == 0 ? '\\267 ' : '  ';
            final x = j == 0 ? 65 : 75;
            stream.write('BT /F1 10 Tf 1 0 0 1 $x $y Tm ($prefix${_pdfEsc(wl)}) Tj ET\n');
            y -= 14;
          }
        } else {
          for (final wl in wrapText(line, 85)) {
            if (y < 50) break;
            stream.write('BT /F1 10 Tf 1 0 0 1 50 $y Tm (${_pdfEsc(wl)}) Tj ET\n');
            y -= 14;
          }
        }
      }
      final streamBytes = utf8.encode(stream.toString());
      addObj(contentIds[pi], utf8.encode('<</Length ${streamBytes.length}>>stream\n') + Uint8List.fromList(streamBytes) + utf8.encode('\nendstream'));
      addObj(pageIds[pi], utf8.encode(
          '<</Type/Page/Parent $pagesId 0 R/MediaBox[0 0 595 842]'
          '/Contents ${contentIds[pi]} 0 R'
          '/Resources<</Font<</F1 $fontId 0 R/F2 $boldFontId 0 R>>>>>>'));
    }

    final xrefPos = pdf.length;
    pdf.add(utf8.encode('xref\n0 $objId\n'));
    pdf.add(utf8.encode('0000000000 65535 f \n'));
    for (var i = 1; i < objId; i++) {
      pdf.add(utf8.encode('${(offsets[i] ?? 0).toString().padLeft(10, '0')} 00000 n \n'));
    }
    pdf.add(utf8.encode('trailer\n<</Size $objId/Root $catalogId 0 R>>\n'));
    pdf.add(utf8.encode('startxref\n$xrefPos\n%%EOF'));

    await File(outputPath).writeAsBytes(pdf.toBytes());
  }

  /// XML-escape text for PPTX content.
  static String _xmlEsc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Build text runs supporting **bold** markdown markers.
  static String _textRuns(String text, {
    required String color, required int sz, String font = 'Calibri',
  }) {
    final buf = StringBuffer();
    final parts = text.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      final bold = i % 2 == 1;
      buf.write('<a:r><a:rPr lang="de-DE" sz="$sz"${bold ? ' b="1"' : ''} dirty="0">'
          '<a:solidFill><a:srgbClr val="$color"/></a:solidFill>'
          '<a:latin typeface="$font"/></a:rPr>'
          '<a:t>${_xmlEsc(parts[i])}</a:t></a:r>');
    }
    return buf.toString();
  }

  /// Build bullet paragraphs for PPTX slides.
  static String _bulletXml(List<String> bullets, {
    String color = '2C3E50', int sz = 1800, String accent = '3498DB',
  }) {
    final buf = StringBuffer();
    for (final b in bullets) {
      buf.write('<a:p>'
          '<a:pPr marL="457200" indent="-228600">'
          '<a:spcBef><a:spcPts val="600"/></a:spcBef>'
          '<a:buClr><a:srgbClr val="$accent"/></a:buClr>'
          '<a:buFont typeface="Arial"/><a:buChar char="&#x25CF;"/>'
          '</a:pPr>'
          '${_textRuns(b, color: color, sz: sz)}'
          '</a:p>');
    }
    return buf.toString();
  }

  /// Generate a PPTX from markdown content with professional layouts.
  ///
  /// Supports 4 layouts:
  /// 1. **Title slide** (first slide): gradient bg, large centered title + subtitle
  /// 2. **Image + bullets**: title bar, image left, bullets right
  /// 3. **Image only**: title bar, full-bleed image
  /// 4. **Text only**: title bar, bullets on light background
  ///
  /// Content format:
  /// ```
  /// # Presentation Title
  /// subtitle: Optional subtitle
  /// # Slide Title
  /// - Bullet point 1
  /// - Bullet point 2
  /// IMG_xxxxx
  /// ```
  Future<void> _writePptx(String markdown, String outputPath) async {
    final dir = Directory(p.dirname(outputPath));
    if (!await dir.exists()) await dir.create(recursive: true);

    final text = markdown.replaceAll('\\n', '\n');
    final lines = text.split('\n');

    // --- Parse slides ---
    final slides = <_PptxSlide>[];
    _PptxSlide? current;

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) continue;

      // New slide on heading
      if (t.startsWith('#')) {
        if (current != null) slides.add(current);
        current = _PptxSlide(title: t.replaceAll(RegExp(r'^#+\s*'), ''));
        continue;
      }

      if (current == null) {
        current = _PptxSlide(title: t);
        continue;
      }

      // Subtitle (only before any bullets/images)
      if ((t.toLowerCase().startsWith('subtitle:') || t.toLowerCase().startsWith('untertitel:'))
          && current.bullets.isEmpty && !current.hasImage) {
        current.subtitle = t.substring(t.indexOf(':') + 1).trim();
        continue;
      }

      // Bullet point
      if (t.startsWith('- ') || t.startsWith('* ') || t.startsWith('• ')) {
        current.bullets.add(t.substring(2).trim());
        continue;
      }

      // Numbered list
      final numMatch = RegExp(r'^\d+[\.\)]\s+(.+)').firstMatch(t);
      if (numMatch != null) {
        current.bullets.add(numMatch.group(1)!);
        continue;
      }

      // Image reference — check registry first, then detect orphaned IMG_ refs
      String? foundImgId;
      if (imageRegistry != null) {
        for (final img in imageRegistry!.images) {
          if (t.contains(img.id)) { foundImgId = img.id; break; }
        }
      }
      if (foundImgId != null) {
        final img = imageRegistry!.findById(foundImgId);
        if (img != null) {
          try { current.imageBytes = await File(img.filePath).readAsBytes(); } catch (_) {}
        }
        continue;
      }
      // Skip orphaned IMG_xxx references (image generation failed)
      if (RegExp(r'^IMG_[a-z0-9]{4,}$').hasMatch(t)) continue;

      // Regular text → treat as bullet (but strip any inline IMG_xxx refs)
      final cleaned = t.replaceAll(RegExp(r'IMG_[a-z0-9]{4,}'), '').trim();
      if (cleaned.isNotEmpty && cleaned.length < 300) current.bullets.add(cleaned);
    }
    if (current != null) slides.add(current);
    if (slides.isEmpty) slides.add(_PptxSlide(title: 'Presentation'));

    // First slide is always the title slide
    slides[0].isTitleSlide = true;

    // --- Constants (EMU) ---
    const W = 12192000;    // slide width
    const H = 6858000;     // slide height
    const barH = 950000;   // title bar height
    const accentH = 36000; // accent line height
    const contentY = barH + accentH;
    const contentH = H - contentY;

    // --- Colors ---
    const cDark = '0F1B2D';
    const cBar = '1B2A4A';
    const cAccent = '3498DB';
    const cWhite = 'FFFFFF';
    const cText = '2C3E50';
    const cSubtle = '8899AA';
    const cContentBg = 'F5F7FA';

    // --- Build PPTX ZIP ---
    final files = <String, List<int>>{};

    // Content Types
    final ctBuf = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="jpeg" ContentType="image/jpeg"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>');
    for (var i = 0; i < slides.length; i++) {
      ctBuf.write('<Override PartName="/ppt/slides/slide${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
    }
    ctBuf.write('</Types>');
    files['[Content_Types].xml'] = utf8.encode(ctBuf.toString());

    // Root rels
    files['_rels/.rels'] = utf8.encode(
        '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
        '</Relationships>');

    // Presentation + rels
    final slideRefs = StringBuffer();
    final presRels = StringBuffer(
        '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (var i = 0; i < slides.length; i++) {
      slideRefs.write('<p:sldId id="${256 + i}" r:id="rSlide${i + 1}" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>');
      presRels.write('<Relationship Id="rSlide${i + 1}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
          'Target="slides/slide${i + 1}.xml"/>');
    }
    presRels.write('</Relationships>');

    files['ppt/presentation.xml'] = utf8.encode(
        '<?xml version="1.0"?>'
        '<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<p:sldSz cx="$W" cy="$H"/>'
        '<p:sldIdLst>${slideRefs.toString()}</p:sldIdLst>'
        '</p:presentation>');
    files['ppt/_rels/presentation.xml.rels'] = utf8.encode(presRels.toString());

    // --- Generate each slide ---
    const nsP = 'http://schemas.openxmlformats.org/presentationml/2006/main';
    const nsA = 'http://schemas.openxmlformats.org/drawingml/2006/main';
    const nsR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

    for (var i = 0; i < slides.length; i++) {
      final s = slides[i];
      final xml = StringBuffer(
          '<?xml version="1.0"?>'
          '<p:sld xmlns:p="$nsP" xmlns:a="$nsA" xmlns:r="$nsR">'
          '<p:cSld><p:spTree>'
          '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
          '<p:grpSpPr/>');

      var nextId = 2;

      if (s.isTitleSlide) {
        // ═══════════════════════════════════════════
        //  TITLE SLIDE — gradient bg, centered title
        // ═══════════════════════════════════════════

        // Gradient background
        xml.write(_sp(nextId++, 'Bg', 0, 0, W, H,
            fill: '<a:gradFill><a:gsLst>'
                '<a:gs pos="0"><a:srgbClr val="$cDark"/></a:gs>'
                '<a:gs pos="100000"><a:srgbClr val="$cBar"/></a:gs>'
                '</a:gsLst><a:lin ang="5400000"/></a:gradFill>'));

        // Title
        xml.write(_textBox(nextId++, 'Title', 600000, 1800000, 11000000, 1600000,
            align: 'ctr', anchor: 'b',
            runs: _textRuns(s.title, color: cWhite, sz: 4400)));

        // Decorative accent line
        xml.write(_sp(nextId++, 'Line', 4596000, 3500000, 3000000, accentH,
            fill: '<a:solidFill><a:srgbClr val="$cAccent"/></a:solidFill>'));

        // Subtitle
        final sub = s.subtitle.isNotEmpty ? s.subtitle
            : (s.bullets.isNotEmpty ? s.bullets.join(' | ') : '');
        if (sub.isNotEmpty) {
          xml.write(_textBox(nextId++, 'Sub', 600000, 3650000, 11000000, 1000000,
              align: 'ctr', anchor: 't',
              runs: _textRuns(sub, color: cSubtle, sz: 2200)));
        }

        // Slide number
        xml.write(_slideNum(nextId++, i + 1, slides.length));

      } else if (s.hasImage && s.hasBullets) {
        // ═══════════════════════════════════════════
        //  IMAGE + BULLETS — adaptive split layout
        // ═══════════════════════════════════════════

        // Title bar background
        xml.write(_sp(nextId++, 'Bar', 0, 0, W, barH,
            fill: '<a:solidFill><a:srgbClr val="$cBar"/></a:solidFill>'));
        // Accent line
        xml.write(_sp(nextId++, 'Accent', 0, barH, W, accentH,
            fill: '<a:solidFill><a:srgbClr val="$cAccent"/></a:solidFill>'));
        // Title text
        xml.write(_textBox(nextId++, 'Title', 500000, 130000, 11200000, 700000,
            align: 'l', anchor: 'ctr',
            runs: _textRuns(s.title, color: cWhite, sz: 2800)));
        // Content area background
        xml.write(_sp(nextId++, 'CBg', 0, contentY, W, contentH,
            fill: '<a:solidFill><a:srgbClr val="$cContentBg"/></a:solidFill>'));

        // Adapt layout to image aspect ratio
        final pad = 150000;
        final availH = contentH - pad * 2;
        final imgTop = contentY + pad;

        int imgX, imgW, imgH, bltX, bltW;
        if (s.isSquareImage) {
          // Square image: image sized to fit height, centered left
          imgH = availH;
          imgW = availH; // 1:1
          imgX = 300000;
          bltX = imgX + imgW + 300000;
          bltW = W - bltX - 300000;
        } else if (s.isLandscapeImage) {
          // Landscape: image spans wider, bullets narrower
          imgW = (W * 0.52).round();
          imgH = (imgW / s.imageAspect).round();
          if (imgH > availH) { imgH = availH; imgW = (imgH * s.imageAspect).round(); }
          imgX = 200000;
          bltX = imgX + imgW + 300000;
          bltW = W - bltX - 200000;
        } else {
          // Portrait: image narrower, bullets wider
          imgH = availH;
          imgW = (imgH * s.imageAspect).round();
          if (imgW > W ~/ 2) imgW = W ~/ 2;
          imgX = 300000;
          bltX = imgX + imgW + 300000;
          bltW = W - bltX - 300000;
        }

        xml.write(
            '<p:pic><p:nvPicPr><p:cNvPr id="${nextId++}" name="img"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>'
            '<p:blipFill><a:blip r:embed="rImg"/>'
            '<a:stretch><a:fillRect/></a:stretch></p:blipFill>'
            '<p:spPr><a:xfrm><a:off x="$imgX" y="$imgTop"/>'
            '<a:ext cx="$imgW" cy="$imgH"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>');

        // Bullets on right
        xml.write(_textBox(nextId++, 'Bullets', bltX, imgTop, bltW, availH,
            align: 'l', anchor: 't', autoFit: true,
            body: _bulletXml(s.bullets, color: cText, sz: 1800)));

        // Slide number
        xml.write(_slideNum(nextId++, i + 1, slides.length));

      } else if (s.hasImage) {
        // ═══════════════════════════════════════════
        //  IMAGE ONLY — title bar + full image
        // ═══════════════════════════════════════════

        // Title bar
        xml.write(_sp(nextId++, 'Bar', 0, 0, W, barH,
            fill: '<a:solidFill><a:srgbClr val="$cBar"/></a:solidFill>'));
        xml.write(_sp(nextId++, 'Accent', 0, barH, W, accentH,
            fill: '<a:solidFill><a:srgbClr val="$cAccent"/></a:solidFill>'));
        xml.write(_textBox(nextId++, 'Title', 500000, 130000, 11200000, 700000,
            align: 'l', anchor: 'ctr',
            runs: _textRuns(s.title, color: cWhite, sz: 2800)));

        // Full image below
        xml.write(
            '<p:pic><p:nvPicPr><p:cNvPr id="${nextId++}" name="img"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>'
            '<p:blipFill><a:blip r:embed="rImg"/>'
            '<a:stretch><a:fillRect/></a:stretch></p:blipFill>'
            '<p:spPr><a:xfrm><a:off x="0" y="$contentY"/>'
            '<a:ext cx="$W" cy="$contentH"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>');

        xml.write(_slideNum(nextId++, i + 1, slides.length));

      } else {
        // ═══════════════════════════════════════════
        //  TEXT ONLY — title bar + bullets on light bg
        // ═══════════════════════════════════════════

        // Title bar
        xml.write(_sp(nextId++, 'Bar', 0, 0, W, barH,
            fill: '<a:solidFill><a:srgbClr val="$cBar"/></a:solidFill>'));
        xml.write(_sp(nextId++, 'Accent', 0, barH, W, accentH,
            fill: '<a:solidFill><a:srgbClr val="$cAccent"/></a:solidFill>'));
        xml.write(_textBox(nextId++, 'Title', 500000, 130000, 11200000, 700000,
            align: 'l', anchor: 'ctr',
            runs: _textRuns(s.title, color: cWhite, sz: 2800)));
        // Content area
        xml.write(_sp(nextId++, 'CBg', 0, contentY, W, contentH,
            fill: '<a:solidFill><a:srgbClr val="$cContentBg"/></a:solidFill>'));

        // Bullets full width
        if (s.hasBullets) {
          xml.write(_textBox(nextId++, 'Bullets', 700000, contentY + 200000,
              10800000, contentH - 400000,
              align: 'l', anchor: 't', autoFit: true,
              body: _bulletXml(s.bullets, color: cText, sz: 2000)));
        }

        xml.write(_slideNum(nextId++, i + 1, slides.length));
      }

      xml.write('</p:spTree></p:cSld></p:sld>');
      files['ppt/slides/slide${i + 1}.xml'] = utf8.encode(xml.toString());

      // Slide relationships
      if (s.hasImage) {
        files['ppt/media/slide${i + 1}.png'] = s.imageBytes!;
        files['ppt/slides/_rels/slide${i + 1}.xml.rels'] = utf8.encode(
            '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rImg" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
            'Target="../media/slide${i + 1}.png"/></Relationships>');
      } else {
        files['ppt/slides/_rels/slide${i + 1}.xml.rels'] = utf8.encode(
            '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '</Relationships>');
      }
    }

    await File(outputPath).writeAsBytes(_createPptxZip(files));
  }

  /// Helper: simple shape (rectangle with fill, no outline).
  static String _sp(int id, String name, int x, int y, int cx, int cy,
      {required String fill}) =>
      '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
      '$fill<a:ln><a:noFill/></a:ln></p:spPr></p:sp>';

  /// Helper: text box shape with optional autofit.
  static String _textBox(int id, String name, int x, int y, int cx, int cy, {
    required String align, required String anchor,
    String runs = '', String body = '', bool autoFit = false,
  }) {
    final fitXml = autoFit ? '<a:normAutofit fontScale="70000" lnSpcReduction="10000"/>' : '';
    final content = body.isNotEmpty ? body : '<a:p><a:pPr algn="$align"/>$runs</a:p>';
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr>'
        '<p:txBody><a:bodyPr wrap="square" anchor="$anchor">$fitXml</a:bodyPr>'
        '$content</p:txBody></p:sp>';
  }

  /// Helper: slide number indicator (bottom right).
  static String _slideNum(int id, int num, int total) =>
      _textBox(id, 'SlideNum', 11000000, 6500000, 900000, 300000,
          align: 'r', anchor: 'ctr',
          runs: '<a:r><a:rPr lang="de-DE" sz="1000" dirty="0">'
              '<a:solidFill><a:srgbClr val="999999"/></a:solidFill>'
              '<a:latin typeface="Calibri"/></a:rPr>'
              '<a:t>$num / $total</a:t></a:r>');

  Uint8List _createPptxZip(Map<String, List<int>> files) {
    // Reuse the DOCX ZIP builder from docx_tools
    final out = BytesBuilder();
    final cd = BytesBuilder();
    var n = 0;
    for (final e in files.entries) {
      final name = utf8.encode(e.key);
      final data = Uint8List.fromList(e.value);
      final crc = _crc32pptx(data);
      final off = out.length;
      out.add(_u32p(0x04034B50));
      out.add(_u16p(20)); out.add(_u16p(0)); out.add(_u16p(0));
      out.add(_u16p(0)); out.add(_u16p(0));
      out.add(_u32p(crc)); out.add(_u32p(data.length)); out.add(_u32p(data.length));
      out.add(_u16p(name.length)); out.add(_u16p(0));
      out.add(name); out.add(data);
      cd.add(_u32p(0x02014B50));
      cd.add(_u16p(20)); cd.add(_u16p(20)); cd.add(_u16p(0)); cd.add(_u16p(0));
      cd.add(_u16p(0)); cd.add(_u16p(0));
      cd.add(_u32p(crc)); cd.add(_u32p(data.length)); cd.add(_u32p(data.length));
      cd.add(_u16p(name.length)); cd.add(_u16p(0)); cd.add(_u16p(0));
      cd.add(_u16p(0)); cd.add(_u16p(0)); cd.add(_u32p(0)); cd.add(_u32p(off));
      cd.add(name);
      n++;
    }
    final cdOff = out.length;
    final cdData = cd.toBytes();
    out.add(cdData);
    out.add(_u32p(0x06054B50));
    out.add(_u16p(0)); out.add(_u16p(0));
    out.add(_u16p(n)); out.add(_u16p(n));
    out.add(_u32p(cdData.length)); out.add(_u32p(cdOff)); out.add(_u16p(0));
    return out.toBytes();
  }

  Uint8List _u16p(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
  Uint8List _u32p(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
  int _crc32pptx(Uint8List d) {
    var c = 0xFFFFFFFF;
    for (final b in d) { c ^= b; for (var j = 0; j < 8; j++) c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1; }
    return c ^ 0xFFFFFFFF;
  }

  /// Escape a string for use inside a PDF text operator: (text) Tj
  /// Escape string for PDF text operators with WinAnsi encoding.
  /// Converts German umlauts and special chars to octal codes.
  static String _pdfEsc(String s) {
    final buf = StringBuffer();
    for (final c in s.codeUnits) {
      switch (c) {
        case 0x5C: buf.write('\\\\'); // backslash
        case 0x28: buf.write('\\(');  // (
        case 0x29: buf.write('\\)');  // )
        // German umlauts + special chars → WinAnsi octal
        case 0xE4: buf.write('\\344'); // ä
        case 0xF6: buf.write('\\366'); // ö
        case 0xFC: buf.write('\\374'); // ü
        case 0xC4: buf.write('\\304'); // Ä
        case 0xD6: buf.write('\\326'); // Ö
        case 0xDC: buf.write('\\334'); // Ü
        case 0xDF: buf.write('\\337'); // ß
        case 0xE9: buf.write('\\351'); // é
        case 0xE8: buf.write('\\350'); // è
        case 0xEA: buf.write('\\352'); // ê
        case 0xE0: buf.write('\\340'); // à
        case 0xF1: buf.write('\\361'); // ñ
        // Common Unicode → WinAnsi mappings
        case 0x2013: buf.write('\\226'); // – en-dash
        case 0x2014: buf.write('\\227'); // — em-dash
        case 0x2018: buf.write('\\221'); // ' left single quote
        case 0x2019: buf.write('\\222'); // ' right single quote
        case 0x201C: buf.write('\\223'); // " left double quote
        case 0x201D: buf.write('\\224'); // " right double quote
        case 0x2022: buf.write('\\267'); // • bullet
        case 0x2026: buf.write('\\205'); // … ellipsis
        case 0x20AC: buf.write('\\200'); // € euro sign
        default:
          if (c >= 32 && c <= 126) {
            buf.writeCharCode(c); // ASCII printable
          } else if (c >= 128 && c <= 255) {
            buf.write('\\${c.toRadixString(8).padLeft(3, '0')}'); // WinAnsi octal
          } else if (c > 255) {
            buf.write('-'); // Non-WinAnsi: replace with dash
          } else {
            buf.writeCharCode(c);
          }
      }
    }
    return buf.toString();
  }

  String _resolvePath(String path, String workspace) {
    if (p.isAbsolute(path)) return path;
    return p.join(workspace, path);
  }

  String _systemPrompt(AgentTask task) {
    // Detect task type for specialized instructions
    final instr = task.instruction.toLowerCase();
    final isCorrection = instr.contains('korrigier') || instr.contains('korrektur') ||
        instr.contains('bewert') || instr.contains('klassenarbeit');
    final isPresentation = instr.contains('praesentation') || instr.contains('präsentation') ||
        instr.contains('powerpoint') || instr.contains('pptx') ||
        instr.contains('folien') || instr.contains('slides');

    return '''Du bist ein Aufgaben-Agent. Fuehre GENAU die Aufgabe aus die dir gegeben wird.
Erfinde KEINE zusaetzlichen Aufgaben. Ignoriere alte Dateien im Workspace die nichts mit deiner Aufgabe zu tun haben.

TOOLS:
[[tool:read_file path="datei.txt"]]  (liest auch .docx!)
[[tool:delete_file path="alte_datei.txt"]]
[[tool:get_image_path id="IMG_abc123"]]  (gibt den echten Dateipfad eines Bildes zurueck)
[[tool:generate_image prompt="Beschreibung auf Englisch" size="1024x1024" aspect="square" ref=""]]
  Bildformate (aspect): square (1:1), landscape (16:9), portrait (9:16), photo (4:3)
  size wird automatisch gesetzt wenn aspect angegeben: square=1024x1024, landscape=1792x1024, portrait=1024x1792, photo=1365x1024
[[tool:transcribe_audio file_path="audio.wav"]]  (Audio-Datei transkribieren, gibt Text zurueck)
[[tool:web_search query="Suchbegriffe"]]  (Brave Search - sucht im Web)
[[tool:web_scrape url="https://example.com"]]  (Text einer Webseite extrahieren)
[[tool:run_python code="print('Hello World')"]]  (Python-Code ausfuehren, Ergebnis zurueck)
[[tool:search_workspace query="kaffee"]]  (Dateien im Workspace suchen)
[[tool:html_to_docx html_path="datei.html" output_path="datei.docx"]]  (HTML in Word konvertieren)
[[tool:html_to_pdf html_path="datei.html" output_path="datei.pdf"]]  (HTML in PDF konvertieren)

DATEIEN SCHREIBEN - ZWEI FORMATE:

Format 1 (kurze Inhalte ohne Anfuehrungszeichen):
[[tool:write_file path="name.docx" content="# Titel\nInhalt ohne Anfuehrungszeichen"]]

Format 2 (EMPFOHLEN fuer HTML, lange Texte, Inhalte mit Anfuehrungszeichen):
[[tool:write_file path="name.html"]]
<<<CONTENT
<!DOCTYPE html>
<html>
<head><title>Titel</title></head>
<body>
<h1>Ueberschrift</h1>
<p>Inhalt mit "Anfuehrungszeichen" und <tags>.</p>
</body>
</html>
CONTENT>>>

Benutze Format 2 fuer HTML, JSON und lange Dokumente!
Das <<<CONTENT...CONTENT>>> Format kann beliebig lang sein.
[[tool:list_files directory=""]]
[[tool:pdf_info file_path="dokument.pdf"]]
[[tool:pdf_extract_text file_path="dokument.pdf" start_page="1" end_page="5"]]
[[tool:analyze_pdf_pages file_path="dok.pdf" instruction="..." start_page="1" end_page="5"]]
[[tool:analyze_document file_path="bild.png" instruction="..."]]
[[tool:wikipedia query="..." language="de"]]
[[tool:weather location="..."]]
[[tool:news topic="..."]]
[[tool:web_fetch url="..."]]

DATEIFORMATE:
write_file erzeugt automatisch das richtige Format je nach Dateiendung:
- .docx = Word-Datei (Calibri 11pt, blaue Ueberschriften) ← STANDARD
- .pptx = PowerPoint-Praesentation (16:9 Folien mit Bildern)
- .pdf = PDF-Datei (Helvetica, sauberes Layout)
- .html = HTML-Datei
- .md = Markdown
WICHTIG: Fuer .docx und .pdf Dateien schreibe den Inhalt IMMER als Markdown:
  # Ueberschrift, ## Unterueberschrift, **fett**, *kursiv*, - Liste
  NIEMALS HTML-Tags in .docx oder .pdf Dateien verwenden!
  HTML-Tags (<div>, <br>, <h1> etc.) nur in .html Dateien!
Wenn der Nutzer ein bestimmtes Format verlangt (HTML, PDF, etc.) benutze das!
Sonst benutze .docx als Standard.

PRAESENTATIONEN (PPTX) - WICHTIG:
Benutze IMMER .pptx (NICHT .html) fuer Praesentationen!
1. Recherchiere ZUERST mit wikipedia + web_search. Scrape 1-2 Links.
2. Generiere Bilder, maximal 2-3 pro Schritt.
   - Fuer Folien mit Text + Bild (Split-Layout): aspect="square" (1:1)
   - Fuer Folien nur mit Bild (Vollbild): aspect="landscape" (16:9)
3. Schreibe die PPTX mit Stichpunkten pro Folie.
4. Letzte Folie = Quellenangaben.

PPTX-Format:
# Haupttitel
subtitle: Untertitel
# Folientitel
- **Begriff**: Erklaerung
- Fakt mit Zahlen
- Konkreter Punkt
IMG_xxxxx
# Quellen
- Wikipedia: Artikel (URL)
- Webquelle: Titel (URL)

BILDER IN HTML EINBAUEN (WICHTIG!):
Schreibe einfach <img src="IMG_xxxxx"> im HTML. Die Bild-ID wird AUTOMATISCH durch
die echten base64-Daten ersetzt wenn die Datei gespeichert wird!
Beispiel: <img src="IMG_k5uchu" style="max-width:100%">
Du brauchst KEIN embed_image_base64 aufzurufen!

WEBSEITEN: web_scrape fuer Text, web_fetch fuer rohen HTML.${isPresentation ? '''

PRAESENTATIONS-MODUS (AKTIV!):
Du erstellst eine PowerPoint-Praesentation. Beachte STRIKT:

SCHRITT 1 - RECHERCHE (KURZ!):
- Benutze wikipedia fuer einen Ueberblick (1-2 Artikel, NICHT mehr).
- Optional: 1x web_search fuer aktuelle Infos.
- KEINE endlose Recherche! Nach 1-2 Quellen SOFORT zu Schritt 2 wechseln!
- Notiere dir Quellen-URLs fuer die letzte Folie.

SCHRITT 2 - BILDER GENERIEREN:
- Generiere fuer jede Inhaltsfolie ein Bild mit passendem Format:
  * Folien MIT Stichpunkten (Bild + Text nebeneinander): aspect="square"
  * Folien NUR mit Bild (Vollbild-Folie): aspect="landscape"
- Generiere maximal 2 Bilder PRO Schritt (nicht alle auf einmal!).
- Merke dir die IMG_IDs.
- Bei Fehler: EIN Retry mit kurzerem Prompt. Danach OHNE Bild weitermachen!
- MAXIMAL 8 Bildgenerierungen insgesamt. Nicht endlos wiederholen!

SCHRITT 3 - PPTX SCHREIBEN:
- Benutze IMMER .pptx (NICHT .html)!
- Format im content (EXAKT so!):

# Haupttitel der Praesentation
subtitle: Untertitel oder Kurzbeschreibung

# Erste Inhaltsfolie
- **Wichtiger Begriff**: Erklaerung dazu
- Konkreter Fakt mit Zahlen oder Daten
- Weiterer informativer Punkt
- Zusammenfassender Aspekt
IMG_xxxxx

# Zweite Inhaltsfolie
- Naechster Themenaspekt
- Detail mit Quellenangabe
- Praxisbeispiel oder Anwendung
IMG_yyyyy

# Quellen und Weiterfuehrende Links
- Wikipedia: Artikelname (de.wikipedia.org/wiki/...)
- Webquelle: Titel der Seite (URL)
- Weitere Quelle (URL)

REGELN:
- MINDESTENS 6 Folien mit 3-5 Stichpunkten UND Bild.
- Letzte Folie = Quellenangaben (ohne Bild).
- **Fettdruck** fuer wichtige Begriffe in Stichpunkten benutzen!
- Stichpunkte muessen KONKRET und INFORMATIV sein (keine generischen Phrasen).
- Verifiziere am Ende mit list_files dass die .pptx existiert.''' : ''}${isCorrection ? '''

KORREKTUR-MODUS:
1. Lies die Transkription in der Aufgabe (bereits extrahiert).
2. Identifiziere alle Schueler und ordne Seiten zu.
3. Bewerte jede Teilaufgabe mit Punkten und Begruendung.
4. Erstelle pro Schueler eine .docx: korrektur_vorname_nachname.docx''' : ''}

REGELN:
- Fuehre NUR die gegebene Aufgabe aus - nichts anderes!
- Mehrere Tools pro Antwort = parallel, schneller.
- VERIFIZIERE am Ende mit list_files dass Dateien existieren.
- Nenne den ABSOLUTEN Pfad: $workspacePath/dateiname
- Wenn FERTIG: antworte mit Endergebnis als Text OHNE [[tool:...]].
- ERFINDE NIEMALS Bild-IDs! Bild-IDs kommen NUR von generate_image Ergebnissen (z.B. IMG_a7x3kp).
  Schreibe KEINE Zahlen als IMG_IDs (z.B. IMG_123456 ist FALSCH).
  Benutze KEIN get_image_path ausser du hast eine echte ID von generate_image bekommen.
- Benutze NIEMALS python-pptx oder andere Python-Bibliotheken! write_file erstellt PPTX automatisch.
- Speichere ALLE Dateien im Arbeitsverzeichnis: $workspacePath/
  Benutze NIEMALS /tmp/ oder andere Verzeichnisse!

WEBSUCHE-REGELN (WICHTIG!):
- Mache maximal 1-2 web_search Aufrufe pro Recherche.
- Nach JEDER web_search: Scrape die Top 5 URLs SOFORT parallel mit web_scrape!
  Also: 5x web_scrape in EINER Antwort (parallel = schneller).
- Fasse Ergebnisse SCHNELL zusammen - der User wartet!
- Wenn die ersten Suchergebnisse ausreichen, hoere auf zu suchen.
- NICHT mehr als 10 web_scrape Aufrufe insgesamt.

ARBEITSVERZEICHNIS: $workspacePath
DATEIEN: ${task.inputFiles.map((f) => p.basename(f)).join(', ')}
${imageRegistry != null && imageRegistry!.images.isNotEmpty ? 'BILDER: ${imageRegistry!.images.map((i) => "${i.id}: ${p.basename(i.filePath)} (${i.source})").join(", ")}' : ''}''';
  }

  String _userPrompt(AgentTask task) {
    final buf = StringBuffer('Aufgabe: ${task.instruction}\n');
    if (task.inputFiles.isNotEmpty) {
      buf.writeln('\nDateien:');
      for (final f in task.inputFiles) {
        buf.writeln('- ${p.basename(f)} (Pfad: $f)');
      }
    }
    return buf.toString();
  }
}

/// Slide data for PPTX generation.
class _PptxSlide {
  String title;
  String subtitle = '';
  final List<String> bullets = [];
  List<int>? imageBytes;
  bool isTitleSlide = false;

  _PptxSlide({required this.title});

  bool get hasImage => imageBytes != null;
  bool get hasBullets => bullets.isNotEmpty;

  /// Detect image aspect ratio from PNG/JPEG header bytes.
  /// Returns width/height ratio (e.g., 1.0 for square, 1.78 for 16:9).
  double get imageAspect {
    final bytes = imageBytes;
    if (bytes == null || bytes.length < 30) return 1.0;
    try {
      // PNG: width at bytes 16-19, height at bytes 20-23 (big-endian)
      if (bytes[0] == 0x89 && bytes[1] == 0x50) {
        final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        if (h > 0) return w / h;
      }
      // JPEG: scan for SOF0/SOF2 marker (0xFF 0xC0 or 0xFF 0xC2)
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        for (var i = 2; i < bytes.length - 10; i++) {
          if (bytes[i] == 0xFF && (bytes[i + 1] == 0xC0 || bytes[i + 1] == 0xC2)) {
            final h = (bytes[i + 5] << 8) | bytes[i + 6];
            final w = (bytes[i + 7] << 8) | bytes[i + 8];
            if (h > 0) return w / h;
          }
        }
      }
    } catch (_) {}
    return 1.0; // Default to square
  }

  /// True if image is roughly square (aspect 0.8–1.2).
  bool get isSquareImage => imageAspect >= 0.8 && imageAspect <= 1.25;
  /// True if image is landscape (wider than 1.25).
  bool get isLandscapeImage => imageAspect > 1.25;
}
