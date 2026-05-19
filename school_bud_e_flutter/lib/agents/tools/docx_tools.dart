/// DOCX file generation — creates properly formatted Word documents.
/// Includes styles.xml for default font (Calibri 11pt), heading styles, etc.
library;

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

/// Write a real .docx file from markdown content.
/// If [imageFiles] is provided, IMG_xxx references in markdown are replaced
/// with embedded images in the DOCX.
Future<String> writeDocx(String markdown, String outputPath,
    {Map<String, String>? imageFiles}) async {
  if (!outputPath.toLowerCase().endsWith('.docx')) {
    outputPath = '${outputPath.replaceAll(RegExp(r'\.\w+$'), '')}.docx';
  }
  final dir = Directory(p.dirname(outputPath));
  if (!await dir.exists()) await dir.create(recursive: true);

  final cleaned = markdown.replaceAll('\\n', '\n').replaceAll('\r\n', '\n');

  // Collect images to embed
  final images = <String, List<int>>{}; // rId -> bytes
  var processedMd = cleaned;
  if (imageFiles != null) {
    var imgIdx = 0;
    for (final entry in imageFiles.entries) {
      if (processedMd.contains(entry.key)) {
        final file = File(entry.value);
        if (await file.exists()) {
          imgIdx++;
          images['rImg$imgIdx'] = await file.readAsBytes();
          // Replace the IMG_xxx reference with a placeholder
          processedMd = processedMd.replaceAll(
              RegExp('!?\\[?${RegExp.escape(entry.key)}\\]?\\(?[^)]*\\)?'),
              '<<IMAGE:rImg$imgIdx>>');
          // Also handle bare references
          if (processedMd.contains(entry.key)) {
            processedMd = processedMd.replaceAll(entry.key, '<<IMAGE:rImg$imgIdx>>');
          }
        }
      }
    }
  }

  final bodyXml = _mdToOoxml(processedMd, imageRefs: images.keys.toList(), imageBytesMap: images);
  await File(outputPath).writeAsBytes(
      _buildZip(bodyXml, images: images));
  return outputPath;
}

// ── Markdown → OOXML ────────────────────────────────────────────────────────

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _mdToOoxml(String md, {List<String>? imageRefs, Map<String, List<int>>? imageBytesMap}) {
  final buf = StringBuffer();
  for (final line in md.split('\n')) {
    final t = line.trim();
    // Check for image placeholder
    final imgMatch = RegExp(r'<<IMAGE:(rImg\d+)>>').firstMatch(t);
    if (imgMatch != null) {
      final rId = imgMatch.group(1)!;
      buf.write(_imageBlock(rId, imageBytes: imageBytesMap?[rId]));
      continue;
    }
    if (t.isEmpty) {
      buf.write(_p('', after: 120));
    } else if (t.startsWith('# ') && !t.startsWith('## ')) {
      buf.write(_styled('Heading1', t.substring(2)));
    } else if (t.startsWith('## ') && !t.startsWith('### ')) {
      buf.write(_styled('Heading2', t.substring(3)));
    } else if (t.startsWith('### ')) {
      buf.write(_styled('Heading3', t.substring(4)));
    } else if (t.startsWith('#### ')) {
      // Heading 4 — small bold
      final h4text = t.substring(5).replaceAll('**', '').replaceAll('*', '');
      buf.write('<w:p><w:pPr><w:spacing w:before="120" w:after="40"/></w:pPr>'
          '<w:r><w:rPr><w:b/><w:sz w:val="22"/><w:color w:val="555555"/></w:rPr>'
          '<w:t xml:space="preserve">${_esc(h4text)}</w:t></w:r></w:p>');
    } else if (t.startsWith('- ') || t.startsWith('* ')) {
      buf.write(_bullet(t.substring(2)));
    } else if (t.startsWith('> ')) {
      // Blockquote
      buf.write('<w:p><w:pPr><w:ind w:left="720"/><w:spacing w:after="60"/>'
          '<w:pBdr><w:left w:val="single" w:sz="12" w:space="8" w:color="AAAAAA"/>'
          '</w:pBdr></w:pPr>${_runs(t.substring(2))}</w:p>');
    } else if (RegExp(r'^\d+\.\s').hasMatch(t)) {
      // Numbered list
      final text = t.replaceFirst(RegExp(r'^\d+\.\s'), '');
      buf.write('<w:p><w:pPr><w:ind w:left="720" w:hanging="360"/>'
          '<w:spacing w:after="40"/></w:pPr>${_runs(t)}</w:p>');
    } else if (t.startsWith('---') && t.replaceAll('-', '').trim().isEmpty) {
      buf.write('<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" '
          'w:space="1" w:color="CCCCCC"/></w:pBdr>'
          '<w:spacing w:after="120"/></w:pPr></w:p>');
    } else if (t.startsWith('|') && t.contains('|')) {
      if (!t.contains('---')) buf.write(_tableRow(t));
    } else {
      buf.write(_p(t));
    }
  }
  return buf.toString();
}

