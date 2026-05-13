# School Bud-E Flutter App

Cross-platform AI-powered educational assistant — a Flutter proof-of-concept for [School Bud-E](https://github.com/LAION-AI/school-bud-e-frontend).

## Features

- **Chat** with streaming LLM responses via the Admin Bud-E middleware
- **Voice input** — tap mic to record, tap again to transcribe (ASR) and send
- **Text-to-Speech** — auto-plays assistant responses (sanitized: no emojis/markdown read aloud)
- **Configurable API key** — universal key format with encoded middleware URL
- **Persistent memory** — all data saved as JSON files in `%APPDATA%/SchoolBudE/`
- **Conversation history** — browse and reload past conversations
- **Memory Explorer** — browse the JSON folder tree in-app
- **Debug log** — real-time view of all component activity

## Memory Architecture

The app implements a three-tier memory system inspired by cognitive science:

### Episodic Memory (`episodic_memory/`)
Session-by-session conversation summaries. Loaded in **temporal order** up to a configurable token budget (default: 50,000 tokens). Provides the "what happened recently" context.

### Semantic Memory (`semantic_memory/`)
Individual concept files (knowledge base, facts, entities). Each JSON file includes:
- **`triggerWords`** — keywords that activate this memory when found in the episodic context (case-insensitive, special-char-tolerant matching)
- **`summary`** — 100-200 word summary (loaded when full content is too large for the budget)
- **`relatedConcepts`** — pointers to other semantic files (knowledge graph edges, e.g., "camelot" → "king_arthur")
- **`content`** — full detailed knowledge

### Procedural Memory (`semantic_memory/procedural.json`)
Communication patterns and interaction style notes. Also activated via trigger words.

### Context Construction

On each message, the **ContextBuilder** constructs the LLM context:

1. Load episodic entries (most recent first) up to **episodic token budget** (default 50k)
2. Scan the episodic text + current conversation for **trigger words**
3. Activate matching semantic/procedural memory files
4. Follow **relatedConcepts pointers** to activate more files (knowledge graph traversal)
5. For each activated file: include **full content** if budget allows, otherwise **summary**
6. Fill until **total context budget** is reached (default 100k tokens)

### Background Memory Updater

After every conversation exchange, the **MemoryUpdater** agent runs in the background:
- Calls the LLM to extract structured information from the conversation
- Creates/updates individual concept files with `triggerWords`, `summary`, `relatedConcepts`
- Saves episodic summaries with topics
- Updates procedural notes with interaction patterns
- All writes are atomic (temp file + rename) to prevent corruption

### BM25 Search Tool

The main agent can invoke a memory search tool by outputting:
```json
{"tool": "memory_search", "query": "search keywords"}
```
This runs a **BM25 search** over an in-memory inverted index of all memory files, returning the top results with scores and summaries.

## Settings

Configurable in the Settings screen:

| Setting | Default | Description |
|---|---|---|
| Episodic token budget | 50,000 | Max tokens loaded from episodic memory |
| Total context budget | 100,000 | Max total context tokens (episodic + semantic) |
| System prompt | (default) | Saved to `personality.json` |
| Persona name | School Bud-E | Display name, saved to `personality.json` |
| TTS enabled | true | Auto-play assistant responses |
| API key | (test key) | Universal key with encoded middleware URL |

## Data Folder Structure

```
%APPDATA%/SchoolBudE/
  settings.json              ← API key, TTS, token budgets
  personality.json           ← system prompt, persona name, traits
  semantic_memory/
    knowledge_base.json      ← accumulated facts with triggerWords
    user_preferences.json    ← learning profile with triggerWords
    procedural.json          ← interaction patterns with triggerWords
    <concept_id>.json        ← individual concept files (auto-created)
  episodic_memory/
    session_<timestamp>.json ← conversation summaries
  working_memory/
    active_context.json      ← current session state
  conversations/
    <id>.json                ← full message history
```

## Platforms

- Windows (primary)
- Android, iOS, macOS (cross-platform compatible)

## Getting Started

```bash
cd school_bud_e_flutter
C:\dev\flutter\bin\flutter pub get
C:\dev\flutter\bin\flutter run -d windows

# Run tests
C:\dev\flutter\bin\dart test
```

## Architecture

```
lib/
├── main.dart                        # Entry point
├── config/api_config.dart           # Key decoding, URL resolution
├── services/
│   ├── chat_service.dart            # LLM streaming (SSE)
│   ├── tts_service.dart             # TTS with text sanitization
│   ├── asr_service.dart             # Mic recording + transcription
│   ├── file_storage_service.dart    # JSON file persistence
│   ├── context_builder.dart         # Trigger-word context construction
│   ├── memory_search.dart           # BM25 inverted index search
│   ├── debug_log.dart               # Global debug event log
│   └── storage_service.dart         # (legacy, migrated)
├── models/                          # Message, Conversation (with JSON serialization)
├── providers/chat_provider.dart     # Central state + tool calling
├── memory/memory_store.dart         # Memory tiers + persistence hooks
├── agents/
│   ├── agent.dart                   # Sub-agent interface
│   ├── agent_registry.dart          # Agent dispatch
│   └── memory_updater.dart          # Background LLM memory extraction
├── screens/
│   ├── chat_screen.dart             # Main chat UI
│   ├── settings_screen.dart         # Settings with token budget sliders
│   ├── debug_screen.dart            # Debug tabs (Log, Context, Memory, Agents, Config, Files)
│   └── memory_explorer_screen.dart  # JSON file browser
└── widgets/                         # MessageBubble, ChatInput
```
