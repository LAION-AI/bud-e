import { agreementContentRaw } from "./agreement-content.ts";

export const headerContent: InternalizationContent = {
  en: {
    overTitle: "Experimental",
    title: "School Bud-E!",
  },
  de: {
    overTitle: "Experimenteller",
    title: "School Bud-E!",
  },
};

export const agreementContent: InternalizationContent = agreementContentRaw;

export const menuContent: InternalizationContent = {
  en: {
    about: "About School Bud-E",
    imprint: "Imprint",
  },
  de: {
    about: "Über School Bud-E",
    imprint: "Impressum",
  },
};

export const warningContent: InternalizationContent = {
  en: {
    title: "🚧 Experimental Demo Version 🚧",
    content:
      "Please note that this is an early prototype application that may provide inaccurate answers or generate content that is not suitable for all audiences. We advise caution and encourage you to report any issues you encounter to us.",
    usage:
      `**School Bud-E Features**
1.: Wikipedia search (**#wikipedia**: search term)
2.: Paper search (**#papers**: search term)
3.: Search the Hamburger Bildungsplan (**#bildungsplan**: search term)
4.: Correction of student assignments (only **#correction** or **#korrektur** with image upload)
5.: Image generation (**#imagegen**: prompt) or (**#imagegen**:model:prompt)

Points 1 to 3 can optionally be followed by :top_n to limit the number of results.
Example: **#wikipedia: Artificial Intelligence:3**

Alternatively to #wikipedia, you can also use **#wikipedia_de** or **#wikipedia_en** to set the language of the Wikipedia search.
Example: **#wikipedia_de: Artificial Intelligence**

---

## 🎨 Image Generation & Editing Guide

### Available Models:
| Model | Description | Best For |
|-------|-------------|----------|
| **nano-banana** | Gemini 2.5 Flash (default) | Fast generation |
| **nano-banana-pro** | Gemini 3 Pro | Best quality |
| **flux-2-klein** | FLUX.2 Klein 9B | Sub-second, fast |
| **flux-2-klein-4b** | FLUX.2 Klein 4B | Fastest |
| **flux-2-pro** | FLUX.2 Pro | Production quality |
| **flux-2-max** | FLUX.2 Max | Maximum quality |
| **dall-e-3** | OpenAI DALL-E 3 | Creative images |

### Hashtag Format (#):
**Basic generation (default model):**
\`#imagegen: A colorful butterfly in a garden\`

**With specific model:**
\`#imagegen:nano-banana-pro: A photorealistic mountain landscape\`
\`#imagegen:flux-2-pro: A cinematic portrait with soft lighting\`
\`#imagegen:flux-2-max: A detailed oil painting of a forest\`
\`#imagegen:flux-2-klein: A simple logo design\`

### JSON Format {}:
**Basic generation:**
\`{"imagegen": "A colorful butterfly in a garden"}\`

**With specific model:**
\`{"imagegen": {"prompt": "A photorealistic landscape", "model": "nano-banana-pro"}}\`
\`{"imagegen": {"prompt": "A cinematic portrait", "model": "flux-2-pro"}}\`
\`{"imagegen": {"prompt": "Maximum quality artwork", "model": "flux-2-max"}}\`

**With all parameters:**
\`{"imagegen": {"prompt": "A sunset over mountains", "model": "flux-2-pro", "n": 2, "size": "1024x1024", "aspectRatio": "16:9"}}\`

### Image Editing (imageedit):
**Edit the last image (any model):**
\`{"imageedit": "Add flying birds to the sky"}\`

**Edit with specific model:**
\`{"imageedit": {"prompt": "Transform to oil painting style", "model": "flux-2-max"}}\`
\`{"imageedit": {"prompt": "Add neon lights", "model": "flux-2-pro", "use_last_image": true}}\`
\`{"imageedit": {"prompt": "Make it look vintage", "model": "nano-banana-pro"}}\`

**Edit specific image by ID:**
\`{"imageedit": {"prompt": "Add butterflies", "model": "flux-2-pro", "image_id": "gen_00001"}}\`

**Combine multiple images:**
\`{"imageedit": {"prompt": "Blend these images", "model": "flux-2-max", "image_ids": ["gen_00001", "upl_00002"]}}\`

### Parameters Reference:
| Parameter | Values | Description |
|-----------|--------|-------------|
| **prompt** | text | Image description |
| **model** | see above | Model to use |
| **n** | 1-4 | Number of images |
| **size** | "1024x1024" | Dimensions |
| **aspectRatio** | "16:9", "1:1" | Aspect ratio |
| **use_last_image** | true/false | Use last image |
| **image_id** | "gen_00001" | Specific image |
| **image_ids** | ["id1","id2"] | Multiple images |

**Support Email**: contact@laion.ai`,
  },
  de: {
    title: "🚧 Experimentelle Demoversion 🚧",
    content:
      "Bitte beachten Sie, dass dies eine frühe Prototyp-Anwendung ist, die möglicherweise ungenaue Antworten liefert oder Inhalte erzeugt, die nicht für alle Zielgruppen geeignet sind. Wir raten zur Vorsicht und raten Ihnen uns alle Probleme, die Sie feststellen, mitzuteilen.",
    usage:
      `**School Bud-E Funktionen**
1.: Wikipedia-Suche (**#wikipedia**: Suchbegriff)
2.: Paper-Suche (**#papers**: Suchbegriff)
3.: Suche im Hamburger Bildungsplan (**#bildungsplan**: Suchbegriff)
4.: Korrektur von Schüleraufgaben (nur **#korrektur** oder **#correction** mit Bilderupload)
5.: Bildgenerierung (**#imagegen**: Prompt) oder (**#imagegen**:Modell:Prompt)

Punkte 1 bis 3 können optional mit einem :top_n am Ende versehen werden, um die Anzahl der Ergebnisse zu begrenzen.
Beispiel: **#wikipedia: Künstliche Intelligenz:3**

Alternativ zu #wikipedia kann auch **#wikipedia_de** oder **#wikipedia_en** verwendet werden, um die Sprache der Wikipedia-Suche festzulegen.
Beispiel: **#wikipedia_de: Künstliche Intelligenz**

---

## 🎨 Bildgenerierung & Bearbeitung Anleitung

### Verfügbare Modelle:
| Modell | Beschreibung | Ideal für |
|--------|--------------|-----------|
| **nano-banana** | Gemini 2.5 Flash (Standard) | Schnelle Generierung |
| **nano-banana-pro** | Gemini 3 Pro | Beste Qualität |
| **flux-2-klein** | FLUX.2 Klein 9B | Unter 1 Sekunde |
| **flux-2-klein-4b** | FLUX.2 Klein 4B | Am schnellsten |
| **flux-2-pro** | FLUX.2 Pro | Produktionsqualität |
| **flux-2-max** | FLUX.2 Max | Maximale Qualität |
| **dall-e-3** | OpenAI DALL-E 3 | Kreative Bilder |

### Hashtag-Format (#):
**Einfache Generierung (Standardmodell):**
\`#imagegen: Ein bunter Schmetterling im Garten\`

**Mit bestimmtem Modell:**
\`#imagegen:nano-banana-pro: Eine fotorealistische Berglandschaft\`
\`#imagegen:flux-2-pro: Ein filmisches Portrait mit weichem Licht\`
\`#imagegen:flux-2-max: Ein detailliertes Ölgemälde eines Waldes\`
\`#imagegen:flux-2-klein: Ein einfaches Logo-Design\`

### JSON-Format {}:
**Einfache Generierung:**
\`{"imagegen": "Ein bunter Schmetterling im Garten"}\`

**Mit bestimmtem Modell:**
\`{"imagegen": {"prompt": "Eine fotorealistische Landschaft", "model": "nano-banana-pro"}}\`
\`{"imagegen": {"prompt": "Ein filmisches Portrait", "model": "flux-2-pro"}}\`
\`{"imagegen": {"prompt": "Kunstwerk in maximaler Qualität", "model": "flux-2-max"}}\`

**Mit allen Parametern:**
\`{"imagegen": {"prompt": "Ein Sonnenuntergang über Bergen", "model": "flux-2-pro", "n": 2, "size": "1024x1024", "aspectRatio": "16:9"}}\`

### Bildbearbeitung (imageedit):
**Letztes Bild bearbeiten (beliebiges Modell):**
\`{"imageedit": "Füge fliegende Vögel am Himmel hinzu"}\`

**Bearbeitung mit bestimmtem Modell:**
\`{"imageedit": {"prompt": "In Ölgemälde-Stil umwandeln", "model": "flux-2-max"}}\`
\`{"imageedit": {"prompt": "Neonlichter hinzufügen", "model": "flux-2-pro", "use_last_image": true}}\`
\`{"imageedit": {"prompt": "Vintage-Look erzeugen", "model": "nano-banana-pro"}}\`

**Bestimmtes Bild per ID bearbeiten:**
\`{"imageedit": {"prompt": "Schmetterlinge hinzufügen", "model": "flux-2-pro", "image_id": "gen_00001"}}\`

**Mehrere Bilder kombinieren:**
\`{"imageedit": {"prompt": "Diese Bilder verschmelzen", "model": "flux-2-max", "image_ids": ["gen_00001", "upl_00002"]}}\`

### Parameter-Übersicht:
| Parameter | Werte | Beschreibung |
|-----------|-------|--------------|
| **prompt** | Text | Bildbeschreibung |
| **model** | siehe oben | Zu verwendendes Modell |
| **n** | 1-4 | Anzahl der Bilder |
| **size** | "1024x1024" | Abmessungen |
| **aspectRatio** | "16:9", "1:1" | Seitenverhältnis |
| **use_last_image** | true/false | Letztes Bild verwenden |
| **image_id** | "gen_00001" | Bestimmtes Bild |
| **image_ids** | ["id1","id2"] | Mehrere Bilder |

**Support Email**: contact@laion.ai`,
  },
};

