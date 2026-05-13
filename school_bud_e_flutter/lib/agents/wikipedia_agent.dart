/// Wikipedia search agent.
///
/// Provides summary, abstract, or full article retrieval from Wikipedia.
/// Tool syntax: [[tool:wikipedia query="search terms" depth="summary|abstract|full"]]
/// Default depth is "summary" (first paragraph).
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/debug_log.dart';

class WikipediaResult {
  final String title;
  final String summary;
  final String? fullExtract;
  final String url;
  final int charCount;

  WikipediaResult({
    required this.title,
    required this.summary,
    this.fullExtract,
    required this.url,
    required this.charCount,
  });
}

class WikipediaAgent {
  /// Search Wikipedia and return results.
  ///
  /// [lang] — Wikipedia language code (de, en, etc.)
  /// [depth] — "summary" (first ~500 chars), "abstract" (~2000 chars), "full" (up to 10k chars)
  Future<WikipediaResult?> search(
    String query, {
    String lang = 'de',
    String depth = 'summary',
  }) async {
    debugLog(DebugSource.mainAgent,
        'Wikipedia search: "$query" (lang=$lang, depth=$depth)');

    try {
      // Step 1: Search for the article title
      final searchUrl = Uri.parse(
        'https://$lang.wikipedia.org/w/api.php'
        '?action=query&list=search&srsearch=${Uri.encodeComponent(query)}'
        '&srlimit=1&format=json&origin=*',
      );

      final searchResp = await http.get(searchUrl)
          .timeout(const Duration(seconds: 10));
      if (searchResp.statusCode != 200) {
        debugLog(DebugSource.mainAgent,
            'Wikipedia search failed: ${searchResp.statusCode}');
        return null;
      }

      final searchData = jsonDecode(searchResp.body) as Map<String, dynamic>;
      final results = (searchData['query']?['search'] as List?) ?? [];
      if (results.isEmpty) {
        debugLog(DebugSource.mainAgent, 'Wikipedia: no results for "$query"');
        return null;
      }

      final title = results[0]['title'] as String;

      // Step 2: Get the article extract
      final maxChars = switch (depth) {
        'full' => 10000,
        'abstract' => 2000,
        _ => 500,  // summary
      };

      final extractUrl = Uri.parse(
        'https://$lang.wikipedia.org/w/api.php'
        '?action=query&titles=${Uri.encodeComponent(title)}'
        '&prop=extracts&exchars=$maxChars&explaintext=1'
        '&exintro=${depth == 'summary' || depth == 'abstract' ? '1' : '0'}'
        '&format=json&origin=*',
      );

      final extractResp = await http.get(extractUrl)
          .timeout(const Duration(seconds: 10));
      if (extractResp.statusCode != 200) return null;

      final extractData = jsonDecode(extractResp.body) as Map<String, dynamic>;
      final pages = extractData['query']?['pages'] as Map<String, dynamic>?;
      if (pages == null || pages.isEmpty) return null;

      final page = pages.values.first as Map<String, dynamic>;
      final extract = page['extract'] as String? ?? '';
      final articleUrl = 'https://$lang.wikipedia.org/wiki/'
          '${Uri.encodeComponent(title.replaceAll(' ', '_'))}';

      debugLog(DebugSource.mainAgent,
          'Wikipedia: "$title" — ${extract.length} chars');

      return WikipediaResult(
        title: title,
        summary: extract.length > 500
            ? extract.substring(0, 500)
            : extract,
        fullExtract: extract,
        url: articleUrl,
        charCount: extract.length,
      );
    } catch (e) {
      debugLog(DebugSource.mainAgent, 'Wikipedia error: $e');
      return null;
    }
  }
}
