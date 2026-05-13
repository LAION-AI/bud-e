/// PDF utilities — page count estimation, basic text extraction.
/// Designed to be safe for large files (multi-MB PDFs).
library;

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../config/api_config.dart';

// ---------------------------------------------------------------------------
// Byte-level helpers (no full-file String conversion)
// ---------------------------------------------------------------------------

/// Find a byte pattern in [bytes] starting from [start].
int _findBytes(List<int> bytes, List<int> pattern, int start) {
  outer:
  for (var i = start; i <= bytes.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

final _streamMarker = 'stream'.codeUnits;
final _endstreamMarker = 'endstream'.codeUnits;
final _flateDecode = 'FlateDecode'.codeUnits;
final _typePage = '/Type /Page'.codeUnits; // common form
final _typePageAlt = '/Type/Page'.codeUnits; // no space

/// Estimate page count from PDF bytes using byte-level scanning.
int estimatePageCount(List<int> bytes) {
  // Method 1: Find /Count N in the first 10KB (catalog is usually near the start)
  final searchLen = min(bytes.length, 100000);
  final header = String.fromCharCodes(bytes, 0, searchLen);
  final countMatch = RegExp(r'/Count\s*(\d+)').firstMatch(header);
  if (countMatch != null) {
    final count = int.tryParse(countMatch.group(1)!) ?? 0;
    if (count > 0) return count;
  }

  // Method 2: Count /Type /Page occurrences (byte scan)
  int count = 0;
  for (var i = 0; i < bytes.length - 12; i++) {
    // Check for "/Type /Page" or "/Type/Page" NOT followed by "s" (to exclude /Pages)
    if (bytes[i] == 0x2F && // '/'
        bytes[i + 1] == 0x54 && // 'T'
        bytes[i + 2] == 0x79 && // 'y'
        bytes[i + 3] == 0x70 && // 'p'
        bytes[i + 4] == 0x65) {
      // Found "/Type", check what follows
      var j = i + 5;
      // Skip whitespace
      while (j < bytes.length && (bytes[j] == 0x20 || bytes[j] == 0x0A || bytes[j] == 0x0D)) j++;
      if (j < bytes.length - 4 &&
          bytes[j] == 0x2F && // '/'
          bytes[j + 1] == 0x50 && // 'P'
          bytes[j + 2] == 0x61 && // 'a'
          bytes[j + 3] == 0x67 && // 'g'
          bytes[j + 4] == 0x65) { // 'e'
        // Check NOT /Pages
        if (j + 5 >= bytes.length || bytes[j + 5] != 0x73) { // not 's'
          count++;
        }
      }
    }
  }
  if (count > 0) return count;

  // Method 3: rough estimate
  return max(1, bytes.length ~/ 50000);
}

/// Extract text from PDF streams. Safe for large files.
/// Only processes up to [maxPages] pages to avoid memory issues.
Map<int, String> extractTextBasic(List<int> bytes, {int maxPages = 50}) {
  final result = <int, String>{};

  // Find stream/endstream boundaries using byte scanning
  var pos = 0;
  int pageNum = 0;

  while (pos < bytes.length - 20 && pageNum < maxPages) {
    final sIdx = _findBytes(bytes, _streamMarker, pos);
    if (sIdx < 0) break;

    // Make sure this is "stream" not "endstream"
    if (sIdx >= 3 && bytes[sIdx - 1] == 0x64 && bytes[sIdx - 2] == 0x6E && bytes[sIdx - 3] == 0x65) {
      pos = sIdx + 6;
      continue;
    }

    // Skip past "stream\r\n" or "stream\n"
    var dataStart = sIdx + 6;
    if (dataStart < bytes.length && bytes[dataStart] == 0x0D) dataStart++;
    if (dataStart < bytes.length && bytes[dataStart] == 0x0A) dataStart++;

    final eIdx = _findBytes(bytes, _endstreamMarker, dataStart);
    if (eIdx < 0) break;

    var dataEnd = eIdx;
    if (dataEnd > dataStart && bytes[dataEnd - 1] == 0x0A) dataEnd--;
    if (dataEnd > dataStart && bytes[dataEnd - 1] == 0x0D) dataEnd--;

    pos = eIdx + 9;

    // Skip very large streams (images, fonts) — text streams are usually < 50KB
    final streamLen = dataEnd - dataStart;
    if (streamLen <= 0 || streamLen > 200000) continue;

    // Check for FlateDecode in the 300 bytes before "stream"
    final dictStart = max(0, sIdx - 300);
    final dictBytes = bytes.sublist(dictStart, sIdx);
    final isCompressed = _findBytes(dictBytes, _flateDecode, 0) >= 0;

    String streamText;
    final rawBytes = bytes.sublist(dataStart, dataEnd);

    if (isCompressed) {
      try {
        final decompressed = ZLibDecoder().convert(rawBytes);
        streamText = String.fromCharCodes(decompressed);
      } catch (_) {
        continue;
      }
    } else {
      try {
        streamText = String.fromCharCodes(rawBytes);
      } catch (_) {
        continue;
      }
    }

    // Check for text operators
    if (!streamText.contains('Tj') && !streamText.contains('TJ')) continue;
    pageNum++;

    final textBuf = StringBuffer();

    // Extract (text) Tj patterns
    for (final tj in RegExp(r"\(([^)]*)\)\s*Tj").allMatches(streamText)) {
      var text = tj.group(1) ?? '';
      text = _unescapePdf(text);
      textBuf.writeln(text);
    }

    // Extract [(...) ...] TJ patterns
    for (final tjArr in RegExp(r"\[([^\]]*)\]\s*TJ").allMatches(streamText)) {
      final arr = tjArr.group(1) ?? '';
      for (final part in RegExp(r"\(([^)]*)\)").allMatches(arr)) {
        textBuf.write(_unescapePdf(part.group(1) ?? ''));
      }
      textBuf.writeln();
    }

    final pageText = textBuf.toString().trim();
    if (pageText.isNotEmpty) {
      result[pageNum] = pageText;
    }
  }
  return result;
}

String _unescapePdf(String s) => s
    .replaceAll(r'\(', '(')
    .replaceAll(r'\)', ')')
    .replaceAll(r'\\', r'\')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\r', '\r')
    .replaceAll(r'\t', '\t');

// ---------------------------------------------------------------------------
// Tools for the sub-agent
// ---------------------------------------------------------------------------

/// Get PDF info: size, pages, text quality.
Future<String> toolPdfInfo(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) return 'Error: File not found: $filePath';

  try {
    final bytes = await file.readAsBytes();
    final sizeKb = bytes.length / 1024;
    final sizeMb = sizeKb / 1024;
    final pageCount = estimatePageCount(bytes);

    // Only try text extraction for files under 10MB
    int totalChars = 0;
    int textPageCount = 0;
    if (sizeMb < 10) {
      try {
        final textPages = extractTextBasic(bytes, maxPages: 10);
        totalChars = textPages.values.fold(0, (sum, t) => sum + t.length);
        textPageCount = textPages.length;
      } catch (_) {
        // Text extraction failed — that's OK
      }
    }
    final hasText = totalChars > 50;

    return 'PDF Info: ${p.basename(filePath)}\n'
        'Size: ${sizeMb > 1 ? "${sizeMb.toStringAsFixed(1)} MB" : "${sizeKb.toStringAsFixed(0)} KB"}\n'
        'Pages: $pageCount (estimated)\n'
        'Text extracted: $textPageCount pages sampled, $totalChars chars found\n'
        'Type: ${hasText ? "Text-PDF (extractable)" : "Scanned/Image-PDF or complex encoding"}\n'
        'Recommendation: ${_recommendation(pageCount, sizeMb, hasText)}';
  } catch (e) {
    return 'Error reading PDF: $e';
  }
}

String _recommendation(int pages, double sizeMb, bool hasText) {
  if (pages <= 5 && sizeMb < 1) return 'Small PDF - use analyze_pdf_pages directly';
  if (hasText) return 'Use pdf_extract_text in 5-page chunks, then analyze the text';
  if (sizeMb < 1) return 'PDF under 1MB - use analyze_pdf_pages (sends to AI for visual reading)';
  return 'Large/complex PDF - use analyze_pdf_pages with small page ranges (3-5 pages at a time)';
}

/// Extract text from specific pages.
Future<String> toolPdfExtractText(String filePath,
    {int startPage = 1, int endPage = 999}) async {
  final file = File(filePath);
  if (!await file.exists()) return 'Error: File not found: $filePath';

  try {
    final bytes = await file.readAsBytes();
    final textPages = extractTextBasic(bytes, maxPages: endPage);

    if (textPages.isEmpty) {
      return 'No text could be extracted from this PDF. '
          'It may use complex encoding or be scanned. '
          'Use analyze_pdf_pages to send pages to the AI for visual reading/OCR.';
    }

    final buf = StringBuffer();
    for (var i = startPage; i <= min(endPage, textPages.keys.reduce(max)); i++) {
      if (textPages.containsKey(i)) {
        buf.writeln('=== Seite $i ===');
        buf.writeln(textPages[i]);
        buf.writeln();
      }
    }

    if (buf.isEmpty) {
      return 'No text found for pages $startPage-$endPage. '
          'Available pages with text: ${textPages.keys.toList()}';
    }
    return buf.toString();
  } catch (e) {
    return 'Error extracting text: $e';
  }
}

/// Send a PDF to the middleware for AI-based analysis.
/// For large PDFs (>1MB), includes page-focus instruction.
Future<String> toolAnalyzePdfPages(
  String filePath,
  String instruction,
  String universalApiKey, {
  int startPage = 1,
  int endPage = 5,
}) async {
  final url = middlewareUrl(universalApiKey, '/v1/chat/completions');
  if (url == null) return 'Error: Cannot decode middleware URL';

  final file = File(filePath);
  if (!await file.exists()) return 'Error: File not found: $filePath';

  final bytes = await file.readAsBytes();
  final b64 = base64Encode(bytes);
  final fullInstruction = startPage > 1 || endPage < 999
      ? 'Fokussiere dich auf Seiten $startPage bis $endPage. $instruction'
      : instruction;

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
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': fullInstruction},
              {'type': 'input_file', 'data': b64, 'mime_type': 'application/pdf'},
            ],
          },
        ],
      }),
    ).timeout(const Duration(seconds: 180));

    if (response.statusCode == 502 || response.statusCode == 413) {
      return 'Error: PDF too large for direct upload (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Try pdf_extract_text to get the text content instead, '
          'or ask the user to provide a smaller file.';
    }

    if (response.statusCode != 200) {
      return 'Error: HTTP ${response.statusCode}';
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['choices'] as List?)?.firstOrNull
            ?['message']?['content'] as String? ??
        'No analysis returned';
  } catch (e) {
    return 'Error analyzing PDF pages: $e';
  }
}