export const chatIslandContent: InternalizationContent = {
  en: {
    welcomeMessage:
      "Hello! I am School Bud-E, your personal AI assistant. How can I help you today?",
    deleteCurrentChat: "current chat",
    deleteAllChats: "all chats",
    backupChat: "Download",
    restoreChat: "Upload",
    placeholderText: "Chat with the School Bud-E...",
    wikipediaTitle: "Title",
    wikipediaContent: "Content",
    wikipediaURL: "URL",
    wikipediaScore: "Score",
    papersDOI: "DOI",
    papersTitle: "Title",
    papersSubjects: "Type",
    papersAuthors: "Authors",
    papersAbstract: "Abstract",
    papersDate: "Date",
    result: "Result",
    of: "of",
    noSettings:
      "⚠️ The minimum requirement to run the chat is missing. You need to open the settings and either provide an Universal API key or a custom API key with the corresponding url and model. ⚠️",
    imageGenError: "Image generation error",
    imageGenNoImages: "No images were generated",
    imageGenGenerated: "Generated image",
    imageGenPrompt: "Prompt",
    imageGenModel: "Model",
  },
  de: {
    welcomeMessage:
      "Hallo! Ich bin School Bud-E, dein persönlicher Assistent. Wie kann ich dir helfen?",
    deleteCurrentChat: "diesen Chat",
    deleteAllChats: "alle Chats",
    backupChat: "Download",
    restoreChat: "Upload",
    placeholderText: "Schreibe mit dem School Bud-E...",
    wikipediaTitle: "Titel",
    wikipediaContent: "Inhalt",
    wikipediaURL: "URL",
    wikipediaScore: "Score",
    papersDOI: "DOI",
    papersTitle: "Titel",
    papersSubjects: "Typ",
    papersAuthors: "Autoren",
    papersAbstract: "Abstract",
    papersDate: "Datum",
    result: "Ergebnis",
    of: "von",
    noSettings:
      "⚠️ Die Mindestanforderung zum Ausführen des Chats fehlt. Du musst die Einstellungen öffnen und entweder einen Universal-API-Schlüssel oder einen benutzerdefinierten API-Schlüssel mit der entsprechender URL und dem Modell eintragen. ⚠️",
    imageGenError: "Bildgenerierungsfehler",
    imageGenNoImages: "Es wurden keine Bilder generiert",
    imageGenGenerated: "Generiertes Bild",
    imageGenPrompt: "Prompt",
    imageGenModel: "Modell",
  },
};

