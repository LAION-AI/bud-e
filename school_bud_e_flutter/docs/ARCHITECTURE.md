# BUD-E Architecture & Lifecycle Documentation

## Overview

BUD-E is a cross-platform AI assistant with persistent memory, voice I/O, and a multi-tier context construction system. This document describes the complete lifecycle of a conversation exchange, how memory is managed, and how context is constructed.

---

## 1. Message Lifecycle

### 1.1 User Input → Response Flow

```
User Input (text or ASR)
    │
    ├─ ASR: Record → Whisper API → Transcription → Text field (or auto-send)
    │
    ▼
sendMessage(text)
    │
    ├─ 1. Add user message to conversation + memory
    ├─ 2. Build context (with timeout: 10s)
    │     ├─ Load episodic memory (up to episodicTokenBudget)
    │     ├─ Load semantic entries (cached in RAM)
    │     ├─ Scan for trigger words
    │     ├─ Follow related-concept pointers (max 3 hops, 20 entries)
    │     ├─ Sort by recency (lastUpdated desc)
    │     └─ Fill remaining budget (full content or summary)
    │
    ├─ 3. Record ContextSnapshot for debug
    │
    ├─ 4. Build system prompt
    │     ├─ Base personality (personality.json)
    │     ├─ Language instruction
    │     ├─ Agent descriptions
    │     ├─ Tool descriptions (memory_search, wikipedia, memory_save)
    │     ├─ Episodic context ("=== Erinnerungen ===")
    │     └─ Semantic context ("=== Aktiviertes Wissen ===")
    │
    ├─ 5. Stream LLM response (SSE, with retry: max 2 retries)
    │     ├─ Feed chunks to TTS pipeline (if TTS enabled)
    │     │   ├─ Detect first sentence (min 3 words) → synthesize immediately
    │     │   └─ Accumulate rest → send as ONE batch at endStream()
    │     └─ Display chunks in UI as they arrive
    │
    ├─ 6. Check for tool calls in response
    │     ├─ [[tool:memory_search query="..."]] → BM25 search → follow-up LLM call
    │     ├─ [[tool:wikipedia query="..." depth="..."]] → Wikipedia API → follow-up
    │     └─ [[tool:memory_save id="..." content="..."]] → direct write (no follow-up)
    │
    ├─ 7. _finishExchange (fire-and-forget)
    │     ├─ Save conversation + working memory (parallel)
    │     └─ Background memory updater
    │           ├─ LLM extraction call (non-streaming)
    │           ├─ Save concepts, prefs, episodic, procedural (parallel)
    │           ├─ Record MemoryUpdateRecord for debug
    │           └─ Invalidate context cache + mark BM25 dirty
    │
    └─ Done
```

### 1.2 Retry Logic

If the LLM returns an error or empty response:
1. Wait 1 second, retry (attempt 1)
2. Wait 2 seconds, retry (attempt 2)
3. If all 3 attempts fail: show user-friendly error message in the configured language

### 1.3 Tool Call Flow

When the LLM outputs `[[tool:...]]`:
1. First response (with tool call) is saved as assistant message
2. Tool is executed (search/wikipedia/save)
3. Tool results injected as user message (wrapped in `[[tool_result]]...[[/tool_result]]`)
4. Second LLM call with results in context → follow-up response
5. Follow-up is the "real" answer used for TTS

---

## 2. Memory Architecture

### 2.1 Three-Tier Memory System

```
%APPDATA%/SchoolBudE/
├── semantic_memory/          ← WHAT (facts, knowledge, entities)
│   ├── <concept_id>.json     ← Individual concept files
│   ├── user_preferences.json ← User profile
│   ├── knowledge_base.json   ← General facts
│   └── procedural.json       ← HOW (interaction patterns)
├── episodic_memory/          ← WHEN (what happened, summaries)
│   └── session_<ts>.json     ← Per-exchange summaries
├── working_memory/           ← NOW (current session state)
│   └── active_context.json
├── conversations/            ← Full message history
│   └── <id>.json
├── settings.json             ← API key, TTS, token budgets
└── personality.json          ← System prompt, persona name, traits
```

