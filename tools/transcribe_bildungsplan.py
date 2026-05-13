"""Transcribe a Bildungsplan PDF page-by-page using Vision API.

Creates a structured JSON index with per-page transcriptions including
detailed captions for diagrams/images, plus metadata (Schulform, Fach, etc.).
"""
import base64
import json
import os
import sys
import time
import urllib.request

# --- Configuration ---
MIDDLEWARE_URL = os.environ.get("BUDDY_MIDDLEWARE", "http://127.0.0.1:8787")
API_KEY = os.environ.get("BUDDY_API_KEY", "")

PAGES_DIR = r"C:\Users\chris\AppData\Roaming\ai.laion\school_bud_e_flutter\SchoolBudE\bildungsplaene\pages"
OUTPUT_JSON = r"C:\Users\chris\AppData\Roaming\ai.laion\school_bud_e_flutter\SchoolBudE\bildungsplaene\informatik_gym_sek1_hamburg.json"

# Metadata for this specific Bildungsplan
META = {
    "bundesland": "Hamburg",
    "schulform": "Gymnasium",
    "stufe": "Sekundarstufe I",
    "fach": "Informatik",
    "titel": "Bildungsplan Informatik - Gymnasium Sekundarstufe I",
    "url": "https://www.hamburg.de/resource/blob/798514/ad3c2fdfb3a32b9545a271dfceae5772/informatik-data.pdf",
    "pdf_file": "informatik_gym_sek1_hamburg.pdf",
}

SYSTEM_PROMPT = """Du bist ein Dokumenten-Transkriptor. Transkribiere diese Seite eines Bildungsplans VOLLSTAENDIG und PRAEZISE.

REGELN:
1. Transkribiere ALLEN Text auf der Seite woertlich.
2. Behalte die Struktur bei: Ueberschriften, Listen, Tabellen, Nummerierungen.
3. Fuer DIAGRAMME, BILDER, GRAFIKEN oder TABELLEN: Erstelle eine detaillierte Beschreibung in [BILD-BESCHREIBUNG: ...] Tags.
   Beispiel: [BILD-BESCHREIBUNG: Flussdiagramm zeigt den Ablauf eines Algorithmus mit den Schritten Eingabe -> Verarbeitung -> Ausgabe. Die Verarbeitung enthaelt eine Schleife mit Bedingungspruefung.]
4. Fuer TABELLEN: Gib den Inhalt strukturiert wieder mit | als Trennzeichen.
5. Behalte Seitenzahlen bei wenn sichtbar.
6. Schreibe in der Sprache des Dokuments (Deutsch).
7. Lasse NICHTS aus - jedes Detail zaehlt fuer die spaetere Suche."""


def transcribe_page(image_path: str, page_num: int) -> str:
    """Send a page image to the Vision API for transcription."""
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()

    payload = {
        "model": "auto",
        "stream": False,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": f"Transkribiere Seite {page_num} dieses Bildungsplans vollstaendig. "
                        f"Beschreibe alle Diagramme und Bilder detailliert in [BILD-BESCHREIBUNG: ...] Tags.",
                    },
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{b64}"},
                    },
                ],
            },
        ],
        "max_tokens": 4000,
    }

    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{MIDDLEWARE_URL}/v1/chat/completions",
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_KEY}",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read())
            content = result["choices"][0]["message"]["content"]
            return content
    except Exception as e:
        print(f"  ERROR page {page_num}: {e}")
        return f"[TRANSKRIPTION FEHLGESCHLAGEN: {e}]"


def main():
    # Find all page images
    pages = sorted(
        [f for f in os.listdir(PAGES_DIR) if f.startswith("page_") and f.endswith(".jpg")]
    )
    print(f"Found {len(pages)} pages to transcribe")

    # Load existing progress if any
    index_data = {
        "metadata": META,
        "created": time.strftime("%Y-%m-%d %H:%M:%S"),
        "total_pages": len(pages),
        "pages": [],
    }

    if os.path.exists(OUTPUT_JSON):
        try:
            with open(OUTPUT_JSON, "r", encoding="utf-8") as f:
                existing = json.load(f)
                index_data["pages"] = existing.get("pages", [])
                print(f"  Resuming: {len(index_data['pages'])} pages already done")
        except Exception:
            pass

    done_pages = {p["page_number"] for p in index_data["pages"]}

    for page_file in pages:
        page_num = int(page_file.replace("page_", "").replace(".jpg", ""))

        if page_num in done_pages:
            print(f"  Page {page_num}: already done, skipping")
            continue

        image_path = os.path.join(PAGES_DIR, page_file)
        print(f"  Transcribing page {page_num}/{len(pages)}...", end="", flush=True)

        start = time.time()
        content = transcribe_page(image_path, page_num)
        elapsed = time.time() - start

        page_entry = {
            "page_number": page_num,
            "content": content,
            "image_file": page_file,
            # Flatten metadata for easy BM25 indexing
            "bundesland": META["bundesland"],
            "schulform": META["schulform"],
            "stufe": META["stufe"],
            "fach": META["fach"],
            "url": META["url"],
        }

        index_data["pages"].append(page_entry)
        print(f" {len(content)} chars, {elapsed:.1f}s")

        # Save progress after each page
        with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
            json.dump(index_data, f, ensure_ascii=False, indent=2)

    print(f"\nDone! {len(index_data['pages'])} pages transcribed -> {OUTPUT_JSON}")


if __name__ == "__main__":
    # Allow overriding API key from command line
    if len(sys.argv) > 1:
        API_KEY = sys.argv[1]

    if not API_KEY:
        print("Usage: python transcribe_bildungsplan.py <API_KEY>")
        print("Or set BUDDY_API_KEY environment variable")
        sys.exit(1)

    main()