/// A paragraph with optional style.
String _styled(String style, String text) {
  text = text.replaceAll('**', '').replaceAll('*', '');
  return '<w:p><w:pPr><w:pStyle w:val="$style"/></w:pPr>'
      '${_runs(_esc(text))}</w:p>';
}

/// Normal paragraph with inline formatting.
/// Supports {font:Arial} and {size:14} directives at start of line.
String _p(String text, {int after = 60}) {
  if (text.isEmpty) {
    return '<w:p><w:pPr><w:spacing w:after="$after"/></w:pPr></w:p>';
  }

  // Parse font/size directives: {font:Arial size:14 color:FF0000}
  String? fontName;
  int? fontSize;
  String? fontColor;
  final directiveMatch = RegExp(r'^\{([^}]+)\}\s*').firstMatch(text);
  if (directiveMatch != null) {
    final directives = directiveMatch.group(1)!;
    final fMatch = RegExp(r'font:(\w[\w\s]*)').firstMatch(directives);
    final sMatch = RegExp(r'size:(\d+)').firstMatch(directives);
    final cMatch = RegExp(r'color:([0-9A-Fa-f]{6})').firstMatch(directives);
    if (fMatch != null) fontName = fMatch.group(1)!.trim();
    if (sMatch != null) fontSize = int.tryParse(sMatch.group(1)!);
    if (cMatch != null) fontColor = cMatch.group(1)!;
    text = text.substring(directiveMatch.end);
  }

  // Build paragraph with optional custom formatting
  final ppr = '<w:pPr><w:spacing w:after="$after"/></w:pPr>';
  if (fontName != null || fontSize != null || fontColor != null) {
    // Custom run properties for the whole paragraph
    final rprBuf = StringBuffer('<w:rPr>');
    if (fontName != null) rprBuf.write('<w:rFonts w:ascii="$fontName" w:hAnsi="$fontName"/>');
    if (fontSize != null) rprBuf.write('<w:sz w:val="${fontSize * 2}"/><w:szCs w:val="${fontSize * 2}"/>');
    if (fontColor != null) rprBuf.write('<w:color w:val="$fontColor"/>');
    rprBuf.write('</w:rPr>');
    return '<w:p>$ppr<w:r>${rprBuf.toString()}'
        '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';
  }

  return '<w:p>$ppr${_runs(text)}</w:p>';
}

/// Bullet paragraph.
String _bullet(String text) =>
    '<w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr>'
    '${_runs(text)}</w:p>';

/// Table row (simple tab-separated).
String _tableRow(String line) {
  final cells = line.split('|').where((c) => c.trim().isNotEmpty).toList();
  final buf = StringBuffer('<w:tbl><w:tblPr>'
      '<w:tblW w:w="5000" w:type="pct"/>'
      '<w:tblBorders>'
      '<w:top w:val="single" w:sz="4" w:color="999999"/>'
      '<w:bottom w:val="single" w:sz="4" w:color="999999"/>'
      '<w:insideH w:val="single" w:sz="4" w:color="999999"/>'
      '<w:insideV w:val="single" w:sz="4" w:color="999999"/>'
      '</w:tblBorders></w:tblPr><w:tr>');
  for (final cell in cells) {
    final clean = cell.trim().replaceAll('**', '');
    final isBold = cell.contains('**');
    buf.write('<w:tc><w:p>');
    if (isBold) {
      buf.write('<w:r><w:rPr><w:b/></w:rPr>'
          '<w:t xml:space="preserve">${_esc(clean)}</w:t></w:r>');
    } else {
      buf.write('<w:r><w:t xml:space="preserve">${_esc(clean)}</w:t></w:r>');
    }
    buf.write('</w:p></w:tc>');
  }
  buf.write('</w:tr></w:tbl>');
  return buf.toString();
}