### 2.2 Semantic Memory (JSON Schema)

Each concept file:
```json
{
  "id": "king_arthur",
  "title": "King Arthur",
  "content": "Current, up-to-date knowledge about this concept...",
  "summary": "100-200 word summary for context budget overflow",
  "triggerWords": ["king arthur", "camelot", "excalibur", "round table"],
  "relatedConcepts": ["camelot", "merlin", "excalibur"],
  "category": "history",
  "lastUpdated": "2026-04-20T14:00:00",
  "revisions": [
    {"content": "old version...", "replacedAt": "2026-04-20T14:00:00"}
  ]
}
```

Key fields:
- **triggerWords**: Activate this memory when found in episodic context (case-insensitive, special-char-tolerant matching)
- **relatedConcepts**: Pointers to other concept IDs (knowledge graph edges)
- **summary**: Loaded when full content exceeds remaining token budget
- **revisions**: History of changes (max 5), stored on disk but NOT sent to LLM

### 2.3 Episodic Memory

Auto-generated after each exchange by the Memory Updater:
```json
{
  "type": "auto_summary",
  "conversationId": "abc123",
  "summary": "User asked about photosynthesis...",
  "topics": ["photosynthesis", "biology"],
  "messageCount": 4,
  "savedAt": "2026-04-20T14:00:00"
}
```

### 2.4 Memory Update Rules

The **Memory Updater** runs after every exchange (fire-and-forget):

1. Takes the last 10 messages of the conversation
2. Sends them to the LLM with an extraction prompt
3. The extraction prompt includes the list of **existing concept IDs** so the LLM can reuse them for updates (not create duplicates)
4. Extracted concepts are **merged** with existing files:
   - `content` is REPLACED (not appended) — always contains the latest info
   - `triggerWords` are UNION merged (old + new)
   - `relatedConcepts` are UNION merged
   - Old `content` is saved to `revisions` array (max 5)
5. All saves run in **parallel** via `Future.wait`
6. After completion: context cache invalidated, BM25 index marked dirty

### 2.5 Daily Memory Consolidation

Runs automatically once per day (checked at app startup via `lastConsolidation` setting):

1. Loads ALL semantic concept IDs and their metadata (title, triggerWords, relatedConcepts)
2. Sends concept summaries to LLM for review
3. LLM suggests:
   - **Cross-references**: Missing bidirectional `relatedConcepts` links
   - **Missing triggers**: Additional `triggerWords` for better retrieval
   - **Duplicates**: Concepts covering the same topic under different IDs
4. Cross-references are applied bidirectionally (A->B AND B->A)
5. Missing triggers are union-merged into existing triggerWords
6. Results logged as `MemoryUpdateRecord` with `conversationId: 'consolidation'`

### 2.6 Sub-Agent System

Background agents for complex multi-step tasks (PDF analysis, research, file creation):

```
BUD-E detects complex task or large PDF
    |
    +-- Creates AgentTask (status: running, spinning gear icon)
    +-- Spawns SubAgentRunner in background
    |     |
    |     +-- System prompt with available tools
    |     +-- Text-based tool calling ([[tool:...]] syntax)
    |     +-- Max 15 iterations
    |     +-- Each step logged in AgentTask.steps
    |     |
    |     +-- PDF strategy:
    |     |     1. pdf_info -> size, pages, text quality
    |     |     2. pdf_extract_text -> 5-page chunks (if text extractable)
    |     |     3. analyze_pdf_pages -> send to AI for OCR (if scanned)
    |     |
    |     +-- Completion: task.complete(result)
    |     +-- Error: task.fail(error)
    |
    +-- On completion: result injected into conversation
    +-- BUD-E presents result to user via follow-up LLM call
    +-- On error: BUD-E explains error and suggests fixes
```

Available sub-agent tools: `read_file`, `write_file`, `list_files`, `pdf_info`, `pdf_extract_text`, `analyze_pdf_pages`, `analyze_document`, `wikipedia`, `weather`, `news`, `web_fetch`

---

## 3. Context Construction

### 3.1 When is context built?

On **every `sendMessage()` call**, before the LLM request.

