# BUD-E — Your AI Learning Companion

**BUD-E is a friendly AI assistant that runs on your phone, tablet, or computer.** It can answer questions, search the web, create documents and presentations, generate images and music, and even search through education curricula — all through a simple chat interface with voice support.

Think of it as a personal assistant for students and teachers: you talk or type, and BUD-E helps you learn, create, and explore. It connects to AI services through a middleware server ([Admin Bud-E](https://github.com/LAION-AI/Admin_Bud-E)) that your school or organization controls — so your data stays private and costs stay manageable.

---

## What BUD-E Can Do

| Feature | Description |
|---------|-------------|
| **Chat** | Natural conversation with memory across sessions |
| **Voice** | Speech-to-text input + text-to-speech output |
| **Web Search** | Brave Search + Wikipedia + website scraping |
| **Documents** | Create Word (.docx), PDF, HTML files with images |
| **Presentations** | PowerPoint (.pptx) with AI-generated images per slide |
| **Images** | Generate and edit images (Gemini, Imagen, FLUX.2) |
| **Music** | Full songs with vocals and lyrics (Lyria 3 Pro, up to 3 min) |
| **Curriculum Search** | Search through education plans with BM25 ranking |
| **Memory** | Remembers facts, preferences, and conversation history |
| **Multi-language** | Responds in the language you speak |
| **Conversation Branching** | Regenerate responses, navigate between alternative branches |

## Architecture

```
┌─────────────────────────────────────────────────┐
│  BUD-E Flutter App (Android / iOS / Windows)    │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ Chat UI  │  │ Voice IO │  │ File Viewer  │  │
│  └────┬─────┘  └────┬─────┘  └──────────────┘  │
│       │              │                          │
│  ┌────▼──────────────▼─────────────────────┐    │
│  │         Chat Provider (State)           │    │
│  │  ┌─────────┐ ┌────────┐ ┌───────────┐  │    │
│  │  │ Memory  │ │Context │ │  Skills   │  │    │
│  │  │ Store   │ │Builder │ │ (Tools)   │  │    │
│  │  └─────────┘ └────────┘ └───────────┘  │    │
│  └─────────────────┬───────────────────────┘    │
│                    │                            │
└────────────────────┼────────────────────────────┘
                     │ HTTPS / API Key
                     ▼
         ┌───────────────────────┐
         │  Admin Bud-E Server   │
         │  (Middleware Proxy)   │
         └───────────┬───────────┘
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
     Google      Black Forest  Other
     Vertex AI   Labs (FLUX)   Providers
```

**Detailed documentation:**
- **[Context & Memory System](docs/CONTEXT_AND_MEMORY.md)** — How BUD-E remembers and constructs context
- **[Skills & Tools](docs/SKILLS_AND_TOOLS.md)** — All available tools and how they work
- **[Document Generation](docs/DOCUMENT_GENERATION.md)** — DOCX, PDF, HTML, PPTX creation
- **[Curriculum Search](docs/CURRICULUM_SEARCH.md)** — BM25 search over education plans

---

## Quick Start

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.x+)
- An [Admin Bud-E](https://github.com/LAION-AI/Admin_Bud-E) server running
- An API key from your Admin Bud-E server

### Install & Run

```bash
git clone https://github.com/LAION-AI/bud-e.git
cd bud-e
flutter pub get
flutter run
```

### Configure

1. Open BUD-E and go to **Settings** (gear icon)
2. Enter your **API Key** in the format: `<key>#<encoded-server-address>`
3. Start chatting!

### Build

```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# Windows
flutter build windows --release
```

---

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── config/api_config.dart       # API key decoding, middleware URL
├── models/
│   ├── message.dart             # Message with tree branching (parentId)
│   ├── conversation.dart        # Conversation with branch navigation
│   └── agent_task.dart          # Sub-agent task tracking
├── providers/
│   └── chat_provider.dart       # Central state: chat, tools, agents, memory
├── screens/                     # UI screens (chat, settings, debug, memory)
├── services/
│   ├── context_builder.dart     # Priority-based context construction
│   ├── memory_search.dart       # BM25 search over memory files
│   ├── bildungsplan_search.dart # BM25 search over education curricula
│   ├── chat_service.dart        # LLM streaming
│   ├── tts_service.dart         # Text-to-speech
│   ├── asr_service.dart         # Speech-to-text recording
│   └── file_storage_service.dart# Persistent storage
├── memory/memory_store.dart     # Episodic + semantic memory management
├── agents/
│   ├── sub_agent_runner.dart    # Sub-agent with tool calling (DOCX, PPTX, etc.)
│   ├── memory_updater.dart      # Background memory consolidation
│   └── tools/                   # Web search, file ops, document generation
└── widgets/                     # Message bubbles, file chips, agent status
```

---

## Contributing

Developed by [LAION](https://laion.ai) and collaborators. Contributions welcome!

## License

Apache 2.0
