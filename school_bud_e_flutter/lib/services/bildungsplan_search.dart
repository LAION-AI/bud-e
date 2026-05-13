/// BM25 search index over Bildungsplan pages.
///
/// Uses BM25 ranking (same parameters as zvec/dashtext: k1=1.2, b=0.75)
/// with German-aware tokenization. Returns structured results with metadata
/// (Schulform, Fach, Bundesland, Stufe, page number, PDF URL) and
/// highlighted snippets for citation.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'debug_log.dart';

/// A single indexed Bildungsplan page.
class BildungsplanPage {
  final int pageNumber;
  final String content;
  final String bundesland;
  final String schulform;
  final String stufe;
  final String fach;
  final String url;
  final String pdfFile;
  final String imageFile;

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

  String get sourceRef =>
      '$fach, $schulform, $stufe ($bundesland) — Seite $pageNumber';

  /// Direct link to the PDF page.
  String get pdfPageLink => url.isNotEmpty
      ? '$url#page=$pageNumber' : '';
}

/// BM25 search result with snippet extraction.
class BildungsplanResult {
  final BildungsplanPage page;
  final double score;
  final String snippet; // relevant excerpt with query terms highlighted

  BildungsplanResult(this.page, this.score, {this.snippet = ''});
}

/// German stopwords to skip during indexing.
const _stopwords = <String>{
  'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einer', 'eines',
  'und', 'oder', 'aber', 'als', 'auch', 'auf', 'aus', 'bei', 'bis', 'dass',
  'durch', 'fuer', 'für', 'gegen', 'haben', 'hat', 'ich', 'ihr', 'ihre',
  'ihrem', 'ihren', 'ihrer', 'ihm', 'ihn', 'im', 'in', 'ist', 'kann',
  'kein', 'keine', 'mit', 'nach', 'nicht', 'noch', 'nur', 'sie', 'sind',
  'so', 'ueber', 'über', 'um', 'von', 'vor', 'was', 'wenn', 'wer', 'wie',
  'wir', 'wird', 'zu', 'zum', 'zur', 'werden', 'diese', 'dieser', 'dieses',
  'diesem', 'diesen', 'es', 'er', 'man', 'sich', 'sein', 'seine', 'seinem',
  'seinen', 'seiner', 'vom', 'were', 'been', 'the', 'and', 'for',
  'that', 'with', 'are', 'this', 'from', 'have', 'has', 'will',
  'can', 'which', 'their', 'would', 'each', 'more', 'also',
};

/// BM25 parameters — aligned with zvec/dashtext defaults.
const double _k1 = 1.2;
const double _b = 0.75;

class BildungsplanSearch {
  final String _dataDir;

  final List<BildungsplanPage> _pages = [];
  final Map<String, Map<int, int>> _index = {}; // term → {pageIdx: freq}
  final List<int> _pageLengths = [];
  double _avgLen = 0;
  bool _built = false;

  BildungsplanSearch(this._dataDir);

  bool get isBuilt => _built;
  int get pageCount => _pages.length;

  Set<String> get availableFaecher => _pages.map((p) => p.fach).toSet();
  Set<String> get availableSchulformen => _pages.map((p) => p.schulform).toSet();

  Future<void> buildIndex() async {
    _pages.clear();
    _index.clear();
    _pageLengths.clear();

    final dir = Directory(_dataDir);
    if (!await dir.exists()) {
      debugLog(DebugSource.memory, 'Bildungsplan dir not found: $_dataDir');
      return;
    }

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

  /// Search with BM25 ranking. Returns results with relevant snippets.
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

    final results = <BildungsplanResult>[];
    for (var i = 0; i < scores.length; i++) {
      if (scores[i] <= 0) continue;
      final page = _pages[i];

      if (fach != null && !page.fach.toLowerCase().contains(fach.toLowerCase())) continue;
      if (schulform != null && !page.schulform.toLowerCase().contains(schulform.toLowerCase())) continue;
      if (stufe != null && !page.stufe.toLowerCase().contains(stufe.toLowerCase())) continue;

      final snippet = _extractSnippet(page.content, queryTerms);
      results.add(BildungsplanResult(page, scores[i], snippet: snippet));
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }

  /// Extract the most relevant text snippet containing query terms.
  /// Returns ~300 chars of context around the best-matching region.
  String _extractSnippet(String content, List<String> queryTerms) {
    final lower = content.toLowerCase();
    // Find the position with the highest density of query terms
    int bestPos = 0;
    int bestScore = 0;

    // Slide a window of ~300 chars across the content
    const windowSize = 300;
    for (var pos = 0; pos < content.length; pos += 50) {
      final end = (pos + windowSize).clamp(0, content.length);
      final window = lower.substring(pos, end);
      var score = 0;
      for (final term in queryTerms) {
        // Count occurrences in window
        var idx = 0;
        while ((idx = window.indexOf(term, idx)) != -1) {
          score++;
          idx += term.length;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestPos = pos;
      }
    }

    // Extract snippet with some padding
    final start = (bestPos - 20).clamp(0, content.length);
    final end = (bestPos + windowSize + 20).clamp(0, content.length);
    var snippet = content.substring(start, end).trim();

    // Clean up: start/end at word boundaries
    if (start > 0) {
      final firstSpace = snippet.indexOf(' ');
      if (firstSpace > 0 && firstSpace < 30) {
        snippet = '...${snippet.substring(firstSpace + 1)}';
      }
    }
    if (end < content.length) snippet = '$snippet...';

    // Remove BILD-BESCHREIBUNG tags for cleaner output
    snippet = snippet.replaceAll(RegExp(r'\[BILD-BESCHREIBUNG:[^\]]*\]'), '[Grafik]');

    return snippet;
  }

  /// Tokenize German text with stopword removal.
  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll('ä', 'ae').replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue').replaceAll('ß', 'ss')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2 && !_stopwords.contains(t))
        .toList();
  }
}
