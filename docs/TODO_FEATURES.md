# BUD-E Feature Roadmap & TODOs

## Uebersicht

Jedes Feature wird als **Skill-Datei** im prozeduralen Gedaechtnis (`semantic_memory/skill_*.json`) implementiert. Skills definieren:
- Wann BUD-E das Feature aktivieren soll (triggerWords)
- Wie die API angesprochen wird (Tool-Beschreibung)
- Wie das Ergebnis praesentiert wird (UI-Rendering)

---

## 1. Bildgenerierung

**Skill-Datei:** `skill_bildgenerierung.json`
**Status:** TODO
**API:** `POST /v1/images/generations`

### Funktionalitaet
- **Text-to-Image:** User beschreibt ein Bild, BUD-E generiert es
- **Image Editing:** User gibt ein Referenzbild + Aenderungswunsch, BUD-E editiert es
- **Style Transfer:** Stil von Bild A auf Bild B uebertragen
- **Multi-Reference:** Mehrere Referenzbilder (bis zu 4 bei FLUX.2 klein, 8 bei pro/max)

### Modelle (via Admin_Bud-E Middleware)
| Modell | Typ | Kosten |
|--------|-----|--------|
| gemini-3-pro-image-preview | Text+Images → Image | ~0.02/Bild |
| imagen-4.0-generate-001 | Text → Image | ~0.02/Bild |
| imagen-4.0-ultra-generate-001 | Text → Image (HQ) | ~0.04/Bild |
| flux-2-klein-9b | Text → Image (schnell) | ~0.014/Bild |
| flux-2-pro | Text → Image (Produktion) | ~0.04/Bild |
| flux-2-max | Text → Image (Maximum) | ~0.07/Bild |
| nano-banana-pro | Multimodal | variabel |

### API-Request Format
```json
{
  "model": "gemini-3-pro-image-preview",
  "prompt": "Ein Sonnenuntergang ueber dem Meer",
  "n": 1,
  "size": "1024x1024",
  "input_images": ["data:image/jpeg;base64,..."],
  "negative_prompt": "blurry, low quality"
}
```

### UI-Verhalten
- Generiertes Bild wird als **Vorschau** im Chat angezeigt (ca. 300px breit)
- **Klick** auf Vorschau → Vollbild-Ansicht (Dialog/Overlay)
- Buttons unter dem Bild:
  - Download (speichert als PNG/JPG im Workspace)
  - Regenerieren (gleicher Prompt, neuer Seed)
  - Prompt bearbeiten → neues Bild
  - Als Referenz verwenden (fuer naechste Generierung)
- Wenn User ein Bild hochlaedt + "aendere X": Image Editing mit dem Bild als Referenz
- Agent sammelt automatisch alle Bilder aus der aktuellen Konversation als potenzielle Referenzen

### Trigger-Words
`bild generieren`, `bild erstellen`, `male`, `zeichne`, `generiere ein bild`, `image`, `foto`, `illustration`, `style transfer`, `bild aendern`, `bild bearbeiten`

---

## 2. Musikgenerierung (Lyria)

**Skill-Datei:** `skill_musikgenerierung.json`
**Status:** TODO
**API:** `POST /v1/audio/generations`

### Funktionalitaet
- User beschreibt Musikstueck, BUD-E generiert instrumentale Musik
- Bis zu 32.8 Sekunden pro Clip
- Negative Prompts (z.B. "keine Gesangsstimmen")
- Seed fuer Reproduzierbarkeit

### Modelle
| Modell | Typ | Max Laenge | Format |
|--------|-----|-----------|--------|
| lyria-002 | Instrumental | 32.8s | 48kHz WAV |

### API-Request Format
```json
{
  "model": "lyria-002",
  "prompt": "Entspannende Klaviermusik mit sanften Streichern",
  "negative_prompt": "vocals, singing",
  "n": 1,
  "seed": null
}
```

### UI-Verhalten
- Audio-Player Widget im Chat (Play/Pause/Seek)
- Download-Button (WAV-Datei)
- Regenerieren-Button
- Prompt bearbeiten → neues Stueck

### Trigger-Words
`musik generieren`, `musik erstellen`, `komponiere`, `spiele musik`, `melodie`, `song`, `beat`, `instrumental`, `lyria`, `audio generieren`

---

## 3. Audio-Transkription (Upload)

**Skill-Datei:** `skill_audio_transkription.json`
**Status:** TODO
**API:** `POST /v1/audio/transcriptions`

### Funktionalitaet
- User laedt Audio-Datei hoch (MP3, WAV, OGG, M4A, FLAC, WebM)
- BUD-E transkribiert den Inhalt zu Text
- Transkription wird im Chat angezeigt und kann als Datei gespeichert werden

### API-Request Format
```
POST /v1/audio/transcriptions
Content-Type: multipart/form-data

file: <audio-datei>
model: whisper-1
language: de
```

### UI-Verhalten
- Audio-Dateien werden ueber den File-Picker oder Drag&Drop hochgeladen
- BUD-E erkennt Audio-Dateien automatisch und bietet Transkription an
- Transkription wird als Text im Chat angezeigt
- Option: Als .txt oder .docx Datei speichern

