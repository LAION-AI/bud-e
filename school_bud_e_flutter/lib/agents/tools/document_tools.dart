/// Document analysis tools — sends PDFs/images to middleware for LLM analysis.
library;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../config/api_config.dart';

/// Analyze a document (PDF, image) by sending it to the middleware.
/// The middleware routes to a VLM (Gemini) that can read PDFs natively.
Future<String> toolAnalyzeDocument(
  String filePath,
  String instruction,
  String universalApiKey, {
  String? pageRange,
}) async {
  final url = middlewareUrl(universalApiKey, '/v1/chat/completions');
  if (url == null) return 'Error: Cannot decode middleware URL';

  final file = File(filePath);
  if (!await file.exists()) return 'Error: File not found: $filePath';

  final bytes = await file.readAsBytes();
  final base64Data = base64Encode(bytes);
  final ext = p.extension(filePath).toLowerCase();
  final mimeType = _mimeForExt(ext);

  final contentParts = <Map<String, dynamic>>[
    {'type': 'text', 'text': instruction},
  ];

  if (ext == '.pdf') {
    contentParts.add({
      'type': 'input_file',
      'data': base64Data,
      'mime_type': mimeType,
    });
  } else if (_isImage(ext)) {
    contentParts.add({
      'type': 'image_url',
      'image_url': {'url': 'data:$mimeType;base64,$base64Data'},
    });
  } else {
    // Text file — just include as text
    try {
      final text = await file.readAsString();
      contentParts[0] = {
        'type': 'text',
        'text': '$instruction\n\n--- File: ${p.basename(filePath)} ---\n$text',
      };
    } catch (_) {
      return 'Error: Cannot read file as text: $filePath';
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
        'messages': [
          {'role': 'user', 'content': contentParts},
        ],
      }),
    ).timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      return 'Document analysis error: HTTP ${response.statusCode}: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}';
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      return (choices[0]['message']['content'] as String?) ??
          'No analysis returned';
    }
    return 'No analysis returned';
  } catch (e) {
    return 'Document analysis error: $e';
  }
}

String _mimeForExt(String ext) {
  return switch (ext) {
    '.pdf' => 'application/pdf',
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.svg' => 'image/svg+xml',
    _ => 'application/octet-stream',
  };
}

bool _isImage(String ext) =>
    {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'}.contains(ext);
