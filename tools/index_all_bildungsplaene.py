"""Download and index all Hamburg Bildungsplan PDFs.

Downloads PDFs, converts each page to JPEG, transcribes via Vision API,
and creates structured JSON index files for BM25 search.

Usage: python index_all_bildungsplaene.py <API_KEY>
"""
import base64
import json
import os
import sys
import time
import urllib.request
import urllib.error

# --- Configuration ---
MIDDLEWARE_URL = os.environ.get("BUDDY_MIDDLEWARE", "http://127.0.0.1:8787")
BASE_DIR = os.path.join(
    os.environ.get("APPDATA", os.path.expanduser("~")),
    "ai.laion", "school_bud_e_flutter", "SchoolBudE", "bildungsplaene"
)

# All Hamburg Bildungsplan PDFs organized by Schulform
BILDUNGSPLAENE = [
    # === GYMNASIUM SEKUNDARSTUFE I ===
    {"url": "https://www.hamburg.de/resource/blob/122934/59b37bbb0712d24e773de536ce879146/deutsch-gym-seki-2022-data.pdf",
     "fach": "Deutsch", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/122938/ea8fcb338d06e068c1e13091afa61761/englisch-gym-seki-2022-data.pdf",
     "fach": "Englisch", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/122944/62db046dc3abf1ed671370d8c8b36c65/mathematik-gym-seki-2022-data.pdf",
     "fach": "Mathematik", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/798502/9849cd02ad9dd005afc904a535de5430/biologie-data.pdf",
     "fach": "Biologie", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/798504/525ea40e785e1788a07082bfd216a72d/chemie-data.pdf",
     "fach": "Chemie", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/798534/4cf0047ad61effacd1ff7e6ad819fa41/physik-data.pdf",
     "fach": "Physik", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/798514/ad3c2fdfb3a32b9545a271dfceae5772/informatik-data.pdf",
     "fach": "Informatik", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/798512/1bced517d508b24e60871e63d286ea6c/geschichte-data.pdf",
     "fach": "Geschichte", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/798508/861434f03667554b884d3fba9e747ecc/geographie-data.pdf",
     "fach": "Geographie", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/798556/8c90560accc1930b1a1a7bbf54739320/sport-data.pdf",
     "fach": "Sport", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/123472/fb22fd8021266345b50c060fc2220c95/neuere-fremdsprachen-gym-seki-data.pdf",
     "fach": "Neuere Fremdsprachen", "schulform": "Gymnasium", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},

    # === STADTTEILSCHULE ===
    {"url": "https://www.hamburg.de/resource/blob/122960/040b603ce22aae363c298d51757270ee/deutsch-sts-2022-data.pdf",
     "fach": "Deutsch", "schulform": "Stadtteilschule", "stufe": "Jahrgangsstufen 5-11", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/122964/3812266b9334c5b6d4e13c1971939d98/englisch-sts-2022-data.pdf",
     "fach": "Englisch", "schulform": "Stadtteilschule", "stufe": "Jahrgangsstufen 5-11", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/122968/91ab0af4949763ef650814c06a77d127/mathematik-sts-2022-data.pdf",
     "fach": "Mathematik", "schulform": "Stadtteilschule", "stufe": "Jahrgangsstufen 5-11", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/122972/b751f40ba1fb502ab0a3913aad133ffa/religion-sts-2022-data.pdf",
     "fach": "Religion", "schulform": "Stadtteilschule", "stufe": "Jahrgangsstufen 5-11", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/119916/dd9e3ba21f14872c2a3233894573e62b/physik-sts-data.pdf",
     "fach": "Physik", "schulform": "Stadtteilschule", "stufe": "Jahrgangsstufen 7-11", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/798370/d2ebe12ab087b60136959e18fc89074a/chemie-data.pdf",
     "fach": "Chemie", "schulform": "Stadtteilschule", "stufe": "Jahrgangsstufen 5-11", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/798442/a1aa5711bae16bddfcfc3cc6760318cb/wirtschaft-data.pdf",
     "fach": "Wirtschaft", "schulform": "Stadtteilschule", "stufe": "Sekundarstufe I", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/119846/841203fdcaae59077908b21f9cb3af5e/lb-gesellschaftswissenschaften-sts-data.pdf",
     "fach": "Gesellschaftswissenschaften", "schulform": "Stadtteilschule", "stufe": "Jahrgangsstufen 5-11", "bundesland": "Hamburg"},

    # === GRUNDSCHULE ===
    {"url": "https://www.hamburg.de/resource/blob/122874/aacaaaccee5fe7b6d13400ccc89589ee/deutsch-gs-2022-data.pdf",
     "fach": "Deutsch", "schulform": "Grundschule", "stufe": "Jahrgangsstufen 1-4", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/122898/35b9d1599f2fa43cc76f979697addfe3/mathematik-gs-2022-data.pdf",
     "fach": "Mathematik", "schulform": "Grundschule", "stufe": "Jahrgangsstufen 1-4", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/122890/4b72869d52ce04307b957f15e256795a/englisch-gs-2022-data.pdf",
     "fach": "Englisch", "schulform": "Grundschule", "stufe": "Jahrgangsstufen 1-4", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/122914/bea7592db01da8657f1c412bfbb0eb08/sachunterricht-gs-2022-data.pdf",
     "fach": "Sachunterricht", "schulform": "Grundschule", "stufe": "Jahrgangsstufen 1-4", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/122882/dcc8b50423d6895825a611a1278cd345/aufgabegebiete-gs-2022-data.pdf",
     "fach": "Aufgabengebiete", "schulform": "Grundschule", "stufe": "Jahrgangsstufen 1-4", "bundesland": "Hamburg"},

    # === STUDIENSTUFE (Oberstufe) ===
    {"url": "https://www.hamburg.de/resource/blob/123046/1e58f3be0860bd56fcf3402fd10bcde5/deutsch-gyo-2022-data.pdf",
     "fach": "Deutsch", "schulform": "Gymnasium", "stufe": "Studienstufe", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/122990/8be6c0cd2aef732c3931bab3dc97c664/fsp-englisch-gyo-2022-data.pdf",
     "fach": "Englisch", "schulform": "Gymnasium", "stufe": "Studienstufe", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/123074/23276415bdfb32ba8bb652f7c1998a4c/mathematik-gyo-2022-data.pdf",
     "fach": "Mathematik", "schulform": "Gymnasium", "stufe": "Studienstufe", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/123038/52efc40f9172394cea670444018b89a3/biologie-gyo-2022-data.pdf",
     "fach": "Biologie", "schulform": "Gymnasium", "stufe": "Studienstufe", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/123042/e19828c45238e198fc9cfc2a73777685/chemie-gyo-2022-data.pdf",
     "fach": "Chemie", "schulform": "Gymnasium", "stufe": "Studienstufe", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/123070/43be4b064591b08ff467d3a6dcbb3422/informatik-gyo-2022-data.pdf",
     "fach": "Informatik", "schulform": "Gymnasium", "stufe": "Studienstufe", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/123062/2d0432531247b6facba147b63e79328f/geographie-gyo-2022-data.pdf",
     "fach": "Geographie", "schulform": "Gymnasium", "stufe": "Studienstufe", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/123098/d7a3b747142bce77013ab01fced4112b/psychologie-gyo-2022-data.pdf",
     "fach": "Psychologie", "schulform": "Gymnasium", "stufe": "Studienstufe", "bundesland": "Hamburg"},
    {"url": "https://www.hamburg.de/resource/blob/123114/1811dfd629b6d16f2c659c03a05a46ce/sport-gyo-2022-data.pdf",
     "fach": "Sport", "schulform": "Gymnasium", "stufe": "Studienstufe", "bundesland": "Hamburg"},
]