/// Parse inline **bold** and *italic* into runs.
String _runs(String text) {
  final buf = StringBuffer();
  final re = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*)');
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) buf.write(_run(_esc(text.substring(last, m.start))));
    final s = m.group(0)!;
    if (s.startsWith('**')) {
      buf.write(_run(_esc(s.substring(2, s.length - 2)), bold: true));
    } else {
      buf.write(_run(_esc(s.substring(1, s.length - 1)), italic: true));
    }
    last = m.end;
  }
  if (last < text.length) buf.write(_run(_esc(text.substring(last))));
  if (buf.isEmpty) buf.write(_run(_esc(text)));
  return buf.toString();
}

String _run(String text, {bool bold = false, bool italic = false}) {
  final rpr = (bold || italic)
      ? '<w:rPr>${bold ? "<w:b/>" : ""}${italic ? "<w:i/>" : ""}</w:rPr>'
      : '';
  return '<w:r>$rpr<w:t xml:space="preserve">$text</w:t></w:r>';
}

/// Inline image block for DOCX (OOXML drawing).
/// If imageBytes is provided, auto-detects aspect ratio.
String _imageBlock(String rId, {List<int>? imageBytes}) {
  var cx = 4500000; // ~4.7 inches EMU default
  var cy = 3000000; // ~3.1 inches EMU default

  // Auto-detect aspect ratio from PNG/JPEG header
  if (imageBytes != null && imageBytes.length > 30) {
    int? w, h;
    // PNG
    if (imageBytes[0] == 0x89 && imageBytes[1] == 0x50) {
      w = (imageBytes[16] << 24) | (imageBytes[17] << 16) | (imageBytes[18] << 8) | imageBytes[19];
      h = (imageBytes[20] << 24) | (imageBytes[21] << 16) | (imageBytes[22] << 8) | imageBytes[23];
    }
    // JPEG
    if (imageBytes[0] == 0xFF && imageBytes[1] == 0xD8) {
      for (var i = 2; i < imageBytes.length - 10; i++) {
        if (imageBytes[i] == 0xFF && (imageBytes[i + 1] == 0xC0 || imageBytes[i + 1] == 0xC2)) {
          h = (imageBytes[i + 5] << 8) | imageBytes[i + 6];
          w = (imageBytes[i + 7] << 8) | imageBytes[i + 8];
          break;
        }
      }
    }
    if (w != null && h != null && w > 0 && h > 0) {
      final aspect = w / h;
      // Scale to fit page width (max 4.7 inches = 4500000 EMU)
      cx = 4500000;
      cy = (cx / aspect).round();
      // Cap height to ~6 inches
      if (cy > 5500000) { cy = 5500000; cx = (cy * aspect).round(); }
    }
  }
  return '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
      '<w:r><w:drawing>'
      '<wp:inline distT="0" distB="0" distL="0" distR="0" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
      '<wp:extent cx="$cx" cy="$cy"/>'
      '<wp:docPr id="1" name="Bild"/>'
      '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
      '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:nvPicPr><pic:cNvPr id="1" name="image"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill>'
      '<a:blip r:embed="$rId" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>'
      '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic>'
      '</wp:inline></w:drawing></w:r></w:p>';
}

// ── ZIP builder ─────────────────────────────────────────────────────────────