export const chatTemplateContent: InternalizationContent = {
  "en": {
    readOutText: "Read out text",
    silent: "Silent",
    autoScrollOn: "Auto scroll",
    autoScrollOff: "Manual scroll",
  },
  "de": {
    readOutText: "Text vorlesen",
    silent: "Stumm",
    autoScrollOn: "Automatisch scrollen",
    autoScrollOff: "Manuelles scrollen",
  },
};
export const chatContent: InternalizationContent = {
  en: {
    systemPrompt:
      "You are an intelligent and empathetic learning assistant. Always respond empathetically, friendly, curiously and appropriately to the school context. Respond briefly and to the point. Your name is School Bud-E and you would be created by LAION. LAION is a non-profit organization for the democratization of open source AI. Try to keep the conversation friendly, educational and entertaining and to keep it running while taking into account previously said information. Respond briefly, concisely and to the point. When someone talks to you or asks you a question, you must always reply in the same language they are using at that moment. For example, if someone is talking to you in German but then switches to English, you must reply in English. If someone asks you something in Chinese, you must reply in Chinese. It's important to always use the language the person last spoke in. Try your best to be inspiring and to spark curiosity and essence of wonder and beauty in the world. (Never output asterisks *)\n\nYou may also perform external searches and generate images, but **only if the user explicitly asks you**. If the user asks you to search in Wikipedia, the Hamburg educational curricula (Bildungsplan), or in scientific papers/publications, then you must trigger such a search by outputting a **single JSON object** in one of these formats:\n\n- `{\"wikipedia\": \"topic\"}`\n- `{\"wikipedia_de\": \"Thema\"}` or `{\"wikipedia_en\": \"topic\"}`\n- `{\"bildungsplan\": {\"q\": \"term\", \"n\": 5}}`\n- `{\"papers\": {\"q\": \"query\", \"n\": 10}}`\n\n**Image Generation**: If the user asks you to create, generate, or draw an image, you can trigger image generation by outputting a JSON object:\n\n- `{\"imagegen\": \"detailed description of the image\"}` (uses default: flux-2-klein)\n- `{\"imagegen\": {\"prompt\": \"description\", \"model\": \"MODEL_NAME\"}}` (with specific model)\n\n**Available models**: flux-2-klein (fast, DEFAULT), flux-2-pro (quality), flux-2-max (best quality), nano-banana-pro (Gemini 3 Pro), dall-e-3.\n\n**IMPORTANT**: If the user mentions a model name (like \"Flux\", \"Flux Klein\", \"Flux Pro\", \"Flux Max\", \"DALL-E\"), you MUST include it in the model field. Map spoken names: \"Flux Klein\" → \"flux-2-klein\", \"Flux Pro\" → \"flux-2-pro\", \"Flux Max\" → \"flux-2-max\", \"Flux\" → \"flux-2-pro\".\n\n**Aspect Ratio**: If the user mentions an aspect ratio (\"16:9\", \"widescreen\", \"portrait\", \"square\", \"9:16\", \"4:3\", \"21:9\"), include it as \"aspectRatio\" in the JSON. Map: \"widescreen\"/\"cinematic\" → \"16:9\", \"portrait\"/\"vertical\" → \"9:16\", \"square\" → \"1:1\", \"ultrawide\" → \"21:9\".\nExample: `{\"imagegen\": {\"prompt\": \"A sunset\", \"model\": \"flux-2-klein\", \"aspectRatio\": \"16:9\"}}`\n\n**Image Editing**: To edit/modify an existing image, use `imageedit` instead of `imagegen`. Reference images by their ID (shown as gen_00001, gen_00002, etc. for generated images, or upl_00001 for uploaded images):\n- Edit the last generated image: `{\"imageedit\": {\"prompt\": \"Add a rainbow\", \"use_last_image\": true}}`\n- Edit a specific image by ID: `{\"imageedit\": {\"prompt\": \"Make it night time\", \"image_id\": \"gen_00001\"}}`\n- Edit with specific model: `{\"imageedit\": {\"prompt\": \"Add more details\", \"model\": \"flux-2-pro\", \"use_last_image\": true}}`\n\nWhen the user says \"edit this image\", \"modify the image\", \"add X to the image\", \"change the image\", use `imageedit` with `use_last_image: true` or the specific `image_id`.\n\n**Character Consistency**: When the user asks you to generate a new image of a character, person, or subject that was ALREADY depicted in a previous generated or uploaded image in this conversation, you MUST use `imageedit` (not `imagegen`) and reference that earlier image. This preserves visual consistency (same face, style, features). For example: if an image of \"Alice\" was generated as gen_00001, and the user later says \"show me Alice in a red dress\", use `{\"imageedit\": {\"prompt\": \"Same character now wearing a red dress\", \"image_id\": \"gen_00001\"}}`. Always pick the best reference image for the character. Only use `imagegen` for entirely new subjects with no prior reference.\n\nDo not wrap the JSON in explanations, prose, or Markdown. The action will only run once the JSON object is complete (closed with `}`). After search results arrive, you will automatically summarize them for the user. Do not use any other formats (such as hashtags or exclamation marks).",
    correctionSystemPrompt:
      `This Vision Language Model is specialized in supporting teachers in correcting tests, exams, and assessments. It accurately analyzes the submitted documents, transcribes them with the highest accuracy, and creates well-founded, empathetic, and customizable correction suggestions that adapt to the teacher's expectations and the students' level. ... (unchanged) ...`,
  },
  de: {
    systemPrompt:
      "Du bist ein sehr intelligenter, empathischer, geduldiger Lernassistent. Antworte immer empathisch, freundlich, neugierig und dem Kontext Schule angemessen. Antworte kurz und auf den Punkt gebracht. Dein Name ist School Bud-E und Du würdest von LAION erschaffen. LAION ist ein gemeinnütziger Verein zur Demokratisierung von Open Source AI. Wenn jemand mit dir spricht oder dir eine Frage stellt, musst du immer in der Sprache antworten, in der die Person dich gerade angesprochen hat. Wenn jemand zum Beispiel auf Deutsch mit dir redet und dann plötzlich auf Englisch wechselt, musst du auf Englisch antworten. Wenn jemand dir eine Frage auf Chinesisch stellt, musst du auf Chinesisch antworten. Es ist wichtig, immer die Sprache zu verwenden, die die Person zuletzt benutzt hat. Versuche so gut es geht die Unterhaltung freundlich, inspirierend und unterhaltsam am Laufen zu halten.\n\nDu darfst auch externe Suchen durchführen und Bilder generieren, aber **nur wenn der Nutzer dich ausdrücklich dazu auffordert**. Wenn der Nutzer dich bittet, etwas in Wikipedia, im Hamburger Bildungsplan oder in wissenschaftlichen Veröffentlichungen (Scientific Papers) zu recherchieren, dann sollst du dies durch Ausgabe eines **einzigen JSON-Objekts** tun, z. B.:\n\n- `{\"wikipedia\": \"Thema\"}`\n- `{\"wikipedia_de\": \"Thema\"}` bzw. `{\"wikipedia_en\": \"topic\"}`\n- `{\"bildungsplan\": {\"q\": \"Begriff\", \"n\": 5}}`\n- `{\"papers\": {\"q\": \"Suchanfrage\", \"n\": 10}}`\n\n**Bildgenerierung**: Wenn der Nutzer dich bittet, ein Bild zu erstellen, generieren oder zu zeichnen, kannst du die Bildgenerierung durch Ausgabe eines JSON-Objekts auslösen:\n\n- `{\"imagegen\": \"detaillierte Beschreibung des Bildes\"}` (nutzt Standard: flux-2-klein)\n- `{\"imagegen\": {\"prompt\": \"Beschreibung\", \"model\": \"MODELLNAME\"}}` (mit spezifischem Modell)\n\n**Verfügbare Modelle**: flux-2-klein (schnell, STANDARD), flux-2-pro (Qualität), flux-2-max (beste Qualität), nano-banana-pro (Gemini 3 Pro), dall-e-3.\n\n**WICHTIG**: Wenn der Nutzer einen Modellnamen nennt (z.B. \"Flux\", \"Flux Klein\", \"Flux Pro\", \"Flux Max\", \"DALL-E\"), MUSST du diesen im model-Feld angeben. Zuordnung: \"Flux Klein\" → \"flux-2-klein\", \"Flux Pro\" → \"flux-2-pro\", \"Flux Max\" → \"flux-2-max\", \"Flux\" → \"flux-2-pro\".\n\n**Seitenverhältnis**: Wenn der Nutzer ein Seitenverhältnis nennt (\"16:9\", \"Breitbild\", \"Hochformat\", \"quadratisch\", \"9:16\", \"4:3\", \"21:9\"), füge es als \"aspectRatio\" im JSON hinzu. Zuordnung: \"Breitbild\"/\"filmisch\"/\"Kino\" → \"16:9\", \"Hochformat\"/\"vertikal\" → \"9:16\", \"quadratisch\" → \"1:1\", \"Ultrabreitbild\" → \"21:9\".\nBeispiel: `{\"imagegen\": {\"prompt\": \"Ein Sonnenuntergang\", \"model\": \"flux-2-klein\", \"aspectRatio\": \"16:9\"}}`\n\n**Bildbearbeitung**: Um ein bestehendes Bild zu bearbeiten/ändern, nutze `imageedit` statt `imagegen`. Referenziere Bilder über ihre ID (angezeigt als gen_00001, gen_00002 usw. für generierte Bilder, oder upl_00001 für hochgeladene Bilder):\n- Letztes generiertes Bild bearbeiten: `{\"imageedit\": {\"prompt\": \"Füge einen Regenbogen hinzu\", \"use_last_image\": true}}`\n- Bestimmtes Bild per ID bearbeiten: `{\"imageedit\": {\"prompt\": \"Mache es zur Nachtszene\", \"image_id\": \"gen_00001\"}}`\n- Mit bestimmtem Modell bearbeiten: `{\"imageedit\": {\"prompt\": \"Füge mehr Details hinzu\", \"model\": \"flux-2-pro\", \"use_last_image\": true}}`\n\nWenn der Nutzer sagt \"bearbeite dieses Bild\", \"ändere das Bild\", \"füge X zum Bild hinzu\", \"verändere das Bild\", nutze `imageedit` mit `use_last_image: true` oder der spezifischen `image_id`.\n\n**Charakterkonsistenz**: Wenn der Nutzer ein neues Bild eines Charakters, einer Person oder eines Motivs anfordert, das BEREITS in einem früheren generierten oder hochgeladenen Bild in dieser Unterhaltung abgebildet wurde, MUSST du `imageedit` (nicht `imagegen`) verwenden und auf dieses frühere Bild verweisen. Dies bewahrt die visuelle Konsistenz (gleiches Gesicht, Stil, Merkmale). Beispiel: Wenn ein Bild von \"Alice\" als gen_00001 generiert wurde und der Nutzer später sagt \"zeig mir Alice in einem roten Kleid\", nutze `{\"imageedit\": {\"prompt\": \"Gleicher Charakter jetzt in einem roten Kleid\", \"image_id\": \"gen_00001\"}}`. Wähle immer das beste Referenzbild für den Charakter. Nutze `imagegen` nur für völlig neue Motive ohne vorherige Referenz.\n\nSchreibe das JSON ohne zusätzliche Erklärungen, Fließtext oder Markdown. Die Aktion wird nur ausgeführt, wenn das JSON vollständig geschlossen ist (mit `}`). Nachdem Suchergebnisse vorliegen, fasst du sie automatisch für den Nutzer zusammen. Verwende keine anderen Formate (wie Hashtags oder Ausrufezeichen).",
    correctionSystemPrompt:
      `Dieses Vision Language Model ist darauf spezialisiert, Lehrkräfte bei der Korrektur von Tests, Klassenarbeiten und Prüfungen zu unterstützen. ... (unverändert) ...`,
  },
};