SYSTEM_PROMPT = """Du bist ein Dokumenten-Transkriptor. Transkribiere diese Seite eines Bildungsplans VOLLSTAENDIG und PRAEZISE.

REGELN:
1. Transkribiere ALLEN Text auf der Seite woertlich.
2. Behalte die Struktur bei: Ueberschriften, Listen, Tabellen, Nummerierungen.
3. Fuer DIAGRAMME, BILDER, GRAFIKEN oder TABELLEN: Erstelle eine detaillierte Beschreibung in [BILD-BESCHREIBUNG: ...] Tags.
4. Fuer TABELLEN: Gib den Inhalt strukturiert wieder mit | als Trennzeichen.
5. Behalte Seitenzahlen bei wenn sichtbar.
6. Schreibe in der Sprache des Dokuments (Deutsch).
7. Lasse NICHTS aus - jedes Detail zaehlt fuer die spaetere Suche."""


def safe_filename(meta):
    """Generate a safe filename from metadata."""
    import re
    parts = [
        meta["fach"].lower(),
        meta["schulform"].lower(),
        meta["stufe"].lower(),
        meta["bundesland"].lower(),
    ]
    name = "_".join(parts)
    # Remove any non-ASCII and special chars
    name = re.sub(r'[^a-z0-9_]', '_', name)
    name = re.sub(r'_+', '_', name).strip('_')
    return name + ".json"


def download_pdf(url, dest_path):
    """Download a PDF file."""
    if os.path.exists(dest_path) and os.path.getsize(dest_path) > 1000:
        return True  # Already downloaded
    try:
        urllib.request.urlretrieve(url, dest_path)
        return True
    except Exception as e:
        print(f"  ERROR downloading: {e}")
        return False


def pdf_to_jpegs(pdf_path, output_dir):
    """Convert PDF pages to JPEG images."""
    import fitz
    os.makedirs(output_dir, exist_ok=True)

    existing = [f for f in os.listdir(output_dir) if f.endswith(".jpg")]
    doc = fitz.open(pdf_path)
    if len(existing) == len(doc):
        doc.close()
        return len(existing)  # Already converted

    for i, page in enumerate(doc):
        img_path = os.path.join(output_dir, f"page_{i+1:03d}.jpg")
        if not os.path.exists(img_path):
            pix = page.get_pixmap(dpi=150)  # 150 DPI (balance quality/speed)
            pix.save(img_path)

    count = len(doc)
    doc.close()
    return count