Uint8List _buildZip(String bodyXml, {Map<String, List<int>>? images}) {
  final docXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<w:body>$bodyXml'
      '<w:sectPr>'
      '<w:pgSz w:w="11906" w:h="16838"/>'  // A4
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
      'w:header="720" w:footer="720"/>'  // 1 inch margins
      '</w:sectPr></w:body></w:document>';

  // styles.xml — defines fonts, heading styles, bullet style
  final stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      // Default document font
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>'
      '<w:sz w:val="22"/><w:szCs w:val="22"/>'  // 11pt
      '<w:lang w:val="de-DE"/>'
      '</w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr>'
      '<w:spacing w:after="80" w:line="276" w:lineRule="auto"/>'  // 1.15 line spacing
      '</w:pPr></w:pPrDefault></w:docDefaults>'
      // Normal style
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
      '<w:name w:val="Normal"/></w:style>'
      // Heading 1
      '<w:style w:type="paragraph" w:styleId="Heading1">'
      '<w:name w:val="heading 1"/>'
      '<w:pPr><w:spacing w:before="360" w:after="120"/></w:pPr>'
      '<w:rPr><w:b/><w:sz w:val="36"/><w:szCs w:val="36"/>'
      '<w:color w:val="0050A0"/></w:rPr></w:style>'
      // Heading 2
      '<w:style w:type="paragraph" w:styleId="Heading2">'
      '<w:name w:val="heading 2"/>'
      '<w:pPr><w:spacing w:before="240" w:after="80"/></w:pPr>'
      '<w:rPr><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/>'
      '<w:color w:val="0050A0"/></w:rPr></w:style>'
      // Heading 3
      '<w:style w:type="paragraph" w:styleId="Heading3">'
      '<w:name w:val="heading 3"/>'
      '<w:pPr><w:spacing w:before="160" w:after="60"/></w:pPr>'
      '<w:rPr><w:b/><w:sz w:val="24"/><w:szCs w:val="24"/>'
      '<w:color w:val="333333"/></w:rPr></w:style>'
      // Bullet list
      '<w:style w:type="paragraph" w:styleId="ListBullet">'
      '<w:name w:val="List Bullet"/>'
      '<w:pPr><w:ind w:left="720" w:hanging="360"/>'
      '<w:spacing w:after="40"/></w:pPr></w:style>'
      '</w:styles>';

  // Build content types with image extensions if needed
  var ctExtra = '';
  if (images != null && images.isNotEmpty) {
    ctExtra = '<Default Extension="png" ContentType="image/png"/>'
        '<Default Extension="jpeg" ContentType="image/jpeg"/>'
        '<Default Extension="jpg" ContentType="image/jpeg"/>';
  }

  // Build document relationships including images
  final relsBuf = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
  if (images != null) {
    for (final rId in images.keys) {
      relsBuf.write('<Relationship Id="$rId" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="media/$rId.png"/>');
    }
  }
  relsBuf.write('</Relationships>');

  final files = <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '$ctExtra'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '</Types>'),
    '_rels/.rels': utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>'),
    'word/document.xml': utf8.encode(docXml),
    'word/styles.xml': utf8.encode(stylesXml),
    'word/_rels/document.xml.rels': utf8.encode(relsBuf.toString()),
  };

  // Add image files
  if (images != null) {
    for (final entry in images.entries) {
      files['word/media/${entry.key}.png'] = entry.value;
    }
  }

  return _createZip(files);
}

Uint8List _createZip(Map<String, List<int>> files) {
  final out = BytesBuilder();
  final cd = BytesBuilder();
  var n = 0;
  for (final e in files.entries) {
    final name = utf8.encode(e.key);
    final data = Uint8List.fromList(e.value);
    final crc = _crc32(data);
    final off = out.length;
    // Local header
    out.add(_u32(0x04034B50));
    out.add(_u16(20)); out.add(_u16(0)); out.add(_u16(0));
    out.add(_u16(0)); out.add(_u16(0));
    out.add(_u32(crc)); out.add(_u32(data.length)); out.add(_u32(data.length));
    out.add(_u16(name.length)); out.add(_u16(0));
    out.add(name); out.add(data);
    // Central dir
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

Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

int _crc32(Uint8List d) {
  var c = 0xFFFFFFFF;
  for (final b in d) { c ^= b; for (var j = 0; j < 8; j++) c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1; }
  return c ^ 0xFFFFFFFF;
}
