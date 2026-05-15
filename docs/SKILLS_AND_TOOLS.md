# Skills & Tools

BUD-E has a set of built-in tools that the LLM can invoke via `[[tool:name ...]]` syntax in its responses.

## Direct Tools (executed immediately)

| Tool | Syntax | Description |
|------|--------|-------------|
| **Weather** | `[[tool:weather location="Berlin"]]` | Current weather + forecast via wttr.in |
| **News** | `[[tool:news topic="AI"]]` | Latest news from tagesschau.de |
| **Wikipedia** | `[[tool:wikipedia query="Photosynthesis" depth="full"]]` | Wikipedia article lookup |
| **Memory Save** | `[[tool:memory_save id="fav_food" content="Pizza"]]` | Save a fact to long-term memory |
| **Memory Search** | `[[tool:memory_search query="favorite food"]]` | Search memory with BM25 |
| **Image Generation** | `[[tool:generate_image prompt="..." aspect="square"]]` | Generate images via Vertex/FLUX |
| **Music Generation** | `[[tool:generate_music prompt="..." negative_prompt="..."]]` | Generate songs with Lyria 3 Pro |
| **Bildungsplan Search** | `[[tool:bildungsplan_search query="..." fach="Informatik"]]` | Search education curricula |

## Sub-Agent Tool (background task)

| Tool | Syntax | Description |
|------|--------|-------------|
| **Run Agent** | `[[tool:run_agent instruction="Create a Word doc about..."]]` | Spawns a sub-agent for complex tasks |

### Sub-Agent Capabilities
The sub-agent has its own tool set:
- `read_file`, `write_file`, `delete_file`, `list_files`
- `generate_image` (with aspect ratios)
- `web_search` (Brave Search), `web_scrape`, `web_fetch`
- `wikipedia`, `weather`, `news`
- `transcribe_audio`, `analyze_document`, `pdf_info`, `pdf_extract_text`

### Supported Output Formats
- `.docx` — Word documents (Calibri font, blue headings, embedded images)
- `.pptx` — PowerPoint (4 layouts: title, image+bullets, image-only, text-only)
- `.pdf` — PDF documents
- `.html` — HTML with embedded base64 images
- `.md` — Markdown

## Image Generation

### Aspect Ratios
| Aspect | Size | Use Case |
|--------|------|----------|
| `square` / `1:1` | 1024x1024 | PPTX split-layout slides |
| `landscape` / `16:9` | 1792x1024 | PPTX full-bleed slides |
| `portrait` / `9:16` | 1024x1792 | Mobile wallpapers |
| `photo` / `4:3` | 1365x1024 | Photo-style |

### Models
- Default (auto-routed by middleware)
- `gemini-3-pro-image-preview` — Gemini multimodal
- `imagen-4.0-generate-001` — Google Imagen
- `flux-2-pro` / `flux-2-max` — Black Forest Labs FLUX.2

## Music Generation (Lyria 3 Pro)

### Workflow
1. BUD-E drafts a prompt + lyrics and shows them to the user
2. User confirms or modifies
3. BUD-E calls `generate_music` with the final prompt

### Capabilities
- Full songs with vocals up to 184 seconds (~3 minutes)
- Lyrics with `[Verse]`, `[Chorus]`, `[Bridge]`, `[Outro]` tags
- MP3 output at 44.1kHz / 192kbps
- Multiple languages supported

## Safety Nets

BUD-E has programmatic fallbacks when the LLM doesn't use the right tool:
- **File creation**: If user asks for a document but LLM answers inline, an agent is force-spawned
- **Bildungsplan search**: If user asks about curricula but LLM answers from memory, a BM25 search is auto-triggered and results appended with PDF links
- **Presentation detection**: Requests for presentations auto-set `maxSteps: 20` and image limits