def transcribe_page(image_path, page_num, api_key):
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
                    {"type": "text", "text": f"Transkribiere Seite {page_num} vollstaendig. Beschreibe Diagramme in [BILD-BESCHREIBUNG: ...] Tags."},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                ],
            },
        ],
        "max_tokens": 4000,
    }

    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{MIDDLEWARE_URL}/v1/chat/completions",
        data=data,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read())
            return result["choices"][0]["message"]["content"]
    except Exception as e:
        return f"[TRANSKRIPTION FEHLGESCHLAGEN: {e}]"


def process_bildungsplan(meta, api_key):
    """Process a single Bildungsplan: download, convert, transcribe, index."""
    filename = safe_filename(meta)
    json_path = os.path.join(BASE_DIR, filename)

    # Check if already fully indexed
    if os.path.exists(json_path):
        with open(json_path, "r", encoding="utf-8") as f:
            existing = json.load(f)
        existing_pages = len(existing.get("pages", []))
        if existing_pages > 0:
            # Check if all pages are done
            bad = sum(1 for p in existing["pages"] if "FEHLGESCHLAGEN" in p.get("content", ""))
            if bad == 0:
                print(f"  Already indexed: {filename} ({existing_pages} pages)")
                return existing_pages

    print(f"  Processing: {meta['fach']} ({meta['schulform']}, {meta['stufe']})")

    # 1. Download PDF
    pdf_dir = os.path.join(BASE_DIR, "pdfs")
    os.makedirs(pdf_dir, exist_ok=True)
    pdf_name = os.path.basename(meta["url"])
    pdf_path = os.path.join(pdf_dir, f"{meta['schulform'].lower()}_{pdf_name}")

    if not download_pdf(meta["url"], pdf_path):
        return 0

    # 2. Convert to JPEGs
    pages_dir = os.path.join(BASE_DIR, "pages", filename.replace(".json", ""))
    page_count = pdf_to_jpegs(pdf_path, pages_dir)
    print(f"    {page_count} pages")

    # 3. Load existing progress
    index_data = {
        "metadata": meta,
        "created": time.strftime("%Y-%m-%d %H:%M:%S"),
        "total_pages": page_count,
        "pages": [],
    }
    if os.path.exists(json_path):
        try:
            with open(json_path, "r", encoding="utf-8") as f:
                existing = json.load(f)
                index_data["pages"] = [
                    p for p in existing.get("pages", [])
                    if "FEHLGESCHLAGEN" not in p.get("content", "")
                ]
        except Exception:
            pass

    done_pages = {p["page_number"] for p in index_data["pages"]}

    # 4. Transcribe each page
    page_files = sorted([
        f for f in os.listdir(pages_dir)
        if f.startswith("page_") and f.endswith(".jpg")
    ])

    for page_file in page_files:
        page_num = int(page_file.replace("page_", "").replace(".jpg", ""))
        if page_num in done_pages:
            continue

        image_path = os.path.join(pages_dir, page_file)
        print(f"    Transcribing page {page_num}/{page_count}...", end="", flush=True)

        start = time.time()
        content = transcribe_page(image_path, page_num, api_key)
        elapsed = time.time() - start

        index_data["pages"].append({
            "page_number": page_num,
            "content": content,
            "image_file": page_file,
            "bundesland": meta["bundesland"],
            "schulform": meta["schulform"],
            "stufe": meta["stufe"],
            "fach": meta["fach"],
            "url": meta["url"],
        })

        print(f" {len(content)} chars, {elapsed:.1f}s")

        # Save progress after each page
        try:
            # Truncate extremely large page transcriptions (LLM hallucination)
            if len(content) > 15000:
                content = content[:15000] + "\n...(gekuerzt)"
                index_data["pages"][-1]["content"] = content
            with open(json_path, "w", encoding="utf-8") as f:
                json.dump(index_data, f, ensure_ascii=False, indent=2)
        except OSError as e:
            print(f"\n    SAVE ERROR: {e} - trying without indent...")
            try:
                with open(json_path, "w", encoding="utf-8") as f:
                    json.dump(index_data, f, ensure_ascii=False)
            except OSError as e2:
                print(f"    FATAL SAVE ERROR: {e2}")

    return len(index_data["pages"])


def main():
    if len(sys.argv) < 2:
        print("Usage: python index_all_bildungsplaene.py <API_KEY>")
        sys.exit(1)

    api_key = sys.argv[1]
    os.makedirs(BASE_DIR, exist_ok=True)

    print(f"=== Hamburg Bildungsplan Indexer ===")
    print(f"Output: {BASE_DIR}")
    print(f"Plans to index: {len(BILDUNGSPLAENE)}")
    print()

    total_pages = 0
    for i, meta in enumerate(BILDUNGSPLAENE):
        print(f"[{i+1}/{len(BILDUNGSPLAENE)}] {meta['fach']} - {meta['schulform']} ({meta['stufe']})")
        pages = process_bildungsplan(meta, api_key)
        total_pages += pages
        print()

    print(f"=== Done! Total: {total_pages} pages indexed across {len(BILDUNGSPLAENE)} plans ===")


if __name__ == "__main__":
    main()
