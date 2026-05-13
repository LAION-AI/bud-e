/// File operation tools for the sub-agent.
library;

import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;

/// Read a file and return its contents.
/// Handles text files, DOCX (extracts text from XML), and binary info.
Future<String> toolReadFile(String path, String workspacePath) async {
  final resolved = _resolvePath(path, workspacePath);
  final file = File(resolved);
  if (!await file.exists()) return 'Error: File not found: $path';

  final ext = p.extension(resolved).toLowerCase();

  // DOCX: extract text from the ZIP/XML
  if (ext == '.docx') {
    return _readDocx(resolved);
  }

  // Binary files: just report info
  if ({'.pdf', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp',
       '.mp3', '.wav', '.ogg', '.m4a', '.zip', '.exe'}.contains(ext)) {
    final size = await file.length();
    return 'Binary file: $path ($ext, ${_humanSize(size)})\n'
        'Cannot read as text. Use analyze_document for PDFs/images.';
  }

  // Text files
  try {
    final content = await file.readAsString();
    if (content.length > 50000) {
      return 'File: $path ($ext, ${content.length} chars, truncated)\n---\n'
          '${content.substring(0, 50000)}\n...(truncated)';
    }
    return 'File: $path ($ext, ${content.length} chars)\n---\n$content';
  } catch (e) {
    // Maybe binary file we didn't recognize
    final size = await file.length();
    return 'Cannot read as text: $path ($ext, ${_humanSize(size)}). Error: $e';
  }
}

/// Extract text content from a DOCX file.
Future<String> _readDocx(String filePath) async {
  try {
    final bytes = await File(filePath).readAsBytes();

    // DOCX is a ZIP file — find word/document.xml
    // Simple ZIP parsing: look for the file entry
    final content = _extractFileFromZip(bytes, 'word/document.xml');
    if (content == null) {
      return 'Error: Could not find document.xml in DOCX file';
    }

    final xml = utf8.decode(content);

    // Extract text from OOXML: find all <w:t>...</w:t> elements
    final textBuf = StringBuffer();
    final tRegex = RegExp(r'<w:t[^>]*>([^<]*)</w:t>');
    final pEnd = RegExp(r'</w:p>');

    var lastEnd = 0;
    // Process paragraph by paragraph
    for (final pMatch in pEnd.allMatches(xml)) {
      final segment = xml.substring(lastEnd, pMatch.end);
      final lineTexts = <String>[];
      for (final m in tRegex.allMatches(segment)) {
        lineTexts.add(m.group(1)!);
      }
      if (lineTexts.isNotEmpty) {
        textBuf.writeln(lineTexts.join());
      }
      lastEnd = pMatch.end;
    }

    final text = textBuf.toString().trim();
    if (text.isEmpty) {
      return 'DOCX file: ${p.basename(filePath)} (no text content found)';
    }
    return 'DOCX file: ${p.basename(filePath)} (${text.length} chars)\n---\n$text';
  } catch (e) {
    return 'Error reading DOCX: $e';
  }
}

/// Extract a file from a ZIP archive (minimal parser).
List<int>? _extractFileFromZip(List<int> zipBytes, String targetName) {
  var pos = 0;
  final targetNameBytes = utf8.encode(targetName);

  while (pos < zipBytes.length - 30) {
    // Local file header signature: PK\x03\x04
    if (zipBytes[pos] != 0x50 || zipBytes[pos + 1] != 0x4B ||
        zipBytes[pos + 2] != 0x03 || zipBytes[pos + 3] != 0x04) {
      pos++;
      continue;
    }

    final compMethod = zipBytes[pos + 8] | (zipBytes[pos + 9] << 8);
    final compSize = zipBytes[pos + 18] | (zipBytes[pos + 19] << 8) |
        (zipBytes[pos + 20] << 16) | (zipBytes[pos + 21] << 24);
    final uncompSize = zipBytes[pos + 22] | (zipBytes[pos + 23] << 8) |
        (zipBytes[pos + 24] << 16) | (zipBytes[pos + 25] << 24);
    final nameLen = zipBytes[pos + 26] | (zipBytes[pos + 27] << 8);
    final extraLen = zipBytes[pos + 28] | (zipBytes[pos + 29] << 8);

    final nameStart = pos + 30;
    final nameEnd = nameStart + nameLen;
    if (nameEnd > zipBytes.length) break;

    final name = utf8.decode(zipBytes.sublist(nameStart, nameEnd));
    final dataStart = nameEnd + extraLen;
    final dataEnd = dataStart + compSize;

    if (name == targetName && dataEnd <= zipBytes.length) {
      if (compMethod == 0) {
        // Stored (no compression)
        return zipBytes.sublist(dataStart, dataEnd);
      } else if (compMethod == 8) {
        // Deflate
        try {
          return ZLibDecoder(raw: true)
              .convert(zipBytes.sublist(dataStart, dataEnd));
        } catch (_) {
          return null;
        }
      }
    }

    pos = dataEnd > pos + 30 ? dataEnd : pos + 30 + nameLen;
  }
  return null;
}

/// Write content to a file.
Future<String> toolWriteFile(
    String path, String content, String workspacePath) async {
  final resolved = _resolvePath(path, workspacePath);
  try {
    final dir = Directory(p.dirname(resolved));
    if (!await dir.exists()) await dir.create(recursive: true);
    await File(resolved).writeAsString(content);
    return 'File written: $path (${content.length} chars)';
  } catch (e) {
    return 'Error writing file: $e';
  }
}

/// List files in the workspace directory.
Future<String> toolListFiles(String workspacePath,
    {String subDir = ''}) async {
  final dir = Directory(
      subDir.isEmpty ? workspacePath : p.join(workspacePath, subDir));
  if (!await dir.exists()) return 'Directory is empty or does not exist.';

  try {
    final entries = await dir.list().toList();
    if (entries.isEmpty) return 'Directory is empty.';

    final buf = StringBuffer(
        'Files in ${subDir.isEmpty ? "workspace" : subDir}:\n');
    for (final e in entries) {
      final name = p.basename(e.path);
      if (e is File) {
        final size = await e.length();
        buf.writeln('  [FILE] $name (${_humanSize(size)})');
      } else if (e is Directory) {
        buf.writeln('  [DIR]  $name/');
      }
    }
    return buf.toString();
  } catch (e) {
    return 'Error listing files: $e';
  }
}

String _resolvePath(String path, String workspacePath) {
  if (p.isAbsolute(path)) return path;
  return p.join(workspacePath, path);
}

String _humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
