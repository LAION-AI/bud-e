# School Bud-E 🎓🤖

![School Bud-E Banner](banner.png)

Welcome to School Bud-E, your AI-powered educational assistant!

[![Join us on Discord](https://img.shields.io/discord/823813159592001537?color=5865F2&logo=discord&logoColor=white)](https://discord.gg/xBPBXfcFHd)

## Overview

School Bud-E is an intelligent and empathetic learning assistant designed to revolutionize the educational experience. Developed by [LAION](https://laion.ai) in collaboration with the ELLIS Institute Tübingen, Collabora, the Tübingen AI Center and the German Research Center for Artificial Intelligence (DFKI), and Intel, School Bud-E focuses on empathy, natural interaction, and personalized learning. A working demo of the application is available at [school.bud-e.ai](https://school.bud-e.ai).

## Features

- **Real-time chat** with streaming responses
- **Voice input** via Speech-to-Text (Whisper / Groq API)
- **Text-to-Speech** playback for assistant responses
- **Multi-language support** — English and German (internationalization)
- **PDF upload and parsing** — send PDFs to the assistant for context
- **Image upload** — share images with vision-capable models
- **Experimental image generation** — generate and edit images via AI models (see below)
- **Persistent chat history** — conversations saved to localStorage with images offloaded to IndexedDB
- **Multi-chat management** — create, switch, rename, export, and import chat sessions
- **Character consistency** — image generation supports character reference across turns
- **Privacy-focused design** — local-first, no mandatory cloud dependency

## Experimental Image Generation

> **This branch includes experimental features for AI image generation and editing.**

The frontend supports generating and editing images directly in the chat interface. Both users and the AI assistant can trigger image generation using simple commands.

### Supported Models

| Alias | Model | Description |
|---|---|---|
| `nano-banana` | `gemini-2.5-flash-image` | Fast Gemini image generation |
| `nano-banana-pro` | `gemini-3-pro-image-preview` | Highest quality Gemini image generation |
| `flux-2-klein` | `flux-2-klein-9b` | Fast FLUX.2 generation |
| `flux-2-pro` | `flux-2-pro` | Balanced production quality |
| `flux-2-max` | `flux-2-max` | Maximum quality |
| `dall-e-3` | `dall-e-3` | OpenAI DALL-E 3 |

### Quick Usage Examples

**Generate an image:**
```
{"imagegen": "A serene mountain landscape at sunset"}
```

**Generate with a specific model:**
```
{"imagegen": {"prompt": "A futuristic cityscape", "model": "nano-banana-pro", "aspectRatio": "16:9"}}
```

**Edit the last image:**
```
{"imageedit": "Make the sky purple and add stars"}
```

**Hashtag format (user input):**
```
#imagegen:nano-banana-pro:A detailed portrait of a cat wearing a hat
```

For the full image generation guide including all parameters, models, and troubleshooting, see [image-generation-instructions.txt](image-generation-instructions.txt).

### Image Persistence

Images generated or uploaded in the chat are stored in IndexedDB (namespaced per chat session), preventing `QuotaExceededError` in localStorage. Conversations with images can be exported to JSON and re-imported with full image data intact.

## Technology Stack

- **Frontend**: [Fresh](https://fresh.deno.dev/) framework (Preact-based, Deno runtime)
- **Styling**: Tailwind CSS
- **Language Support**: English and German (internationalization)
- **AI Models**:
  - Speech-to-Text: Whisper Large V3 (via Groq API)
  - LLM: GPT-4o or any OpenAI-compatible endpoint
  - Image generation: Gemini Flash/Pro Image, FLUX.2 Klein/Pro/Max, Imagen 3/4, DALL-E 3
- **Storage**: localStorage + IndexedDB for chat and image persistence

## Project Structure

```
school-bud-e-frontend/
├── routes/
│   ├── api/
│   │   ├── chat.ts          # LLM streaming endpoint
│   │   ├── tts.ts           # Text-to-Speech endpoint
│   │   ├── imagegen.ts      # Image generation endpoint
│   │   ├── getClientId.ts   # Client session ID
│   │   └── debug.ts         # Debug/health endpoint
│   ├── index.tsx            # Main page
│   ├── about.tsx            # About page
│   └── _app.tsx             # App wrapper
├── islands/
│   ├── ChatIsland.tsx       # Main chat island (entry point)
│   ├── ChatIsland/
│   │   ├── hooks/           # State and persistence hooks
│   │   ├── services/        # API calls, streaming, image store
│   │   └── utils/           # Trigger parsing, helpers
│   ├── Header.tsx
│   └── Menu.tsx
├── components/
│   ├── ChatTemplate.tsx     # Chat UI rendering
│   ├── Settings.tsx         # Settings panel
│   ├── ImageUploadButton.tsx
│   ├── PdfUploadButton.tsx
│   ├── AudioUploadButton.tsx
│   └── ...
├── internalization/         # i18n content (EN/DE)
├── static/                  # Static assets
├── docker-compose/          # Docker deployment config
└── image-generation-instructions.txt  # Full image gen guide
```

## Getting Started: Development

1. Clone the repository:
   ```bash
   git clone https://github.com/LAION-AI/school-bud-e-frontend.git
   cd school-bud-e-frontend
   git checkout experimental
   ```

2. Set up environment variables:
   ```bash
   cp .example.env .env
   # Edit .env and fill in your API keys and endpoints
   ```

3. Run the development server:
   ```bash
   deno task start
   ```

4. Open `http://localhost:8000` in your browser.

## Getting Started: Production

**Without Docker:**
```bash
deno task build
deno task preview
```

**With Docker:**
```bash
git clone https://github.com/LAION-AI/school-bud-e-frontend.git
cd school-bud-e-frontend
cd docker-compose
nano .env   # Adjust environment variables
docker-compose up
```

Then open `http://localhost:8000`.

## Environment Variables

Key variables (set in `.env`):

| Variable | Description |
|---|---|
| `MIDDLEWARE_URL` | Base URL for the Admin Bud-E middleware |
| `OPENAI_API_KEY` | OpenAI-compatible API key for LLM |
| `GROQ_API_KEY` | Groq API key for Whisper STT |
| `TTS_API_URL` | Text-to-Speech endpoint |

See `.example.env` for the full list.

## Middleware (Admin Bud-E)

The frontend communicates with a separate middleware service (Admin Bud-E) that handles:
- LLM routing to multiple providers
- Image generation (Gemini, FLUX.2, Imagen, DALL-E)
- TTS and STT proxying
- Provider configuration and pricing

The middleware is a separate repository and is not included here.

## API Routes

- **`/api/chat`** — Streaming LLM chat endpoint
- **`/api/tts`** — Text-to-Speech conversion
- **`/api/imagegen`** — Image generation (supports Gemini, FLUX.2, Imagen, DALL-E)
- **`/api/getClientId`** — Unique session ID generation
- **`/api/debug`** — Health/debug information

## Contributing

We welcome contributions! Please join our [Discord server](https://discord.com/invite/eq3cAMZtCC) or contact us at <contact@laion.ai>.

## Disclaimer

This is an experimental prototype application. It may produce inaccurate answers or generate content not suitable for all audiences. Use with caution and report issues via the [issue tracker](https://github.com/LAION-AI/school-bud-e-frontend/issues).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgements

Special thanks to LAION, ELLIS Institute Tübingen, Collabora, the Tübingen AI Center and the German Research Center for Artificial Intelligence (DFKI), and Intel for their contributions and support.

---

Built with for the future of education.