### 3.2 Construction Pipeline

```
Step 1: Load Episodic Memory
    ├── List episodic_memory/ directory
    ├── Sort by filename descending (most recent first)
    ├── Cap at 100 files
    ├── Parallel read via Future.wait
    ├── Accumulate entries until episodicTokenBudget reached
    ├── Reverse for temporal order (oldest first in context)
    └── Cache result (invalidated when new files written)

Step 2: Load Semantic Entries
    ├── List semantic_memory/ directory
    ├── Parallel read all files via Future.wait
    ├── Parse triggerWords, relatedConcepts, summary from each
    └── Cache in RAM (invalidated after memory updates)

Step 3: Trigger-Word Activation
    ├── Combine episodic text + current conversation text
    ├── Normalize: lowercase, strip special chars
    └── For each semantic entry: if any triggerWord matches → activate

Step 4: Follow Related Pointers
    ├── For each activated entry, check its relatedConcepts
    ├── Activate any matching entries not yet activated
    ├── Max 3 hops deep, max 20 total entries
    └── This implements knowledge graph traversal

Step 5: Sort & Fill Budget
    ├── Sort activated entries by lastUpdated DESC (newest first)
    ├── For each entry (in recency order):
    │   ├── If full JSON fits in remaining budget → include full
    │   ├── Else if summary fits → include summary
    │   └── Else skip
    ├── Header shows timestamp: "--- concept (aktualisiert: ...) ---"
    └── Revisions are STRIPPED from context (prevent LLM confusion)
```

### 3.3 Token Budget Defaults

| Setting | Default | Configurable |
|---|---|---|
| Episodic token budget | 50,000 | Settings slider (5k-200k) |
| Total context budget | 100,000 | Settings slider (10k-500k) |
| Token estimation | ~4 chars per token | Hardcoded |

### 3.4 Caching Strategy

- **Semantic entries**: Cached in RAM after first load. Invalidated when Memory Updater writes new files.
- **Episodic entries**: Cached by file count. Invalidated when new episodes are saved.
- **BM25 index**: Dirty-flag pattern. Rebuilt only when `search()` is called after a memory write.

---

## 4. Search & Retrieval

### 4.1 BM25 Search

- **Index**: Inverted index over all files in `semantic_memory/`, `episodic_memory/`, `working_memory/`
- **Tokenization**: Lowercase, strip punctuation, split on whitespace, min 2 chars per token
- **Parameters**: k1=1.5, b=0.75 (standard BM25)
- **Document lengths**: Cached during index build (not re-tokenized during search)
- **Rebuild**: Only when dirty flag is set and `search()` is called
- **Triggered by**: `[[tool:memory_search query="..."]]` in LLM output

### 4.2 Trigger-Word Matching

- **Normalization**: `_normalize(s)` → lowercase, strip `[^a-z0-9\s]`, collapse spaces
- **Matching**: Simple `string.contains(normalizedTrigger)` — no fuzzy matching
- **Sources**: `triggerWords` array from each semantic JSON + filename as fallback trigger

### 4.3 Knowledge Graph Traversal

- Each concept can point to other concepts via `relatedConcepts` (list of concept IDs)
- Context builder follows these pointers up to 3 hops deep
- Max 20 total activated entries (prevents explosion)
- Example: User mentions "Camelot" → activates `camelot.json` → follows pointer to `king_arthur.json`

---

## 5. TTS Pipeline

### 5.1 Streaming TTS Strategy

Based on benchmarking: each TTS API call has ~2.3s fixed overhead regardless of text length. Optimal strategy: minimize number of API calls.

```
LLM Stream starts
    │
    ├── Accumulate text in buffer
    ├── Detect first sentence boundary (min 3 words)
    ├── Send first sentence immediately (TTS Call #1)
    ├── Continue accumulating ALL remaining text
    │
LLM Stream ends
    │
    ├── Send remaining text as ONE TTS call (TTS Call #2)
    └── Play: Call #1 audio → Call #2 audio (seamless)
```

Result: Only 2 TTS API calls per response, regardless of length.

### 5.2 TTS Controls

