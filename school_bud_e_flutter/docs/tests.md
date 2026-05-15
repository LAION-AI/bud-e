# BUD-E Integration Tests

## Test-Suite Ergebnisse (Stand: Mai 2026)

### Automatisierte API-Tests

| # | Test | Status | Details |
|---|------|--------|---------|
| 1 | Weather Tool-Call | PASS | LLM gibt `[[tool:weather location="Hamburg"]]` aus |
| 2 | News Tool-Call | PASS | LLM gibt `[[tool:news]]` aus |
| 3 | Bildanalyse | PASS | Roter Kreis auf weissem Hintergrund erkannt |
| 4 | Kleines PDF (2 Seiten) | PASS | Geheimcode BETA-GAMMA-7 via Text-Extraktion gefunden |
| 5 | Grosses PDF (15 Seiten) | PASS | Geheimcode ALPHA-OMEGA-42 auf Seite 15 gefunden |
| 6 | NeurIPS Paper (5.1 MB, 25 Seiten) | PASS | Titel "EmoNet Voice" korrekt erkannt via Middleware |
| 7 | Lange Antworten | PASS | 5741 Zeichen fuer Photosynthese-Erklaerung |
| 8 | Seitenzahl-Erkennung | PASS | 2/15/40/25 Seiten korrekt |

### PDF-Verarbeitung

#### Verarbeitungspipeline

```
PDF-Upload
  |
  +-- Groesse pruefen
  |     |
  |     +-- < 2MB, < 10 Seiten --> Direkt an Middleware (multimodal base64)
  |     |                           + Text-Extraktion als Backup im Kontext
  |     |
  |     +-- > 2MB oder > 10 Seiten --> Auto-Agent-Spawn
  |                                     |
  |                                     +-- pdf_info (Seiten, Textgehalt)
  |                                     +-- pdf_extract_text (5-Seiten-Bloecke)
  |                                     +-- Falls kein Text: analyze_pdf_pages (OCR)
  |                                     +-- Ergebnis --> BUD-E praesentiert
  |
  +-- Fehler bei Vorverarbeitung --> Auto-Agent-Spawn
```

#### Text-Extraktion

Die Text-Extraktion arbeitet auf Byte-Ebene (kein `String.fromCharCodes` auf dem ganzen File):
- Sucht `stream`/`endstream` Marker per Byte-Scan
- Dekomprimiert FlateDecode-Streams mit ZLib
- Extrahiert `(text) Tj` und `[(text)] TJ` Operatoren
- Begrenzt auf 50 Seiten und 200KB pro Stream (verhindert Stack Overflow)

**Bekannte Limitationen:**
- CIDFont/ToUnicode CMap-Encoding wird nicht dekodiert (z.B. Lehrplan PDF)
- Bei komplexer Encoding wird auf die Middleware/Gemini-OCR zurueckgefallen
- Sehr grosse Streams (>200KB, z.B. eingebettete Bilder) werden uebersprungen

#### Getestete PDF-Typen

| PDF | Groesse | Seiten | Text-Extraktion | Middleware | Status |
|-----|---------|--------|-----------------|------------|--------|
| test_small.pdf (generiert) | 1 KB | 2 | Ja (Tj) | Ja | OK |
| test_large.pdf (generiert) | 7 KB | 15 | Ja (Tj) | Ja | OK |
| Lehrplan Informatik HH | 657 KB | 40 | Nein (CIDFont) | Ja (intermittent 502) | OK via Agent |
| NeurIPS EmoNet Voice | 5.1 MB | 25 | Nein (komplex) | Ja | OK |
| Boron Vademecum (DSA) | 4.4 MB | ~200 | Nein | Via Agent | OK (Stack Overflow gefixt) |
| 5a Laengen AB1 | 40 KB | 2 | - | Ja | OK |

#### Stack-Overflow-Fix (Boron Vademecum)

**Problem:** `extractTextBasic` konvertierte den gesamten 4.4MB PDF-Inhalt in einen String und fuehrte Regex darauf aus -> Stack Overflow.

**Fix:**
1. Byte-Level-Scanning statt String-Konvertierung fuer Stream-Boundaries
2. Nur einzelne Streams (< 200KB) werden zu Strings konvertiert
3. Maximum 50 Seiten werden verarbeitet
4. Fehler werden abgefangen und fuehren zum Agent-Fallback statt Crash

### Tool-Tests

#### Wetter (wttr.in)

```
Input:  "Wie ist das Wetter in Hamburg?"
LLM:    [[tool:weather location="Hamburg"]]
API:    https://wttr.in/Hamburg?format=j1
Result: Temperature: 9C, Condition: Overcast, Wind: 8 km/h E
```

**Kein API-Key noetig.** Limit: 60 Requests/Stunde.

#### Nachrichten (tagesschau.de)

```
Input:  "Was sind die aktuellen Nachrichten?"
LLM:    [[tool:news]]
API:    https://www.tagesschau.de/api2u/homepage/
Result: 10 aktuelle Artikel mit Titel und Zusammenfassung
```