### Trigger-Words
`transkribiere`, `transkription`, `was wird gesagt`, `audio zu text`, `speech to text`, `mitschrift`

### Unterstuetzte Formate
`.mp3`, `.wav`, `.ogg`, `.m4a`, `.flac`, `.webm`, `.aac`

---

## 4. Erweiterte Nachrichten-APIs

**Skill-Datei:** `skill_nachrichten.json` (erweitern)
**Status:** TODO

### Aktuelle Quellen
- tagesschau.de (DE) - implementiert

### Geplante Quellen

| Quelle | API/Methode | Sprache | Kosten |
|--------|------------|---------|--------|
| **BBC News** | RSS → JSON: `feeds.bbci.co.uk/news/rss.xml` | EN | Kostenlos |
| **Reuters** | RSS: `feeds.reuters.com/reuters/topNews` | EN | Kostenlos |
| **NPR** | RSS: `feeds.npr.org/1001/rss.xml` | EN | Kostenlos |
| **Al Jazeera** | RSS: `aljazeera.com/xml/rss/all.xml` | EN | Kostenlos |
| **DW (Deutsche Welle)** | RSS: `rss.dw.com/rdf/rss-de-all` | DE/EN | Kostenlos |
| **Spiegel Online** | RSS: `spiegel.de/schlagzeilen/index.rss` | DE | Kostenlos |
| **NewsAPI.org** | REST JSON API | Multi | 100 Req/Tag kostenlos |
| **NewsData.io** | REST JSON API | Multi | 200 Credits/Tag |

### RSS-zu-JSON Konvertierung
Fuer RSS-Quellen: Parse XML direkt in Dart oder nutze feed2json.org als Proxy:
```
https://api.rss2json.com/v1/api.json?rss_url=https://feeds.bbci.co.uk/news/rss.xml
```

### Tool-Erweiterung
```
[[tool:news source="bbc" topic="technology"]]
[[tool:news source="reuters"]]
[[tool:news source="dw" language="de"]]
```

---

## 5. Klassenarbeiten-Korrektur (bestehend, Verbesserungen)

**Skill-Datei:** `skill_klausur_korrektur.json` (bestehend)
**Status:** Implementiert, Verbesserungen geplant

### Geplante Verbesserungen
- DOCX-Ausgabe verbessern (Tabellen, Farben fuer richtig/falsch)
- Mehrere Faecher: Mathe-spezifische Bewertung, Sprach-spezifische Bewertung
- Batch-Verarbeitung: 30+ Arbeiten auf einmal
- Notenstatistik: Durchschnitt, Verteilung, Vergleich
- Export als CSV fuer Notenbuch

---

## Implementierungs-Reihenfolge

### Phase 1: Bildgenerierung
1. Skill-Datei `skill_bildgenerierung.json` anlegen
2. Tool `[[tool:generate_image ...]]` im ChatProvider
3. API-Call an `/v1/images/generations`
4. Image-Preview Widget im Chat (klickbar, Vollbild)
5. Download/Regenerieren Buttons
6. Image Editing mit Referenzbildern aus Konversation

### Phase 2: Audio-Transkription
1. Skill-Datei `skill_audio_transkription.json` anlegen
2. Audio-Dateien im File-Upload erkennen
3. Automatisch an `/v1/audio/transcriptions` senden
4. Transkription als Text anzeigen

### Phase 3: Musikgenerierung
1. Skill-Datei `skill_musikgenerierung.json` anlegen
2. Tool `[[tool:generate_music ...]]` im ChatProvider
3. API-Call an `/v1/audio/generations`
4. Audio-Player Widget im Chat
5. Download-Button

### Phase 4: Erweiterte Nachrichten
1. RSS-Parser in Dart (oder feed2json.org Proxy)
2. BBC, Reuters, DW, Spiegel als Quellen
3. Tool-Erweiterung: `[[tool:news source="bbc"]]`
4. Quellenauswahl im UI

---

## Architektur-Prinzipien

### Skill-basiertes Design
Jedes Feature wird durch eine Skill-Datei gesteuert:
```json
{
  "id": "skill_bildgenerierung",
  "title": "Skill: Bildgenerierung",
  "category": "skill",
  "content": "SKILL: BILDER GENERIEREN\n...",
  "triggerWords": ["bild", "generieren", ...],
  "relatedConcepts": ["skill_musikgenerierung"]
}
```

### Tool-Pattern
Neue Tools folgen dem bestehenden `[[tool:...]]` Muster:
```
[[tool:generate_image prompt="..." model="..." size="..." input_images="..."]]
[[tool:generate_music prompt="..." duration="30"]]
[[tool:transcribe_audio file="recording.mp3"]]
[[tool:news source="bbc" topic="..."]]
```

### UI-Rendering
Ergebnisse werden inline im Chat gerendert:
- **Bilder:** Vorschau-Thumbnail → Klick → Vollbild
- **Audio:** Eingebetteter Player mit Wellenform
- **Dateien:** FileChip mit Icon (klickbar)
- **Text:** Formatierter Text mit Markdown-Rendering
