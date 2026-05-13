"""Comprehensive skill test suite for BUD-E."""
import urllib.request
import urllib.parse
import json
import time
import os

BASE = "http://localhost:8790"


def send(t):
    url = f"{BASE}/send?text={urllib.parse.quote(t)}"
    return json.loads(urllib.request.urlopen(url, timeout=10).read())


def get(p):
    return json.loads(urllib.request.urlopen(f"{BASE}{p}", timeout=10).read())


def wait_done(timeout=60):
    for _ in range(timeout // 5):
        time.sleep(5)
        s = get("/status")
        a = get("/agents")
        done = not s["isLoading"] and (
            not a["agents"]
            or all(ag["status"] in ("completed", "error") for ag in a["agents"])
        )
        if done and s["messageCount"] > 1:
            return True
    return False


def last_assistant():
    msgs = get("/messages")
    for m in reversed(msgs["messages"]):
        if m["role"] == "assistant":
            return m["content"]
    return ""


# Wait for server
print("Waiting for server...")
for i in range(10):
    try:
        get("/status")
        print("Server ready!")
        break
    except Exception:
        time.sleep(3)

results = []


def test(name, fn):
    get("/clear")
    time.sleep(1)
    try:
        ok = fn()
        status = "PASS" if ok else "FAIL"
    except Exception as e:
        status = f"ERR({str(e)[:40]})"
        ok = False
    results.append((name, status))
    print(f"  {name:35s} {status}")
    return ok


print("=" * 55)
print("  COMPREHENSIVE SKILL TESTS")
print("=" * 55)

# 1. Weather
test(
    "1. Wetter",
    lambda: (
        send("Wie ist das Wetter in Berlin?"),
        wait_done(30),
        "tool:weather" in last_assistant()
        or any(
            w in last_assistant().lower()
            for w in ["grad", "temperatur", "°c", "wind"]
        ),
    )[-1],
)

# 2. News
test(
    "2. Nachrichten",
    lambda: (
        send("Aktuelle Nachrichten"),
        wait_done(30),
        "tool:news" in last_assistant()
        or "nachrichten" in last_assistant().lower(),
    )[-1],
)

# 3. Wikipedia
test(
    "3. Wikipedia",
    lambda: (
        send("Was ist Photosynthese?"),
        wait_done(30),
        "tool:wikipedia" in last_assistant()
        or "licht" in last_assistant().lower()
        or "pflanze" in last_assistant().lower(),
    )[-1],
)

# 4. Memory
test(
    "4. Gedaechtnis",
    lambda: (
        send("Merke dir: Mein Lieblingsessen ist Pizza"),
        wait_done(20),
        "tool:memory_save" in last_assistant()
        or "gemerkt" in last_assistant().lower()
        or "pizza" in last_assistant().lower(),
    )[-1],
)

# 5. Image
test(
    "5. Bild generieren",
    lambda: (
        send("Male mir eine Katze"),
        wait_done(30),
        "tool:generate_image" in last_assistant(),
    )[-1],
)

# 6. Music
test(
    "6. Musik generieren",
    lambda: (
        send("Komponiere Klaviermusik"),
        wait_done(30),
        "tool:generate_music" in last_assistant(),
    )[-1],
)

# 7. DOCX
test(
    "7. Word-Datei (Agent)",
    lambda: (
        send("Schreib ein Gedicht als Word-Datei"),
        wait_done(30),
        any(
            "tool:run_agent" in m["content"]
            for m in get("/messages")["messages"]
        ),
    )[-1],
)

# 8. HTML
test(
    "8. HTML-Datei (Agent)",
    lambda: (
        send("Erstelle eine HTML-Seite ueber Katzen"),
        wait_done(30),
        any(
            "tool:run_agent" in m["content"]
            for m in get("/messages")["messages"]
        ),
    )[-1],
)

# 9. Presentation (PPTX)
test(
    "9. Praesentation (PPTX Agent)",
    lambda: (
        send("Erstelle eine PowerPoint Praesentation ueber KI"),
        wait_done(60),
        any(
            "tool:run_agent" in m["content"]
            for m in get("/messages")["messages"]
        ),
    )[-1],
)

# 10. Typos
test(
    "10. Tippfehler-Toleranz",
    lambda: (
        send("Wie is das Weter in Hmburg?"),
        wait_done(30),
        "tool:weather" in last_assistant()
        or any(
            w in last_assistant().lower()
            for w in ["grad", "temperatur", "hamburg", "wind"]
        ),
    )[-1],
)

# 11. Imprecise
test(
    "11. Unpraezise Anfrage",
    lambda: (
        send("erzaehl mir was ueber istanbul"),
        wait_done(30),
        "tool:wikipedia" in last_assistant()
        or "istanbul" in last_assistant().lower(),
    )[-1],
)

# 12. Long answer
test(
    "12. Lange Antwort",
    lambda: (
        send("Erklaere Quantenmechanik ausfuehrlich"),
        wait_done(30),
        len(last_assistant()) > 300,
    )[-1],
)

# Summary
print()
print("=" * 55)
passed = sum(1 for _, s in results if s == "PASS")
total = len(results)
print(f"  {passed}/{total} Skills bestanden")
print("=" * 55)
if passed < total:
    print("  Fehlgeschlagen:")
    for name, status in results:
        if status != "PASS":
            print(f"    {name}: {status}")