export const aboutContent: InternalizationContent = {
  en: {
    title: "About School Bud-E",
    partOneOne:
      "In today's world, where education is increasingly intertwined with technology, School Bud-E emerges as an empathetic AI voice assistant specifically designed for the dynamic needs of the education sector. Developed by",
    partOneTwo:
      "in collaboration with the ELLIS Institute Tübingen, Collabora, and the Tübingen AI Center, School Bud-E enables the learning experience with a focus on empathy, natural interaction, and",
    headingOne: "Redefining Education with AI",
    partTwoOne:
      "School Bud-E is not just an AI voice assistant; it is a digital companion that supports educational growth through:",
    partTwoTwo:
      "Real-time responses to student queries that facilitate immediate learning opportunities.",
    partTwoThree:
      "Emotionally intelligent interactions that recognize the learner's emotional state and adapt to it to foster a supportive learning environment.",
    partTwoFour:
      "Maintaining conversation context across sessions, enabling personalized learning experiences that build over time.",
    partTwoFive:
      "Handling complex multi-speaker scenarios, such as classroom discussions in multiple languages.",
    partTwoSix:
      "Operating on local, consumer-grade hardware, ensuring privacy and accessibility.",
    headingTwo: "Technological Innovation for Education",
    partThreeOne:
      "At the core of School Bud-E's development is the pursuit of low latency and maximum conversational naturalness. Through rigorous testing and evaluating various speech-to-text, speech understanding, and text-to-speech models, the team has achieved remarkable responsiveness and quality on devices common in schools.",
    partThreeTwo:
      "Since January 2024, School Bud-E has been operating with latencies between 300 and 500 ms, promising near-instant interaction that is crucial to keeping students engaged and supporting educators in real time.",
    headingThree: "Supporting the Education Revolution",
    partFourOne:
      "The development of School Bud-E is an ongoing collaboration. We are committed to continuously enhancing its capabilities to better serve students and educators alike. From reducing system requirements and latency to enriching its understanding of conversational nuances, each update aims to make School Bud-E an indispensable asset in educational institutions. At the same time, we are building an architecture that enables the technology to be implemented in various educational environments, to scale, and to integrate modules tailored to the specific needs of students and educators in different learning settings.",
    partFourTwo:
      "Are you interested in contributing to the School Bud-E project or integrating it into your suite of educational technologies? Then join our",
    partFourThree: "or contact us directly at",
  },
  de: {
    title: "Über School Bud-E",
    partOneOne:
      "In der heutigen Zeit, in der Bildung zunehmend mit Technologie verflochten ist, tritt School Bud-E als empathischer KI-Sprachassistent hervor, der speziell für die dynamischen Bedürfnisse im Bildungsbereich entwickelt wurde. Entwickelt von",
    partOneTwo:
      "in Zusammenarbeit mit dem ELLIS-Institut Tübingen, Collabora und dem Tübinger KI-Zentrum, ermöglicht School Bud-E das Lernerlebnis mit einem Schwerpunkt auf Empathie, natürliche Interaktion und",
    headingOne: "Bildung mit KI neu definieren",
    partTwoOne:
      "School Bud-E ist nicht nur ein KI-Sprachassistent; es ist ein digitaler Begleiter, der das Bildungswachstum durch unterstützt:",
    partTwoTwo:
      "Echtzeit-Antworten auf Schüleranfragen, die sofortige Lernmöglichkeiten erleichtern.",
    partTwoThree:
      "Emotional intelligente Interaktionen, die den emotionalen Zustand des Lernenden erkennen und sich an diesen anpassen, um eine unterstützende Lernumgebung zu fördern.",
    partTwoFour:
      "Beibehaltung des Gesprächskontexts über Sitzungen hinweg, was personalisierte Lernerfahrungen ermöglicht, die sich im Laufe der Zeit aufbauen.",
    partTwoFive:
      "Bewältigung von komplexen Mehrsprecher-Szenarien, wie Klassenzimmerdiskussionen auf mehreren Sprachen.",
    partTwoSix:
      "Betrieb auf lokaler, verbraucherüblicher Hardware, gewährleistet Datenschutz und Zugänglichkeit.",
    headingTwo: "Technologische Innovation für die Bildung",
    partThreeOne:
      "Im Mittelpunkt der Entwicklung von School Bud-E steht das Streben nach geringer Latenz und maximaler Natürlichkeit im Gespräch. Durch rigoroses Testen und Evaluieren verschiedener Sprach-zu-Text-, Sprachverständnis- und Text-zu-Sprach-Modelle hat das Team eine bemerkenswerte Reaktionsfähigkeit und Qualität auf Geräten erreicht, die in Schulen üblich sind.",
    partThreeTwo:
      "Seit Januar 2024 arbeitet School Bud-E mit Latenzen zwischen 300 und 500 ms und verspricht eine nahezu sofortige Interaktion, die entscheidend ist, um Schüler engagiert zu halten und Pädagogen in Echtzeit zu unterstützen.",
    headingThree: "Unterstützt die Bildungsrevolution",
    partFourOne:
      "Die Entwicklung von School Bud-E ist eine fortwährende Zusammenarbeit. Wir sind darauf bedacht, seine Fähigkeiten kontinuierlich zu verbessern, um Schülern und Pädagogen gleichermaßen besser zu dienen. Von der Reduzierung der Systemanforderungen und Latenz bis zur Bereicherung seines Verständnisses für konversationelle Nuancen zielt jedes Update darauf ab, School Bud-E zu einem unverzichtbaren Vermögenswert in Bildungseinrichtungen zu machen. Gleichzeitig erschaffen bauen wir eine Architektur, die es ermöglicht, die Technologie in verschiedenen Bildungsumgebungen zu implementieren, zu skalieren und Module zu integrieren, die auf die spezifischen Bedürfnisse von Schülern und Pädagogen in verschiedenen Lernsettings zugeschnitten sind.",
    partFourTwo:
      "Sind Sie interessiert, am School Bud-E Projekt mitzuarbeiten oder es in Ihre Suite von Bildungstechnologien zu integrieren? Dann treten Sie unserem",
    partFourThree: "bei oder kontaktieren Sie uns direkt unter",
  },
};