**API-URL:** `api2u` (nicht `api2`). Redirect-Handling (308) implementiert.

#### Wikipedia

```
Input:  "Was ist Photosynthese?"
LLM:    [[tool:wikipedia query="Photosynthese" depth="summary"]]
API:    https://de.wikipedia.org/api/rest_v1/page/summary/Photosynthese
Result: Zusammenfassung des Wikipedia-Artikels
```

#### Bildanalyse (Multimodal)

```
Input:  [Bild: roter Kreis auf weiss] + "Was siehst du?"
Format: {type: "image_url", image_url: {url: "data:image/png;base64,..."}}
Result: "Ich sehe eine rote Scheibe auf weissem Hintergrund"
```

**Unterstuetzte Formate:** PNG, JPG, JPEG, GIF, WebP, BMP
**Bilder werden als Base64 inline im API-Request gesendet.**

### Sub-Agent Tests

#### Agent-Lebenszyklus

```
1. BUD-E erkennt komplexe Aufgabe oder grosses PDF
2. Agent-Task wird erstellt (Status: running, drehendes Zahnrad)
3. Sub-Agent macht LLM-Calls mit Text-basiertem Tool-Calling
4. Tools werden ausgefuehrt, Ergebnisse zurueckgefuettert
5. Agent beendet (Status: completed, gruenes Haekchen)
6. Ergebnis wird BUD-E uebergeben -> BUD-E praesentiert es
7. Bei Fehler: BUD-E erklaert den Fehler dem Nutzer
```

#### Agent-Tools

| Tool | Beschreibung | Getestet |
|------|-------------|----------|
| read_file | Text/JSON/MD lesen | Ja |
| write_file | Dateien schreiben | Ja |
| list_files | Workspace auflisten | Ja |
| pdf_info | PDF-Metadaten | Ja |
| pdf_extract_text | Text aus PDF | Ja |
| analyze_pdf_pages | PDF an AI senden | Ja |
| analyze_document | Bilder/PDFs analysieren | Ja |
| wikipedia | Wikipedia-Suche | Ja |
| weather | Wetter via wttr.in | Ja |
| news | tagesschau.de News | Ja |
| web_fetch | URL abrufen | Ja |

### Memory-System Tests

#### Taegliche Konsolidierung

Laueft automatisch einmal pro Tag (beim App-Start geprueft):
1. Laedt alle semantischen Konzepte
2. LLM analysiert Beziehungen und schlaegt Verbesserungen vor
3. Cross-Referenzen werden bidirektional hinzugefuegt
4. Fehlende Trigger-Words werden ergaenzt
5. Duplikate werden erkannt (noch nicht automatisch gemergt)

#### Memory-Update nach jeder Konversation

1. Letzte 10 Nachrichten -> LLM-Extraktion
2. Konzepte erstellt/aktualisiert (mit Revisions-History)
3. Episodische Zusammenfassung gespeichert
4. Prozedurale Notizen aktualisiert
5. Caches invalidiert (Context Builder + BM25)

### Bekannte Probleme

1. **Middleware 502 bei grossen PDFs:** Intermittent, haengt von Middleware-Load ab. Workaround: Agent-basierte Verarbeitung.
2. **CIDFont-Text-Extraktion:** Komplexe Font-Encodings werden nicht unterstuetzt. Fallback: Middleware/Gemini-OCR.
3. **Dateipfade mit Sonderzeichen:** Unicode-Sonderzeichen (z.B. typographische Apostrophe) koennen auf Windows Probleme machen.
4. **Tagesschau API 308-Redirect:** Manuell behandelt, nicht alle HTTP-Clients folgen automatisch.

### Testdateien

| Datei | Beschreibung | Generiert |
|-------|-------------|-----------|
| test_small.pdf | 2 Seiten, Geheimcode BETA-GAMMA-7 | gen_test_pdfs.py |
| test_large.pdf | 15 Seiten Informatik-Geschichte, Code ALPHA-OMEGA-42 | gen_test_pdfs.py |
| test_circle.png | Roter Kreis auf weiss (100x100px) | Python inline |
| test_lehrplan.pdf | Hamburger Bildungsplan Informatik Sek I | Download hamburg.de |

### Test ausfuehren

Die Tests koennen ueber die API ausgefuehrt werden, waehrend die App laeuft:

```bash
KEY="sbe-2NE7Z87KY6DU#v1NNUG25DKORVHI23AMJWWE3I"

# Weather
curl -s -X POST http://127.0.0.1:8787/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d '{"model":"auto","stream":false,"messages":[
    {"role":"system","content":"Tool: [[tool:weather location=\"Stadt\"]]"},
    {"role":"user","content":"Wetter Hamburg?"}
  ]}'

# Image
B64=$(base64 -w0 test_circle.png)
curl -s -X POST http://127.0.0.1:8787/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY" \
  -d "{\"model\":\"auto\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":[
    {\"type\":\"text\",\"text\":\"Was siehst du?\"},
    {\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,$B64\"}}
  ]}]}"
```
