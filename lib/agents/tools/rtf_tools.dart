/// RTF file generation — creates formatted documents for Word/LibreOffice.
library;

/// Convert markdown-like text to properly formatted RTF.
String markdownToRtf(String markdown) {
  final buf = StringBuffer();

  // RTF header with fonts and colors
  buf.write('{');
  buf.writeln(r'\rtf1\ansi\ansicpg1252\deff0');
  buf.writeln(r'{\fonttbl{\f0\fswiss\fcharset0 Calibri;}{\f1\fmodern\fcharset0 Consolas;}}');
  buf.writeln(r'{\colortbl;\red0\green0\blue0;\red0\green80\blue160;\red180\green0\blue0;\red0\green130\blue0;}');
  buf.writeln(r'\viewkind4\uc1\f0\fs22\sa60');
  buf.writeln();

  final lines = markdown.split('\n');
  var inTable = false;

  for (var i = 0; i < lines.length; i++) {
    final rawLine = lines[i];
    // Escape RTF special chars FIRST, before checking prefixes
    var line = _escapeRtf(rawLine);
    final trimmed = rawLine.trimLeft();

    if (trimmed.startsWith('# ') && !trimmed.startsWith('## ')) {
      // H1 — large blue bold
      final text = _escapeRtf(trimmed.substring(2));
      buf.writeln('\\pard\\sb240\\sa120\\b\\fs36\\cf2 $text\\b0\\fs22\\cf1\\par');
    } else if (trimmed.startsWith('## ') && !trimmed.startsWith('### ')) {
      // H2 — medium blue bold
      final text = _escapeRtf(trimmed.substring(3));
      buf.writeln('\\pard\\sb200\\sa80\\b\\fs28\\cf2 $text\\b0\\fs22\\cf1\\par');
    } else if (trimmed.startsWith('### ')) {
      // H3 — small bold
      final text = _escapeRtf(trimmed.substring(4));
      buf.writeln('\\pard\\sb160\\sa60\\b\\fs24 $text\\b0\\fs22\\par');
    } else if (trimmed.startsWith('---') && trimmed.replaceAll('-', '').trim().isEmpty) {
      // Horizontal rule
      buf.writeln('\\pard\\sa60\\brdrb\\brdrs\\brdrw10\\brsp40\\par');
    } else if (trimmed.startsWith('| ') && trimmed.contains(' | ')) {
      // Table row — use tabs for alignment
      if (trimmed.contains('---')) continue; // Skip separator
      final cells = trimmed.split('|')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
      final isHeader = cells.any((c) => c.startsWith('**'));
      final row = StringBuffer('\\pard\\tx2500\\tx5000\\tx7500\\sa30 ');
      for (var ci = 0; ci < cells.length; ci++) {
        var cell = _escapeRtf(cells[ci].replaceAll('**', ''));
        if (isHeader) {
          row.write('\\b $cell\\b0 ');
        } else {
          row.write(cell);
        }
        if (ci < cells.length - 1) row.write('\\tab ');
      }
      row.write('\\par');
      buf.writeln(row);
    } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      // Bullet point
      final text = _formatInline(_escapeRtf(trimmed.substring(2)));
      buf.writeln('\\pard\\li400\\fi-200\\sa30 \\u8226  $text\\par');
    } else if (trimmed.isEmpty) {
      buf.writeln('\\pard\\sa80\\par');
    } else {
      // Normal paragraph
      final text = _formatInline(line);
      buf.writeln('\\pard\\sa40 $text\\par');
    }
  }

  buf.write('}');
  return buf.toString();
}

/// Escape RTF special characters.
String _escapeRtf(String s) {
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x5C) { // backslash
      buf.write('\\\\');
    } else if (c == 0x7B) { // {
      buf.write('\\{');
    } else if (c == 0x7D) { // }
      buf.write('\\}');
    } else if (c > 127) {
      // Unicode character
      buf.write("\\u${c}?");
    } else {
      buf.writeCharCode(c);
    }
  }
  return buf.toString();
}

/// Convert inline markdown formatting to RTF.
String _formatInline(String text) {
  // Bold: **text**
  text = text.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'),
      (m) => '\\b ${m.group(1)!}\\b0 ');
  // Italic: *text*
  text = text.replaceAllMapped(
      RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)'),
      (m) => '\\i ${m.group(1)!}\\i0 ');
  // Red text for errors: ~~text~~
  text = text.replaceAllMapped(
      RegExp(r'~~([^~]+)~~'),
      (m) => '\\cf3 ${m.group(1)!}\\cf1 ');
  // Green for correct: ++text++
  text = text.replaceAllMapped(
      RegExp(r'\+\+([^+]+)\+\+'),
      (m) => '\\cf4 ${m.group(1)!}\\cf1 ');
  return text;
}