export const settingsContent: InternalizationContent = {
  en: {
    title: "Settings",
    apiUrlLabel: "LLM API URL (url containing /v1/chat/completions)",
    apiUrlPlaceholder: "Enter API URL",
    apiKeyLabel: "LLM API Key",
    apiKeyPlaceholder: "Enter API Key",
    modelLabel: "LLM Model",
    modelPlaceholder: "Enter Model Name",
    ttsUrlLabel: "TTS API URL",
    ttsUrlPlaceholder: "Enter TTS API URL",
    ttsKeyLabel: "TTS API Key",
    ttsKeyPlaceholder: "Enter TTS API Key",
    ttsModelLabel: "TTS Model",
    ttsModelPlaceholder: "Enter TTS Model Name",
    sttUrlLabel: "STT API URL (url containing /v1/audio/transcriptions)",
    sttUrlPlaceholder: "Enter STT API URL",
    sttKeyLabel: "STT API Key",
    sttKeyPlaceholder: "Enter STT API Key",
    sttModelLabel: "STT Model",
    sttModelPlaceholder: "Enter STT Model Name",
    vlmUrlLabel: "VLM API URL (url containing /v1/chat/completions)",
    vlmUrlPlaceholder: "Enter VLM API URL",
    vlmKeyLabel: "VLM API Key",
    vlmKeyPlaceholder: "Enter VLM API Key",
    vlmModelLabel: "VLM Model",
    vlmModelPlaceholder: "Enter VLM Model Name",
    vlmCorrectionModelLabel: "VLM Correction Model",
    vlmCorrectionModelPlaceholder: "Enter VLM Correction Model Name",
    cancel: "Cancel",
    save: "Save",
    systemPromptLabel: "System Prompt",
    back: "Back",
    universalApiKeyLabel: "Universal API Key",
    universalApiKeyPlaceholder: "Enter your API key",
    advancedSettings: "Advanced Settings",
    lessSettings: "Less Settings",
    chatApiTitle: "Chat API",
    ttsTitle: "Text-to-Speech",
    sttTitle: "Speech-to-Text",
    vlmTitle: "Vision & PDF Language Model",
  },
  de: {
    title: "Einstellungen",
    apiUrlLabel: "LLM API URL (URL mit /v1/chat/completions)",
    apiUrlPlaceholder: "API URL eingeben",
    apiKeyLabel: "LLM API Schlüssel",
    apiKeyPlaceholder: "API Schlüssel eingeben",
    modelLabel: "LLM Modell",
    modelPlaceholder: "Modellname eingeben",
    ttsUrlLabel: "TTS API URL",
    ttsUrlPlaceholder: "TTS API URL eingeben",
    ttsKeyLabel: "TTS API Schlüssel",
    ttsKeyPlaceholder: "TTS API Schlüssel eingeben",
    ttsModelLabel: "TTS Modell",
    ttsModelPlaceholder: "TTS Modellname eingeben",
    sttUrlLabel: "STT API URL (URL mit /v1/audio/transcriptions)",
    sttUrlPlaceholder: "STT API URL eingeben",
    sttKeyLabel: "STT API Schlüssel",
    sttKeyPlaceholder: "STT API Schlüssel eingeben",
    sttModelLabel: "STT Modell",
    sttModelPlaceholder: "STT Modellname eingeben",
    vlmUrlLabel: "VLM API URL (URL mit /v1/chat/completions)",
    vlmUrlPlaceholder: "VLM API URL eingeben",
    vlmKeyLabel: "VLM API Schlüssel",
    vlmKeyPlaceholder: "VLM API Schlüssel eingeben",
    vlmModelLabel: "VLM Modell",
    vlmModelPlaceholder: "VLM Modellname eingeben",
    vlmCorrectionModelLabel: "VLM Korrektur Modell",
    vlmCorrectionModelPlaceholder: "VLM Korrektur Modellname eingeben",
    cancel: "Abbrechen",
    save: "Speichern",
    systemPromptLabel: "System Prompt",
    back: "Zurück",
    universalApiKeyLabel: "Universal API-Schlüssel",
    universalApiKeyPlaceholder: "Geben Sie Ihren API-Schlüssel ein",
    advancedSettings: "Erweiterte Einstellungen",
    lessSettings: "Weniger Einstellungen",
    chatApiTitle: "Chat API",
    ttsTitle: "Text-zu-Sprache",
    sttTitle: "Sprache-zu-Text",
    vlmTitle: "Bild- und PDF-Verarbeitung",
  },
};
