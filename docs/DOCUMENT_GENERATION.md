# Document Generation

BUD-E can create professional documents through its sub-agent system.

## Supported Formats

### Word Documents (.docx)
- Generated from Markdown content
- Calibri 11pt font, blue headings
- Embedded images via `IMG_xxx` references
- Automatic DOCX ZIP construction (no external library needed)

### PowerPoint Presentations (.pptx)
Built with 4 adaptive slide layouts:

| Layout | When Used | Description |
|--------|-----------|-------------|
| **Title Slide** | First slide | Gradient background, large centered title + subtitle + accent line |
| **Image + Bullets** | Slide has image + text | Dark title bar, image left (adaptive to aspect ratio), bullets right |
| **Image Only** | Slide has image, no text | Title bar + full-bleed image below |
| **Text Only** | No image | Title bar + bullets on light background |

**Design system:**
- Navy title bar (`#1B2A4A`) with blue accent line (`#3498DB`)
- Calibri font throughout
- Blue bullet markers with `**bold**` support
- Auto-fit text when too many bullets
- Slide numbers in bottom-right corner
- Adaptive image sizing based on actual PNG/JPEG dimensions

**Workflow:**
1. Agent researches topic (Wikipedia + web search)
2. Generates images per slide (aspect="square" for split, "landscape" for full-bleed)
3. Writes PPTX with structured content
4. Quality control verifies output

### PDF Documents (.pdf)
- Generated from Markdown
- Helvetica font family
- Clean layout with proper margins

### HTML Documents (.html)
- Full HTML with inline CSS
- Images auto-embedded as base64 data URLs
- `IMG_xxx` references auto-resolved from image registry

## Image Embedding

The sub-agent generates images with `generate_image` and receives an `IMG_xxx` ID. When writing documents:
- **DOCX**: Images embedded in the ZIP as media files
- **PPTX**: Images embedded as slide media with proper positioning
- **HTML**: `IMG_xxx` references replaced with `data:image/...;base64,...` URLs
- **Orphaned references**: `IMG_xxx` IDs that failed generation are silently removed (not shown as text)

## File Lock Handling

If a PPTX/DOCX is already open in another application, BUD-E automatically generates an alternative filename with a timestamp suffix instead of failing.
