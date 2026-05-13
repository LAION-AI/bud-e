/// BM25 search index over all memory files (semantic, episodic, procedural).
///
/// Builds an in-memory inverted index from JSON files on disk.
/// Supports keyword search with BM25 ranking.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'file_storage_service.dart';
import 'debug_log.dart';

/// A single indexed document.
class IndexedDoc {
  final String path;       // relative path to JSON file
  final String category;   // semantic_memory / episodic_memory / etc.
  final String text;       // searchable text content
  final Map<String, dynamic> data;  // original parsed JSON

  IndexedDoc({
    required this.path,
    required this.category,
    required this.text,
    required this.data,
  });
}

/// BM25 search result.
class SearchResult {
  final IndexedDoc doc;
  final double score;

  SearchResult(this.doc, this.score);
}

/// BM25 parameters.
const double _k1 = 1.5;
const double _b = 0.75;

class MemorySearch {
  final FileStorageService _storage;
  final List<IndexedDoc> _docs = [];
  final Map<String, Map<int, int>> _invertedIndex = {}; // term → {docIdx: freq}
  final List<int> _docLengths = []; // cached token counts per doc
  double _avgDocLen = 0;
  bool _built = false;
  bool _dirty = true; // set true when memory files change

  MemorySearch(this._storage);

  bool get isBuilt => _built;
  int get docCount => _docs.length;

  /// Rebuild the index from all memory JSON files.
  /// Mark the index as dirty (call after memory files change).
  void markDirty() => _dirty = true;

  /// Rebuild only if dirty. Call before search.
  Future<void> ensureFresh() async {
    if (_dirty) await buildIndex();
  }

  Future<void> buildIndex() async {
    _docs.clear();
    _invertedIndex.clear();
    _docLengths.clear();

    // Parallel: read all dirs at once
    final dirs = ['semantic_memory', 'episodic_memory', 'working_memory'];
    final allFiles = <File>[];
    final allDirs = <String>[];
    for (final dir in dirs) {
      final entries = await _storage.listDirectory(dir);
      for (final entity in entries) {
        if (entity is File && entity.path.endsWith('.json')) {
          allFiles.add(entity);
          allDirs.add(dir);
        }
      }
    }

    // Parallel read all files
    final contents = await Future.wait(
      allFiles.map((f) => f.readAsString(encoding: utf8).catchError((_) => '')),
    );

    for (var i = 0; i < allFiles.length; i++) {
      if (contents[i].isEmpty) continue;
      try {
        final data = jsonDecode(contents[i]) as Map<String, dynamic>;
        final relPath = p.relative(allFiles[i].path, from: _storage.rootPath);
        final text = _extractText(data);
        _docs.add(IndexedDoc(path: relPath, category: allDirs[i], text: text, data: data));
      } catch (_) {}
    }

    // Build inverted index + cache doc lengths
    var totalLen = 0;
    for (var i = 0; i < _docs.length; i++) {
      final terms = _tokenize(_docs[i].text);
      _docLengths.add(terms.length);
      totalLen += terms.length;
      final freq = <String, int>{};
      for (final t in terms) {
        freq[t] = (freq[t] ?? 0) + 1;
      }
      for (final entry in freq.entries) {
        _invertedIndex.putIfAbsent(entry.key, () => {});
        _invertedIndex[entry.key]![i] = entry.value;
      }
    }
    _avgDocLen = _docs.isEmpty ? 1 : totalLen / _docs.length;
    _built = true;
    _dirty = false;

    debugLog(DebugSource.memory,
        'BM25 index: ${_docs.length} docs, ${_invertedIndex.length} terms');
  }

  /// Search with BM25 ranking. Returns top [limit] results.
  List<SearchResult> search(String query, {int limit = 10}) {
    if (!_built || _docs.isEmpty) return [];

    final queryTerms = _tokenize(query);
    if (queryTerms.isEmpty) return [];

    final scores = List<double>.filled(_docs.length, 0);
    final n = _docs.length;

    for (final term in queryTerms) {
      final postings = _invertedIndex[term];
      if (postings == null) continue;

      final df = postings.length;
      final idf = log((n - df + 0.5) / (df + 0.5) + 1);

      for (final entry in postings.entries) {
        final docIdx = entry.key;
        final tf = entry.value;
        final docLen = _docLengths[docIdx];
        final tfNorm = (tf * (_k1 + 1)) /
            (tf + _k1 * (1 - _b + _b * docLen / _avgDocLen));
        scores[docIdx] += idf * tfNorm;
      }
    }

    // Collect and sort
    final results = <SearchResult>[];
    for (var i = 0; i < scores.length; i++) {
      if (scores[i] > 0) {
        results.add(SearchResult(_docs[i], scores[i]));
      }
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }

  /// Extract all searchable text from a JSON document.
  String _extractText(Map<String, dynamic> data) {
    final buf = StringBuffer();
    _walkJson(data, buf);
    return buf.toString();
  }

  void _walkJson(dynamic value, StringBuffer buf) {
    if (value is String) {
      buf.write(value);
      buf.write(' ');
    } else if (value is Map) {
      for (final v in value.values) {
        _walkJson(v, buf);
      }
    } else if (value is List) {
      for (final v in value) {
        _walkJson(v, buf);
      }
    }
  }

  /// Tokenize text into lowercase terms, stripping punctuation.
  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toList();
  }
}
