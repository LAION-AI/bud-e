/// Persona Import/Export — ZIP-based persona archiving.
///
/// Exports all persona data (personality, memories, conversations,
/// workspace files, skills) as a single ZIP file.
/// Imports from a ZIP file, replacing or merging with existing data.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'file_storage_service.dart';
import 'debug_log.dart';

class PersonaIO {
  final FileStorageService storage;

  PersonaIO(this.storage);

  /// Export the complete persona as a ZIP file.
  /// Includes: personality, settings, semantic_memory, episodic_memory,
  /// working_memory, conversations, agent_workspace, bildungsplaene.
  Future<Uint8List> exportZip() async {
    final root = storage.rootPath;
    final files = <String, List<int>>{};

    // Collect all files from persona directories
    final dirs = [
      'semantic_memory',
      'episodic_memory',
      'working_memory',
      'conversations',
      'agent_workspace',
    ];

    // Add personality and settings
    for (final name in ['personality.json', 'settings.json']) {
      final file = File(p.join(root, name));
      if (await file.exists()) {
        // Strip API key from settings for security
        if (name == 'settings.json') {
          final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          data.remove('universalApiKey');
          files[name] = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
        } else {
          files[name] = await file.readAsBytes();
        }
      }
    }

    // Add memory and workspace directories
    for (final dirName in dirs) {
      final dir = Directory(p.join(root, dirName));
      if (!await dir.exists()) continue;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final relPath = p.relative(entity.path, from: root).replaceAll('\\', '/');
          // Skip large binary files in workspace (images, etc.)
          final size = await entity.length();
          if (size > 5 * 1024 * 1024) continue; // skip files > 5MB
          try {
            files[relPath] = await entity.readAsBytes();
          } catch (_) {}
        }
      }
    }

    debugLog(DebugSource.system, 'Persona export: ${files.length} files');
    return _createZip(files);
  }

  /// Import a persona from a ZIP file.
  /// Replaces existing data in the target directories.
  Future<int> importZip(Uint8List zipBytes) async {
    final root = storage.rootPath;
    final entries = _extractZip(zipBytes);

    var count = 0;
    for (final entry in entries.entries) {
      final targetPath = p.join(root, entry.key);
      final dir = Directory(p.dirname(targetPath));
      if (!await dir.exists()) await dir.create(recursive: true);

      // Don't overwrite the API key
      if (entry.key == 'settings.json') {
        try {
          final imported = jsonDecode(utf8.decode(entry.value)) as Map<String, dynamic>;
          final existing = File(p.join(root, 'settings.json'));
          if (await existing.exists()) {
            final current = jsonDecode(await existing.readAsString()) as Map<String, dynamic>;
            // Keep current API key
            imported['universalApiKey'] = current['universalApiKey'];
          }
          await File(targetPath).writeAsString(
              const JsonEncoder.withIndent('  ').convert(imported));
        } catch (_) {}
      } else {
        await File(targetPath).writeAsBytes(entry.value);
      }
      count++;
    }

    debugLog(DebugSource.system, 'Persona import: $count files extracted');
    return count;
  }

  // ── ZIP creation (minimal, no compression) ──

  Uint8List _createZip(Map<String, List<int>> files) {
    final out = BytesBuilder();
    final cd = BytesBuilder();
    var n = 0;
    for (final e in files.entries) {
      final name = utf8.encode(e.key);
      final data = Uint8List.fromList(e.value);
      final crc = _crc32(data);
      final off = out.length;
      out.add(_u32(0x04034B50));
      out.add(_u16(20)); out.add(_u16(0)); out.add(_u16(0));
      out.add(_u16(0)); out.add(_u16(0));
      out.add(_u32(crc)); out.add(_u32(data.length)); out.add(_u32(data.length));
      out.add(_u16(name.length)); out.add(_u16(0));
      out.add(name); out.add(data);
      cd.add(_u32(0x02014B50));
      cd.add(_u16(20)); cd.add(_u16(20)); cd.add(_u16(0)); cd.add(_u16(0));
      cd.add(_u16(0)); cd.add(_u16(0));
      cd.add(_u32(crc)); cd.add(_u32(data.length)); cd.add(_u32(data.length));
      cd.add(_u16(name.length)); cd.add(_u16(0)); cd.add(_u16(0));
      cd.add(_u16(0)); cd.add(_u16(0)); cd.add(_u32(0)); cd.add(_u32(off));
      cd.add(name);
      n++;
    }
    final cdOff = out.length;
    final cdData = cd.toBytes();
    out.add(cdData);
    out.add(_u32(0x06054B50));
    out.add(_u16(0)); out.add(_u16(0));
    out.add(_u16(n)); out.add(_u16(n));
    out.add(_u32(cdData.length)); out.add(_u32(cdOff)); out.add(_u16(0));
    return out.toBytes();
  }

  // ── ZIP extraction ──

  Map<String, Uint8List> _extractZip(Uint8List bytes) {
    final result = <String, Uint8List>{};
    var i = 0;
    while (i + 30 <= bytes.length) {
      final sig = bytes.buffer.asByteData().getUint32(i, Endian.little);
      if (sig != 0x04034B50) break;
      final nameLen = bytes.buffer.asByteData().getUint16(i + 26, Endian.little);
      final extraLen = bytes.buffer.asByteData().getUint16(i + 28, Endian.little);
      final compSize = bytes.buffer.asByteData().getUint32(i + 18, Endian.little);
      final name = utf8.decode(bytes.sublist(i + 30, i + 30 + nameLen));
      final dataStart = i + 30 + nameLen + extraLen;
      if (dataStart + compSize <= bytes.length) {
        result[name] = Uint8List.fromList(bytes.sublist(dataStart, dataStart + compSize));
      }
      i = dataStart + compSize;
    }
    return result;
  }

  Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
  Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
  int _crc32(Uint8List d) {
    var c = 0xFFFFFFFF;
    for (final b in d) { c ^= b; for (var j = 0; j < 8; j++) c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1; }
    return c ^ 0xFFFFFFFF;
  }
}