- **Global toggle**: App bar button (on/off)
- **Per-message replay**: Speaker icon under each assistant message (works even when global TTS is off)
- **Stop**: Click speaker during playback to stop, or click the app bar button (shows red stop icon)
- **Cache**: Last 50 sentence hashes cached as MP3 files

---

## 6. Debugging & Introspection

### 6.1 Debug Tabs

| Tab | Content |
|---|---|
| **Live Log** | Real-time event feed from all components, filterable by source |
| **Context** | Current system prompt + context window messages |
| **Memory** | All messages in memory store, which are in context window |
| **Agents** | Registered sub-agents and their prompt injection |
| **Config** | API key, endpoints, conversation metadata, runtime state |
| **Ctx History** | Per-exchange context snapshots: what episodic/semantic context was built, which memories were activated, full system prompt — color-coded sections |
| **Mem Updates** | History of Memory Updater operations: what concepts were created/updated, which files changed, episodic summaries, timing, errors |
| **Files** | File browser for the SchoolBudE data directory |

---

## 7. Improvement Proposals

### 7.1 Memory Retrieval Improvements

1. **Embedding-based similarity search**: Replace or augment BM25 with vector embeddings. Use a local embedding model (e.g., all-MiniLM-L6) to encode concept summaries and query text. This would enable semantic search ("Wie heißt der König?" → finds "king_arthur") rather than exact keyword matching.

2. **Hybrid retrieval**: Combine BM25 (lexical) + embedding similarity (semantic) with reciprocal rank fusion. This gives the best of both worlds.

3. **Importance scoring**: Weight memories by access frequency, recency, and explicit user marking. Frequently accessed memories get higher priority in context filling.

4. **Memory consolidation**: Periodically run an LLM pass to merge overlapping concepts, remove duplicates, and create higher-level summaries. Similar to sleep-based memory consolidation in humans.

5. **Forgetting curve**: Implement Ebbinghaus-inspired decay. Memories not accessed for a long time get lower activation priority. Trigger words would need increasingly strong matches to activate old memories.

### 7.2 Context Construction Improvements

1. **Dynamic token budgeting**: Instead of fixed episodic/semantic split, dynamically allocate based on query type. Factual questions → more semantic. "What did we discuss?" → more episodic.

2. **Multi-hop reasoning**: Currently trigger words only scan the episodic context. Add a second pass that scans the ACTIVATED semantic entries for additional trigger words (two-hop activation).

3. **Relevance filtering**: After trigger-word activation, run a lightweight relevance check (e.g., cosine similarity between query and concept summary) to prune false-positive activations.

4. **Conversation-aware context**: Include a compressed summary of the current conversation alongside episodic history, so the LLM has both the recent exchange AND long-term memory.

### 7.3 Performance Improvements

1. **Streaming TTS via WebSocket**: If the middleware supports it, use a persistent WebSocket connection for TTS instead of individual HTTP POST calls. This eliminates the ~2.3s connection overhead.

2. **Speculative LLM call**: Start the HTTP connection to the LLM endpoint DURING context building (just the TCP/TLS handshake), then send the body once context is ready.

3. **Incremental BM25**: Instead of full rebuild on every dirty flag, maintain the index and only add/update individual documents.

4. **Background prefetch**: When the user is typing (keystrokes detected), start building context speculatively so it's ready when they press send.

5. **Edge TTS**: For offline/low-latency scenarios, use a local TTS model (e.g., Piper) instead of the middleware API.

### 7.4 Memory System Extensions

1. **Procedural memory as skills**: Store executable procedures (step-by-step instructions for tasks) that the agent can follow. E.g., "How to search Wikipedia" → stored procedure with API format.

2. **Emotional memory**: Track the emotional valence of interactions. If a topic caused frustration, approach it differently next time.

3. **Meta-memory**: Memory about memory — track which retrieval strategies work well, which trigger words are most useful, and adapt over time.

4. **Shared memory**: Allow multiple users to share a semantic memory base (e.g., classroom knowledge) while maintaining private episodic and preference memories.

5. **Memory versioning**: Git-like version control for the memory folder, allowing rollback to previous knowledge states.
