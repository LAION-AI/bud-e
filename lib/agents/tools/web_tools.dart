/// Web tools for the sub-agent: search, weather, news.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Search Wikipedia (German or English).
Future<String> toolWikipedia(String query, {String lang = 'de'}) async {
  try {
    final uri = Uri.parse(
        'https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(query)}');
    final response = await http.get(uri, headers: {
      'User-Agent': 'SchoolBudE/1.0',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode == 404) {
      // Try search API instead
      return await _wikiSearch(query, lang: lang);
    }
    if (response.statusCode != 200) return 'Wikipedia: Error ${response.statusCode}';

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final title = data['title'] ?? query;
    final extract = data['extract'] ?? 'No content';
    final url = data['content_urls']?['desktop']?['page'] ?? '';
    return 'Wikipedia: $title\nURL: $url\n---\n$extract';
  } catch (e) {
    return 'Wikipedia error: $e';
  }
}

Future<String> _wikiSearch(String query, {String lang = 'de'}) async {
  try {
    final uri = Uri.parse(
        'https://$lang.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(query)}&format=json&srlimit=3');
    final response = await http.get(uri, headers: {
      'User-Agent': 'SchoolBudE/1.0',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return 'Wikipedia search: Error ${response.statusCode}';

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (data['query']?['search'] as List?) ?? [];
    if (results.isEmpty) return 'Wikipedia: No results for "$query"';

    final buf = StringBuffer('Wikipedia search results for "$query":\n');
    for (final r in results) {
      final title = r['title'] ?? '';
      final snippet = (r['snippet'] as String?)
              ?.replaceAll(RegExp(r'<[^>]+>'), '') ??
          '';
      buf.writeln('- $title: $snippet');
    }
    return buf.toString();
  } catch (e) {
    return 'Wikipedia search error: $e';
  }
}

/// Get current weather using wttr.in (free, no API key needed).
Future<String> toolWeather(String location) async {
  try {
    final uri = Uri.parse(
        'https://wttr.in/${Uri.encodeComponent(location)}?format=j1');
    final response = await http.get(uri, headers: {
      'User-Agent': 'SchoolBudE/1.0',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return 'Weather: Error ${response.statusCode}';

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = (data['current_condition'] as List?)?.firstOrNull
        as Map<String, dynamic>?;
    if (current == null) return 'Weather: No data for "$location"';

    final temp = current['temp_C'] ?? '?';
    final feelsLike = current['FeelsLikeC'] ?? '?';
    final desc = (current['weatherDesc'] as List?)
            ?.firstOrNull?['value'] ??
        'Unknown';
    final humidity = current['humidity'] ?? '?';
    final wind = current['windspeedKmph'] ?? '?';
    final windDir = current['winddir16Point'] ?? '';

    final buf = StringBuffer('Weather for $location:\n');
    buf.writeln('Temperature: ${temp}C (feels like ${feelsLike}C)');
    buf.writeln('Condition: $desc');
    buf.writeln('Humidity: $humidity%');
    buf.writeln('Wind: $wind km/h $windDir');

    // Forecast
    final forecast = data['weather'] as List?;
    if (forecast != null && forecast.isNotEmpty) {
      buf.writeln('\nForecast:');
      for (final day in forecast.take(3)) {
        final date = day['date'] ?? '';
        final maxT = day['maxtempC'] ?? '?';
        final minT = day['mintempC'] ?? '?';
        buf.writeln('  $date: ${minT}C - ${maxT}C');
      }
    }
    return buf.toString();
  } catch (e) {
    return 'Weather error: $e';
  }
}

/// Get latest news from tagesschau.de API.
Future<String> toolTagesschauNews({String? topic}) async {
  try {
    final uri = topic != null && topic.isNotEmpty
        ? Uri.parse(
            'https://www.tagesschau.de/api2u/search/?searchText=${Uri.encodeComponent(topic)}&pageSize=5')
        : Uri.parse('https://www.tagesschau.de/api2u/homepage/');

    // Follow redirects manually (tagesschau uses 308)
    var response = await http.get(uri, headers: {
      'User-Agent': 'SchoolBudE/1.0',
    }).timeout(const Duration(seconds: 10));

    // Handle redirect
    if (response.statusCode == 301 || response.statusCode == 302 ||
        response.statusCode == 307 || response.statusCode == 308) {
      final redirectUrl = response.headers['location'];
      if (redirectUrl != null) {
        response = await http.get(Uri.parse(redirectUrl), headers: {
          'User-Agent': 'SchoolBudE/1.0',
        }).timeout(const Duration(seconds: 10));
      }
    }

    if (response.statusCode != 200) return 'Tagesschau: Error ${response.statusCode}';

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final buf = StringBuffer(topic != null
        ? 'Tagesschau Nachrichten zu "$topic":\n'
        : 'Tagesschau aktuelle Nachrichten:\n');

    // Homepage format
    final news = (data['news'] as List?) ??
        (data['searchResults'] as List?) ??
        [];
    if (news.isEmpty) return 'Tagesschau: No results';

    for (final item in news.take(8)) {
      final title = item['title'] ?? item['teaserText'] ?? '';
      final date = item['date'] ?? '';
      final topline = item['topline'] ?? '';
      final shortText = item['firstSentence'] ?? item['teaserText'] ?? '';
      buf.writeln('\n- ${topline.isNotEmpty ? "$topline: " : ""}$title');
      if (shortText.isNotEmpty) buf.writeln('  $shortText');
      if (date.isNotEmpty) buf.writeln('  ($date)');
    }
    return buf.toString();
  } catch (e) {
    return 'Tagesschau error: $e';
  }
}

/// Search the web using Brave Search and return text results.
Future<String> toolWebSearch(String query) async {
  try {
    final uri = Uri.parse(
        'https://search.brave.com/search?q=${Uri.encodeComponent(query)}');
    final response = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Accept': 'text/html',
    }).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return 'Search error: HTTP ${response.statusCode}';

    var html = response.body;
    // Strip scripts/styles
    html = html.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
    html = html.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
    html = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
    html = html.replaceAll('&amp;', '&').replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>').replaceAll('&nbsp;', ' ');
    html = html.replaceAll(RegExp(r'[ \t]+'), ' ');
    html = html.replaceAll(RegExp(r'\n\s*\n'), '\n');

    // Find relevant sentences
    final sentences = html.split('.').where((s) => s.trim().length > 30).take(15);
    final buf = StringBuffer('Web search results for "$query":\n');
    for (final s in sentences) {
      buf.writeln('- ${s.trim()}.');
    }

    var result = buf.toString();
    if (result.length > 8000) result = '${result.substring(0, 8000)}...(truncated)';
    return result;
  } catch (e) {
    return 'Web search error: $e';
  }
}

/// Fetch a webpage and extract readable text (strips HTML tags, scripts, styles).
Future<String> toolWebScrape(String url) async {
  try {
    final uri = Uri.parse(url);
    final response = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; SchoolBudE/1.0)',
      'Accept': 'text/html,application/xhtml+xml',
    }).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) return 'Scrape error: HTTP ${response.statusCode}';

    var html = response.body;

    // Remove script, style, nav, footer, header tags and their content
    html = html.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
    html = html.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
    html = html.replaceAll(RegExp(r'<nav[^>]*>[\s\S]*?</nav>', caseSensitive: false), '');
    html = html.replaceAll(RegExp(r'<footer[^>]*>[\s\S]*?</footer>', caseSensitive: false), '');
    html = html.replaceAll(RegExp(r'<header[^>]*>[\s\S]*?</header>', caseSensitive: false), '');
    html = html.replaceAll(RegExp(r'<!--[\s\S]*?-->', caseSensitive: false), '');

    // Extract title
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false).firstMatch(html);
    final title = titleMatch?.group(1)?.trim() ?? '';

    // Convert block tags to newlines
    html = html.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    html = html.replaceAll(RegExp(r'</?(p|div|h[1-6]|li|tr|blockquote)[^>]*>'), '\n');

    // Strip all remaining HTML tags
    html = html.replaceAll(RegExp(r'<[^>]+>'), '');

    // Decode HTML entities
    html = html.replaceAll('&amp;', '&').replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>').replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'").replaceAll('&nbsp;', ' ');

    // Clean up whitespace
    html = html.replaceAll(RegExp(r'[ \t]+'), ' ');
    html = html.replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n');
    html = html.trim();

    if (html.length > 15000) html = '${html.substring(0, 15000)}\n...(truncated)';

    return 'Webpage: $title\nURL: $url\n---\n$html';
  } catch (e) {
    return 'Scrape error: $e';
  }
}

/// Fetch a URL and return its raw content (limited to 20KB).
Future<String> toolWebFetch(String url) async {
  try {
    final uri = Uri.parse(url);
    final response = await http.get(uri, headers: {
      'User-Agent': 'SchoolBudE/1.0',
    }).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return 'Fetch error: HTTP ${response.statusCode}';

    var body = response.body;
    if (body.length > 20000) body = '${body.substring(0, 20000)}\n...(truncated)';
    return 'Fetched $url (${response.statusCode}):\n$body';
  } catch (e) {
    return 'Fetch error: $e';
  }
}
