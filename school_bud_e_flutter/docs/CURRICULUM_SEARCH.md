# Curriculum Search (Bildungsplan)

BUD-E can search through indexed education curricula using BM25 ranking and return results with exact page numbers and clickable PDF links.

## How It Works

### 1. Indexing Pipeline
Education plan PDFs are processed offline:

```
PDF → Pages (JPEG at 150-200 DPI) → Vision API Transcription → JSON Index
```

Each page becomes a searchable entry with:
- **Full transcription** of all text
- **[BILD-BESCHREIBUNG: ...]** tags for diagrams and images
- **Metadata**: Bundesland, Schulform, Fach, Stufe, page number, PDF URL

### 2. BM25 Search Engine
Pure Dart implementation (no external dependencies):
- Parameters aligned with zvec/dashtext: k1=1.2, b=0.75
- German stopword removal
- Umlaut normalization (ä→ae, ö→oe, ü→ue, ß→ss)
- Optional filters: Fach, Schulform, Stufe
- Snippet extraction with query term highlighting

### 3. Result Presentation
Each result includes:
- Page number and source reference
- Original quote (snippet)
- Clickable PDF link with page anchor: `URL#page=27`

## Currently Indexed

32 Hamburg Bildungspläne, 1,548 pages:

| Schulform | Fächer |
|-----------|--------|
| Gymnasium Sek I | Englisch, Mathematik, Biologie, Chemie, Physik, Informatik, Geschichte, Geographie, Sport, Neuere Fremdsprachen |
| Gymnasium Studienstufe | Deutsch, Englisch, Mathematik, Biologie, Chemie, Informatik, Geographie, Psychologie, Sport |
| Stadtteilschule | Deutsch, Mathematik, Chemie, Physik, Religion, Gesellschaftswissenschaften, Wirtschaft |
| Grundschule | Deutsch, Englisch, Mathematik, Sachunterricht, Aufgabengebiete |

## Adding New Curricula

Use the indexer tool:

```bash
# Edit BILDUNGSPLAENE list in the script to add new PDFs
python tools/index_all_bildungsplaene.py YOUR_API_KEY
```

The indexer:
- Downloads PDFs
- Converts pages to JPEG (PyMuPDF at 150 DPI)
- Transcribes each page via Vision API (with diagram captions)
- Saves progress after each page (resume-capable)
- Creates JSON index files in the `bildungsplaene/` directory

BUD-E loads all JSON files from `bildungsplaene/` on startup.

## Tool Syntax

```
[[tool:bildungsplan_search query="neuronale Netzwerke" fach="Informatik" schulform="Gymnasium"]]
```

Both `fach` and `schulform` are optional filters. Without them, all indexed curricula are searched.
