/// BM25 search index over Bildungsplan pages.
///
/// Loads JSON index files from the bildungsplaene/ directory,
/// builds an inverted index, and supports keyword search with
/// BM25 ranking. Returns structured results with metadata
/// (Schulform, Fach, Bundesland, Stufe, page number, PDF URL).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'debug_log.dart';

/// A single indexed Bildungsplan page.
class BildungsplanPage {
  final int pageNumber;
  final String content;       // full transcription with inline captions
  final String bundesland;
  final String schulform;
  final String stufe;
  final String fach;
  final String url;           // PDF download URL
  final String pdfFile;       // local filename
  final String imageFile;     // page image filename

  BildungsplanPage({
    required this.pageNumber,
    required this.content,
    required this.bundesland,
    required this.schulform,
    required this.stufe,
    required this.fach,
    required this.url,
    this.pdfFile = '',
    this.imageFile = '',
  });

  /// Human-readable source reference.
  String get sourceRef =>
      '$fach, $schulform, $stufe ($bundesland) — Seite $pageNumber';
}

/// BM25 search result for Bildungsplan pages.
class BildungsplanResult {
  final BildungsplanPage page;
  final double score;

  BildungsplanResult(this.page, this.score);
}

/// BM25 parameters.
const double _k1 = 1.5;
const double _b = 0.75;

class BildungsplanSearch {
  final String _dataDir; // path to bildungsplaene/ directory

  final List<BildungsplanPage> _pages = [];
  final Map<String, Map<int, int>> _index = {}; // term → {pageIdx: freq}
  final List<int> _pageLengths = [];
  double _avgLen = 0;
  bool _built = false;

  BildungsplanSearch(this._dataDir);

  bool get isBuilt => _built;
  int get pageCount => _pages.length;

  /// Available Fächer (subjects) in the index.
  Set<String> get availableFaecher =>
      _pages.map((p) => p.fach).toSet();

  /// Available Schulformen in the index.
  Set<String> get availableSchulformen =>
      _pages.map((p) => p.schulform).toSet();

  /// Build index from all JSON files in the data directory.
  Future<void> buildIndex() async {
    _pages.clear();
    _index.clear();
    _pageLengths.clear();

    final dir = Directory(_dataDir);
    if (!await dir.exists()) {
      debugLog(DebugSource.memory, 'Bildungsplan dir not found: $_dataDir');
      return;
    }

    // Find all JSON index files
    final jsonFiles = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();

    debugLog(DebugSource.memory,
        'Bildungsplan: found ${jsonFiles.length} index files');

    for (final file in jsonFiles) {
      try {
        final content = await file.readAsString(encoding: utf8);
        final data = jsonDecode(content) as Map<String, dynamic>;
        final meta = data['metadata'] as Map<String, dynamic>? ?? {};
        final pages = data['pages'] as List? ?? [];

        for (final pageData in pages) {
          final page = pageData as Map<String, dynamic>;
          _pages.add(BildungsplanPage(
            pageNumber: page['page_number'] as int? ?? 0,
            content: page['content'] as String? ?? '',
            bundesland: page['bundesland'] as String? ??
                meta['bundesland'] as String? ?? '',
            schulform: page['schulform'] as String? ??
                meta['schulform'] as String? ?? '',
            stufe: page['stufe'] as String? ??
                meta['stufe'] as String? ?? '',
            fach: page['fach'] as String? ??
                meta['fach'] as String? ?? '',
            url: page['url'] as String? ??
                meta['url'] as String? ?? '',
            pdfFile: meta['pdf_file'] as String? ?? p.basename(file.path),
            imageFile: page['image_file'] as String? ?? '',
          ));
        }
      } catch (e) {
        debugLog(DebugSource.memory, 'Error loading ${file.path}: $e');
      }
    }

    // Build inverted index
    var totalLen = 0;
    for (var i = 0; i < _pages.length; i++) {
      // Index content + metadata for searchability
      final searchText = '${_pages[i].content} ${_pages[i].fach} '
          '${_pages[i].schulform} ${_pages[i].stufe}';
      final terms = _tokenize(searchText);
      _pageLengths.add(terms.length);
      totalLen += terms.length;

      final freq = <String, int>{};
      for (final t in terms) {
        freq[t] = (freq[t] ?? 0) + 1;
      }
      for (final entry in freq.entries) {
        _index.putIfAbsent(entry.key, () => {});
        _index[entry.key]![i] = entry.value;
      }
    }
    _avgLen = _pages.isEmpty ? 1 : totalLen / _pages.length;
    _built = true;

    debugLog(DebugSource.memory,
        'Bildungsplan BM25: ${_pages.length} pages, ${_index.length} terms, '
        '${availableFaecher.length} Fächer');
  }

  /// Search with BM25 ranking. Optionally filter by Fach/Schulform.
  List<BildungsplanResult> search(
    String query, {
    int limit = 10,
    String? fach,
    String? schulform,
    String? stufe,
  }) {
    if (!_built || _pages.isEmpty) return [];

    final queryTerms = _tokenize(query);
    if (queryTerms.isEmpty) return [];

    final scores = List<double>.filled(_pages.length, 0);
    final n = _pages.length;

    for (final term in queryTerms) {
      final postings = _index[term];
      if (postings == null) continue;

      final df = postings.length;
      final idf = log((n - df + 0.5) / (df + 0.5) + 1);

      for (final entry in postings.entries) {
        final idx = entry.key;
        final tf = entry.value;
        final docLen = _pageLengths[idx];
        final tfNorm =
            (tf * (_k1 + 1)) / (tf + _k1 * (1 - _b + _b * docLen / _avgLen));
        scores[idx] += idf * tfNorm;
      }
    }

    // Collect, filter, and sort
    final results = <BildungsplanResult>[];
    for (var i = 0; i < scores.length; i++) {
      if (scores[i] <= 0) continue;
      final page = _pages[i];

      // Apply optional filters
      if (fach != null && !page.fach.toLowerCase().contains(fach.toLowerCase())) continue;
      if (schulform != null && !page.schulform.toLowerCase().contains(schulform.toLowerCase())) continue;
      if (stufe != null && !page.stufe.toLowerCase().contains(stufe.toLowerCase())) continue;

      results.add(BildungsplanResult(page, scores[i]));
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }

  /// Tokenize German text — keeps umlauts, digits, and common chars.
  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\wäöüß\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toList();
  }
}
