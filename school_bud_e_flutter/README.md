# BUD-E — Your AI Learning Companion

**BUD-E is a friendly AI assistant that runs on your phone, tablet, or computer.** It can answer questions, search the web, create documents and presentations, generate images and music, and even search through education curricula — all through a simple chat interface with voice support.

Think of it as a personal assistant for students and teachers: you talk or type, and BUD-E helps you learn, create, and explore. It connects to AI services through a middleware server ([Admin Bud-E](https://github.com/LAION-AI/Admin_Bud-E)) that your school or organization controls — so your data stays private and costs stay manageable.

[![Download APK](https://img.shields.io/badge/Download-APK%20(Android)-green?style=for-the-badge&logo=android)](https://github.com/LAION-AI/bud-e/releases/download/v0.1.0-beta/BUD-E-v0.1.0-beta.apk)

> **[Download the latest APK](https://github.com/LAION-AI/bud-e/releases/download/v0.1.0-beta/BUD-E-v0.1.0-beta.apk)** | [All Releases](https://github.com/LAION-AI/bud-e/releases)

---

## All Features

### Chat & Communication
- **Chat with LLM** — Streaming responses via middleware (Gemini 2.5 Flash/Pro)
- **Voice Input (ASR)** — Microphone button, Whisper transcription
- **Text-to-Speech (TTS)** — Read responses aloud, per-message TTS toggle
- **Auto Language Detection** — Responds in the user's language
- **Multilingual UI** — German, English, French, Spanish (welcome screen, status messages, agent feedback)
- **Conversation Branching** — Regenerate button, branch navigation (← 1/3 →)
- **Clickable Links** — URLs in responses open in browser (url_launcher)
- **Code Blocks** — Syntax label, dark theme, copy button, inline edit mode

### Document Creation (Sub-Agent)
- **Word (.docx)** — Calibri font, blue headings, embedded images, automatic HTML-to-Markdown conversion
- **PDF (.pdf)** — Helvetica font, WinAnsi encoding (correct umlauts ä/ö/ü/ß, em-dash, smart quotes, €)
- **PowerPoint (.pptx)** — 4 layouts (Title / Image+Bullets / Image-only / Text-only), adaptive image sizing based on aspect ratio, Calibri font, slide numbers, image-first enforcement
- **HTML (.html)** — Inline CSS, base64-embedded images
- **Markdown (.md)**, **RTF (.rtf)**
- **File Chips** — Generated documents shown as clickable icons with file type symbols

### Image Generation
- **Models**: Gemini 3 Pro Image, Imagen 4.0, FLUX.2 (Pro/Max/Klein), nano-banana
- **Aspect Ratios**: square (1:1), landscape (16:9), portrait (9:16), photo (4:3), wide (21:9)
- **Image Editing**: Reference images for style transfer
- **Image Registry**: Every image gets a unique IMG_xxx ID

### Music Generation (Lyria 3 Pro)
- **Full Songs with Vocals** — Up to 184s / ~3 minutes, MP3 output
- **Lyrics Support** — `[Verse]`, `[Chorus]`, `[Bridge]`, `[Outro]` tags
- **Two-Step Workflow**: Draft prompt + lyrics → user confirms → generate
- **Content Policy Error Handling** — Clear message + rephrasing tips

### Web Research (Sub-Agent)
- **Brave Search** — Web search with top-5 parallel scraping
- **Web Scrape** — Extract page content (5s timeout, parallel-friendly)
- **Wikipedia** — Article lookup (de/en)
- **Weather** — Current conditions via wttr.in
- **News** — Latest from tagesschau.de

### Curriculum Search (Bildungsplan, BM25)
- **1,548 pages** from **32 Hamburg education plans** indexed
- **4 school types**: Grundschule, Stadtteilschule, Gymnasium Sek I, Studienstufe
- **17 subjects**: Deutsch, Englisch, Mathematik, Biologie, Chemie, Physik, Informatik, Geschichte, Geographie, Sport, Religion, Wirtschaft, Psychologie, and more
- **Bundled Assets** — Index auto-extracted on first launch (works offline)
- **Clickable PDF Links** with page numbers (`URL#page=27`)
- **Snippet Extraction** with query term highlighting
- **Safety Net** — Auto-triggers search even if LLM skips the tool call

### Memory System
- **Episodic Memory** — Conversation summaries, auto-saved per session
- **Semantic Memory** — Long-term knowledge with trigger words and related concepts
- **Working Memory** — Active session context
- **BM25 Memory Search** — Keyword search across all memory files
- **Priority-Based Context Construction** — ~20K token budget, 1st/2nd order activation, German stopwords

### Agent System
- **Sub-Agent** with tool calling (web_search, web_scrape, generate_image, write_file, run_python, etc.)
- **Agent Task Widget** — Gear animation, progress bar, expandable step history (tap to show all)
- **Health Checks** — Verification at 2s/5s/10s, auto-restart on failure
- **Fallback Regex** — Detects tool calls even with escaped quotes in LLM output
- **Floating Agent Widgets** — Running agents always visible even without message link
- **Image Generation Limit** — Max 10 per agent run to prevent infinite retries
- **Quality Control** — Automatic file verification and content check
- **Python Execution** — Server-side (via middleware) or local fallback

### Persona & Settings
- **Persona Export/Import** — ZIP file with personality, memories, conversations, workspace files
- **Skill Explorer** — Visual skill browser with categories, enable/disable toggles
- **System Prompt Editor** — Customize personality and behavior
- **Language Selection** — Deutsch, English, Francais, Espanol
- **Token Budget Sliders** — Episodic and total context budgets
- **TTS/ASR Toggles**
- **API Key** with encoded middleware URL (works on any device)

### Platforms
- **Android** — APK (tested on emulator + real devices)
- **Windows** — Desktop (native)
- **iOS** — Build-ready (requires Mac with Xcode)
- **macOS** — Build-ready

---

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

## Contributing

Developed by [LAION](https://laion.ai) and collaborators. Contributions welcome!

## License

Apache 2.0
