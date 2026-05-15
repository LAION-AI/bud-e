# Context & Memory System

BUD-E maintains a persistent memory across conversations and constructs a priority-based context for each LLM call.

## Memory Tiers

### 1. Episodic Memory
Short conversation summaries stored as JSON files in `episodic_memory/`. Each entry contains:
- Timestamp, summary, topics, first user message
- Automatically created after each conversation exchange

### 2. Semantic Memory
Long-term knowledge stored in `semantic_memory/`. Contains:
- Facts the user asked BUD-E to remember
- User preferences and interests
- Trigger words for activation
- Related concepts (for graph-based retrieval)

### 3. Working Memory
Current session state in `working_memory/`. Tracks active conversation context.

## Context Construction (Priority-Based)

The `ContextBuilder` constructs a ~20K token context budget:

| Priority | Content | Budget |
|----------|---------|--------|
| 1 | System prompt + tool descriptions | ~3K tokens |
| 2 | Keyword-triggered semantic memories (1st order) | ~5K tokens |
| 3 | Related semantic memories (2nd order, 1 hop) | ~3K tokens |
| 4 | Recent episodic memories (newest first, max 30) | ~4K tokens |

### How Activation Works

1. **Keywords extracted** from the current conversation
2. **1st order**: Semantic entries whose `triggerWords` match any keyword
3. **2nd order**: Entries linked via `relatedConcepts` (1 hop max)
4. **Budget enforcement**: Each entry max 800 tokens, summaries preferred over full text
5. **Stopword filtering**: German + English stopwords removed from matching

## BM25 Search

The `MemorySearch` service builds an in-memory inverted index over all memory files for keyword search with BM25 ranking (k1=1.2, b=0.75).

## API Key Format

The universal API key encodes both the bearer token and middleware server address:

```
<api_key>#<encoded_host:port>
```

The suffix after `#` is either:
- A raw URL: `http://192.168.1.100:8787`
- A `v1`-prefixed Base32-encoded, XOR-obfuscated `host:port` string

The app decodes this automatically to find the middleware server.
