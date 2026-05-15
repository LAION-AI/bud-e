# Agent-Frameworks für BUD-E auf Android

**Ziel:** BUD-E soll auf Android einen Agenten spawnen können, der eigenständig Dateien liest/schreibt (z.B. PDFs), Websuchen durchführt, Daten herunterlädt und mehrstufige Aufgaben löst — alles über den bereits vorhandenen API-Key.

---

## Architektur-Optionen

| Ansatz | Beschreibung | Komplexität |
|---|---|---|
| **A) Dart-native** | Agent-Loop direkt in Dart/Flutter | Niedrig |
| **B) Embedded Python** | Python-Agent via Chaquopy in der App | Mittel-Hoch |
| **C) Backend-Agent** | Agent läuft auf dem Middleware-Server | Niedrig-Mittel |

---

## Ansatz A: Dart-native Agent Frameworks

### 1. neomage — "Claude Code in Dart"

- **Pub.dev:** [neomage](https://pub.dev/packages/neomage)
- **Lizenz:** MIT

**Was es kann:**
- Agnostische AI-Agent-Engine für Flutter
- **31 eingebaute Tools** inkl. Bash, FileRead, FileWrite, FileEdit, Grep, Glob, WebSearch, Agent (Sub-Agents)
- Automatischer Multi-Turn Execution Loop
- MCP-Support (Model Context Protocol)
- 283 ladbare Markdown-Skills in 40+ Kategorien
- 12 modulare Personality-Module (Identity, Cognition, Tools, Agency, Memory, etc.)
- Multi-Provider: Gemini, OpenAI, Anthropic, DeepSeek, Qwen, Ollama
- SSE-Streaming mit typisierten Events (TextDelta, ToolUseStart, ThinkingDelta)
- Gemini Live Realtime Voice/Audio WebSocket Client
- UI-Komponenten: Chat, Settings, Onboarding, Command Palette, Session Browser

**Vorteile:**
- Am nächsten an dem was BUD-E braucht — quasi ein fertiger Agent mit File-Ops + Web
- 31 Tools out of the box, kein eigenes Bauen nötig
- MCP-Support öffnet riesiges Tool-Ökosystem
- Personality/Skills-System passt zu BUD-Es Persona-Konzept
- Streaming-Events für Echtzeit-UI-Updates

**Nachteile:**
- Relativ neues Package, kleinere Community
- Möglicherweise Overhead durch 283 Skills die man nicht alle braucht
- Eigene UI-Komponenten könnten mit BUD-Es UI kollidieren
- Stabilität auf Android-Devices noch nicht breit getestet

**Aufwand für BUD-E:** ~2-3 Tage Integration. Tools sind fertig, man muss nur den Agent-Runner an BUD-Es Chat-Flow anbinden und den API-Key durchreichen.

**Bewertung: Sehr vielversprechend — das umfangreichste Dart-native Framework.**

---

### 2. dart_agent_core — "Mobile-First Agent Loop"

- **Pub.dev:** [dart_agent_core](https://pub.dev/packages/dart_agent_core)
- **Lizenz:** MIT

**Was es kann:**
- Mobile-first, local-first Agentic Loop
- Tool Use mit JSON Schema Definitionen (jede Dart-Funktion wird zum Tool)
- State Persistence via FileStateStorage (JSON auf Disk)
- Multi-Turn Memory mit Context Management
- Sub-Agent Delegation
- Streaming via `runStream()` mit typisierten Events (Model-Chunks, Tool-Calls, Retries)
- **Context Compression**: LLM-basierter Kompressor summariert alte Nachrichten zu episodischem Memory
- Built-in `retrieve_memory` Tool zum Abrufen alter Nachrichten
- Skill-System: modulare Capabilities mit eigenen System-Prompts und Tools
- Skills können `forceActivate` oder dynamisch vom Agent toggled werden
- Provider: OpenAI, Gemini, AWS Bedrock

**Vorteile:**
- Explizit für Flutter/Mobile designed
- Context Compression + Memory ist fast identisch mit BUD-Es Architektur
- Skill-System passt perfekt zu BUD-Es Persona/Agent-Konzept
- Streaming-Events für Flutter-UI (kein Polling)
- State Persistence auf Disk — überlebt App-Neustarts
- Leichtgewichtig, keine riesige Dependency-Chain

**Nachteile:**
- Weniger eingebaute Tools als neomage (man muss File/Web-Tools selbst wrappen)
- Neues Package, Community-Größe unklar
- AWS Bedrock Support relevant? (BUD-E nutzt eigene Middleware)

**Aufwand für BUD-E:** ~2-4 Tage. Agent-Loop ist fertig, man definiert eigene Tools (FileRead, FileWrite, WebSearch, PDF) und bindet es an den API-Key.

**Bewertung: Beste Architektur-Passung zu BUD-E — Memory + Context Compression sind fast identisch.**

---

### 3. Genkit Dart (Google)

- **Pub.dev:** [genkit](https://pub.dev/packages/genkit)
- **Docs:** [genkit.dev](https://genkit.dev/docs/dart/tool-calling/)
- **Lizenz:** Apache 2.0
- **Maintained by:** Google (offizielle Dart-Blog-Ankündigung März 2026)

**Was es kann:**
- Unified Interface für Text-Generierung, Structured Output, Tool Calling, Agentic Workflows
- `ai.defineTool()` für Tool-Definitionen
- Flows: testbare, observable, deploybare Funktionen mit typisierten Inputs/Outputs
- Multi-Agent Patterns
- RAG-Helpers
- Observability Layer (Tracing, Logging)
- Provider: Google Gemini, OpenAI, Anthropic (via Plugins)
- `genkit_middleware` Package mit Tool Approval, Filesystem Access, Skills

**Vorteile:**
- Von Google maintained → langfristig stabil
- Offizielle Flutter/Dart-Integration
- Backend kann Tool-Chains ohne Round-Trip zum Client ausführen
- Observability built-in (wichtig für Debugging)
- `genkit_middleware` hat bereits Filesystem-Access

**Nachteile:**
- Primär für Server-seitige Dart-Apps designed (nicht explizit mobile-first)
- Google-zentrisch (Gemini-First), andere Provider via Plugins
- Relativ neu (März 2026), API könnte sich noch ändern
- Weniger "Agent-Loop" und mehr "Flow-Pipeline"

**Aufwand für BUD-E:** ~3-5 Tage. Gute Basis, aber Agent-Loop muss um Flows herum gebaut werden.

**Bewertung: Solide Langzeit-Wette, aber weniger "Agent" und mehr "AI-Toolkit".**

---

### 4. Agenix — "Multi-Agent für Flutter"

- **Pub.dev:** [agenix 2.1.0](https://pub.dev/packages/agenix)
- **Lizenz:** MIT

**Was es kann:**
- Multi-Agent Framework für Flutter & Dart
- Agent-Chains: Aufgaben werden automatisch an Sub-Agents delegiert
- Tool Registry mit automatischer Parameter-Deduktion
- DataStore-Abstraction (Firebase, Custom)
- Memory über Conversations hinweg
- Zwei Tool-Typen: mit und ohne Parameter

**Vorteile:**
- Multi-Agent-Chains out of the box (Orchestrator → News Agent → Favourites Agent)
- Saubere Architektur (Agent, DataStore, ToolRegistry als separate Concerns)
- Agent deduciert Parameter aus User-Input oder fragt nach
- Flutter-native mit Widget-Integration

**Nachteile:**
- Weniger eingebaute Tools (man definiert alles selbst)
- Fokus auf Chat-Agents, nicht auf File-Operations
- Gemini-zentrisch (andere Provider möglich aber nicht prominent)
- Kleiner als dart_agent_core/neomage

**Aufwand für BUD-E:** ~3-4 Tage. Gutes Multi-Agent-Pattern, aber Tools müssen selbst gebaut werden.

**Bewertung: Interessant für Multi-Agent-Orchestrierung, weniger für File-/Web-Ops.**

---

### 5. dartantic_ai — "pydantic-ai für Dart"

- **Pub.dev:** [dartantic_ai](https://pub.dev/packages/dartantic_ai)
- **Docs:** [docs.dartantic.ai](https://docs.dartantic.ai/)
- **Lizenz:** MIT
- **Aktuell:** v2.1.1

**Was es kann:**
- Inspiriert von Python's pydantic-ai
- Multi-Step Tool Calling: Agent chainet Tool-Calls autonom
- `ToolCallingMode.multiStep` (default) vs `.singleStep`
- Unified API über alle Provider (OpenAI, Google, Anthropic, Mistral, Cohere, Ollama, OpenRouter, xAI)
- Structured Output mit Type-Safety
- Conversation History über Model-Wechsel hinweg

**Vorteile:**
- Breiteste Provider-Unterstützung aller Dart-Frameworks (8+ Provider)
- Multi-Step Tool Calling eingebaut und konfigurierbar
- Kann Models mitten in der Conversation wechseln
- CalPal-Example: voller Agent in ~300 Zeilen Code
- Aktiv maintained (v2.1.1, regelmäßige Changelogs)

**Nachteile:**
- Keine eingebauten Tools (alles selbst definieren)
- Kein Memory/Persistence-System
- Kein Streaming (nur Request-Response)
- Weniger "Framework" und mehr "Tool-Calling-SDK"

**Aufwand für BUD-E:** ~2-3 Tage. Sauber für den Tool-Calling-Layer, aber Memory/Streaming muss BUD-E selbst machen.

**Bewertung: Bestes Tool-Calling-SDK, aber kein vollständiges Agent-Framework.**

---

### 6. LangChain.dart

- **Repo:** [github.com/davidmigloz/langchain_dart](https://github.com/davidmigloz/langchain_dart)
- **Pub.dev:** [langchain 0.8.1](https://pub.dev/packages/langchain)
- **Docs:** [langchaindart.dev](https://langchaindart.dev/)
- **Lizenz:** MIT
- **Stars:** ~500

**Was es kann:**
- Dart-Port des Python LangChain Frameworks
- Agents mit Tool-Calling (Function Calling)
- Document Loaders, Text Splitter, Embeddings, Vector Stores
- RAG (Retrieval-Augmented Generation)
- Chains und LangChain Expression Language (LCEL)
- Streaming-Support
- Provider: OpenAI, Google, Mistral, Ollama, etc.

**Vorteile:**
- Bekanntester Name im AI-Framework-Space
- RAG-Pipeline am ausgereiftesten aller Dart-Frameworks
- Modularer Aufband — nur importieren was man braucht
- Aktiv maintained (Updates April 2026)

**Nachteile:**
- Deutlich weniger Tools/Integrationen als Python-LangChain
- Agent-Loop simpler (kein LangGraph in Dart)
- Manche Document Loaders fehlen

**Aufwand für BUD-E:** ~2-3 Tage.

**Bewertung: Bestes RAG-Framework in Dart, aber als Agent-Framework hinter neomage/dart_agent_core.**

---

### 7. Murmuration

- **Repo:** [github.com/AgnivaMaiti/murmuration](https://github.com/AgnivaMaiti/murmuration)
- **Pub.dev:** [murmuration](https://pub.dev/packages/murmuration)
- **Lizenz:** MIT

**Was es kann:**
- Multi-Agent Orchestration in Dart
- Provider: OpenAI, Google, Anthropic (mit Streaming)
- Caching mit TTL-Support
- Custom Tools mit Auth-Requirements und Metadata
- State Management
- Configurable Logging

**Vorteile:**
- Saubere Multi-Provider-Abstraction
- Tool-Auth-System (Metadata + Validation)
- Caching eingebaut

**Nachteile:**
- Kleineres Projekt, weniger Features als die Top-Kandidaten
- Kein Memory-System
- Keine eingebauten Tools

**Bewertung: Solide Basis, aber weniger Feature-reich als die Alternativen.**

---

### 8. Eigener Agent-Loop in Dart (DIY)

BUD-E hat **bereits einen Tool-Call-Mechanismus** (`[[tool:memory_search]]`, `[[tool:wikipedia]]`, `[[tool:memory_save]]`). Man erweitert diesen:

```dart
final tools = {
  'file_read': (args) => File(args['path']).readAsString(),
  'file_write': (args) => File(args['path']).writeAsString(args['content']),
  'web_search': (args) => _searchDuckDuckGo(args['query']),
  'web_fetch': (args) => http.get(Uri.parse(args['url'])),
  'pdf_read': (args) => _extractPdfText(args['path']),
  'pdf_write': (args) => _generatePdf(args['content'], args['path']),
};
```

**Aufwand:** ~1-2 Tage Basis, ~1 Woche robuster Multi-Step Agent.

**Bewertung: Maximale Kontrolle, aber mehr Eigenarbeit.**

---

## Ansatz B: Embedded Python auf Android

### 9. smolagents (Hugging Face) via Chaquopy

- **Repo:** [github.com/huggingface/smolagents](https://github.com/huggingface/smolagents)
- **Stars:** ~15k+

Minimalistisches Python-Agent-Framework (~1000 LOC), Code-First, `@tool` Decorator. Braucht Chaquopy auf Android.

**Problem:** Chaquopy friert Packages beim Build ein, APK +50-100MB, async-Kompatibilität unsicher.

### 10. OpenAI Agents SDK via Chaquopy

- **Repo:** [github.com/openai/openai-agents-python](https://github.com/openai/openai-agents-python)
- **Stars:** ~20k+

Multi-Agent mit Handoffs, Guardrails, Sandbox. Schwer auf Android wegen Pydantic + async.

**Fazit Ansatz B:** Python auf Android ist fragil. Nur sinnvoll wenn man unbedingt ein spezifisches Python-Package braucht.

---

## Ansatz C: Backend-Agent (Middleware)

### 11. Agent auf dem Admin_Bud-E Server

Der Middleware-Server bekommt einen Agent-Endpoint. Flutter-App sendet Aufgabe + Dateien, Server führt aus.

**Vorteil:** Volle Python/Node.js-Umgebung, beliebige Packages.
**Nachteil:** Kein Zugriff auf lokale Dateien, Latenz bei großen Uploads.

---

## Vergleichsmatrix (Dart-native Frameworks)

| Kriterium | neomage | dart_agent_core | Genkit | Agenix | dartantic_ai | LangChain.dart |
|---|---|---|---|---|---|---|
| **Eingebaute Tools** | 31 | Wenige | Via Middleware | Keine | Keine | Keine |
| **Multi-Step Agent** | Ja (auto) | Ja (loop) | Ja (flows) | Ja (chains) | Ja (multiStep) | Ja (chains) |
| **Memory/Persistence** | Skills | Context Compression | Flows | DataStore | Nein | Nein |
| **MCP-Support** | Ja | Nein | Nein | Nein | Nein | Nein |
| **Streaming** | SSE-Events | runStream() | Ja | Nein | Nein | Ja |
| **Multi-Provider** | 6+ | 3 | 3+ (Plugins) | 1-2 | 8+ | 5+ |
| **Sub-Agents** | Ja | Ja | Multi-Agent | Ja (Chains) | Nein | Nein |
| **File-Ops built-in** | Ja | Nein | Via Middleware | Nein | Nein | Nein |
| **Web-Search built-in** | Ja | Nein | Nein | Nein | Nein | Nein |
| **Maintained by** | Community | Community | Google | Community | Community | Community |
| **Aufwand für BUD-E** | 2-3 Tage | 2-4 Tage | 3-5 Tage | 3-4 Tage | 2-3 Tage | 2-3 Tage |

---

## Empfehlung

### Top-Empfehlung: **neomage + dart_agent_core Hybrid**

| Schicht | Framework | Warum |
|---|---|---|
| **Tool Execution** | neomage | 31 eingebaute Tools (File, Web, Bash, Grep, Glob) — kein eigenes Bauen |
| **Agent Loop + Memory** | dart_agent_core | Context Compression, State Persistence, Skill-System — passt zu BUD-Es Memory-Architektur |
| **RAG (optional)** | LangChain.dart | Document Loaders, Embeddings, Vector Stores für große Dokumente |

### Warum dieser Stack?

1. **neomage liefert die Tools fertig** — FileRead, FileWrite, FileEdit, Bash, WebSearch, Grep, Glob, Sub-Agents sind alle eingebaut. Man muss sie nicht selbst implementieren.

2. **dart_agent_core liefert den Agent-Loop** — Multi-Turn mit Context Compression und Memory ist fast identisch mit BUD-Es bestehendem System. Die Skill-Architektur (forceActivate / dynamisch toggle) passt perfekt.

3. **Alles reines Dart** — kein Python, kein Chaquopy, kein APK-Bloat. Funktioniert auf Android, iOS, Web, Desktop.

4. **API-Key wird durchgereicht** — Beide Frameworks unterstützen OpenAI-kompatible Endpoints. BUD-Es Middleware (`/v1/chat/completions`) funktioniert direkt.

### Konkreter Implementierungsplan

```
Phase 1 (2-3 Tage):
  - neomage als Dependency hinzufügen
  - AgentRunner-Klasse die neomages Tool-System nutzt
  - API-Key + Middleware-URL durchreichen
  - Multi-Step-Loop mit Fortschrittsanzeige ("Schritt 3/10")
  - Basis-Tools aktivieren: FileRead, FileWrite, WebSearch

Phase 2 (1-2 Tage):
  - dart_agent_core für Context Compression integrieren
  - Agent-State auf Disk persistieren (überlebt App-Neustart)
  - Agent-Memory an BUD-Es Memory-System anbinden

Phase 3 (1-2 Tage):
  - PDF-Tools (via syncfusion_flutter_pdf + pdf Package)
  - Download-Tool (Dateien aus dem Internet)
  - Sandbox: Welche Ordner darf der Agent lesen/schreiben?

Phase 4 (optional):
  - LangChain.dart für RAG bei großen Dokumenten
  - MCP-Server anbinden (neomage hat Support)
  - Agent-Debugging im Debug-Screen
```

### Fallback: Nur dart_agent_core + eigene Tools

Falls neomage sich als zu groß/instabil erweist:

```dart
// dart_agent_core mit eigenen Tools
final agent = Agent(
  model: OpenAIModel(apiKey: apiKey, baseUrl: middlewareUrl),
  tools: [
    Tool('file_read', 'Reads a file', {'path': 'string'},
        (args) => File(args['path']).readAsString()),
    Tool('file_write', 'Writes a file', {'path': 'string', 'content': 'string'},
        (args) => File(args['path']).writeAsString(args['content'])),
    Tool('web_search', 'Searches the web', {'query': 'string'},
        (args) => _duckDuckGoSearch(args['query'])),
  ],
  contextCompressor: LLMBasedContextCompressor(...),
);

final stream = agent.runStream('Analysiere das PDF und erstelle eine Zusammenfassung');
await for (final event in stream) {
  // Update UI with progress
}
```

---

## Quellen

### Dart/Flutter Frameworks
- [neomage — pub.dev](https://pub.dev/packages/neomage)
- [dart_agent_core — pub.dev](https://pub.dev/packages/dart_agent_core)
- [Genkit Dart — pub.dev](https://pub.dev/packages/genkit) | [Docs](https://genkit.dev/docs/dart/tool-calling/)
- [Genkit Dart Announcement — Dart Blog](https://blog.dart.dev/announcing-genkit-dart-build-full-stack-ai-apps-with-dart-and-flutter-2a5c90a27aab)
- [Agenix — pub.dev](https://pub.dev/packages/agenix)
- [dartantic_ai — pub.dev](https://pub.dev/packages/dartantic_ai) | [Docs](https://docs.dartantic.ai/)
- [LangChain.dart — GitHub](https://github.com/davidmigloz/langchain_dart) | [Docs](https://langchaindart.dev/)
- [Murmuration — GitHub](https://github.com/AgnivaMaiti/murmuration)
- [LangGraph Dart Client — pub.dev](https://pub.dev/packages/langgraph_client)

### Python Frameworks (Referenz)
- [smolagents — GitHub](https://github.com/huggingface/smolagents) | [Docs](https://smolagents.org/)
- [OpenAI Agents SDK — GitHub](https://github.com/openai/openai-agents-python)
- [gptme — GitHub](https://github.com/gptme/gptme) | [Docs](https://gptme.org/)

### Flutter + Android
- [Chaquopy Flutter Plugin — pub.dev](https://pub.dev/packages/chaquopy)
- [Flutter + LangChain: Mobile AI Applications](https://dasroot.net/posts/2026/04/flutter-langchain-mobile-ai-applications/)
- [Flutter AI Agents Guide 2026](https://flutterexperts.com/flutter-ai-agents-building-autonomous-workflows-in-mobile-apps-with-code-samples/)
- [Firebase AI Logic — Function Calling](https://firebase.google.com/docs/ai-logic/function-calling)

### Vergleiche & Übersichten
- [Firecrawl — Best Open Source Agent Frameworks 2026](https://www.firecrawl.dev/blog/best-open-source-agent-frameworks)
- [Alice Labs — Best AI Agent Frameworks 2026](https://alicelabs.ai/en/insights/best-ai-agent-frameworks-2026)
- [Tencent Cloud — Best Open Source AI Agents 2026](https://www.tencentcloud.com/techpedia/144032)
- [Genkit Dart vs Firebase AI Logic 2026](https://dev.to/techwithsam/genkit-dart-vs-firebase-ai-logic-in-2026-which-should-flutter-developers-use-1pf0)
