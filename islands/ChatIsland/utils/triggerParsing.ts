/**
 * @file triggerParsing.ts
 * @description Parsing utilities for detecting and extracting search triggers
 *              from user and assistant messages (hashtags and JSON blocks).
 * @importantFunctions findHashtagTriggersInUserText, findJsonTriggersInText, buildAutoSummaryPrompt
 */

import { AutoTrigger } from "../types.ts";
import { normalizeForTrigger } from "./textProcessing.ts";

/**
 * Extracts only complete (balanced braces) top-level JSON objects from a string.
 * Used to detect search triggers in streaming content.
 */
export const extractCompletedJsonSearchBlocks = (s: string): string[] => {
  const blocks: string[] = [];
  let depth = 0;
  let start = -1;
  let inString = false;
  let quote: string | null = null;
  let escape = false;

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];

    if (inString) {
      if (escape) {
        escape = false;
        continue;
      }
      if (ch === "\\") {
        escape = true;
        continue;
      }
      if (ch === quote) {
        inString = false;
        quote = null;
        continue;
      }
      continue;
    }

    if (ch === '"' || ch === "'") {
      inString = true;
      quote = ch;
      continue;
    }
    if (ch === "{") {
      if (depth === 0) start = i;
      depth++;
    } else if (ch === "}") {
      if (depth > 0) depth--;
      if (depth === 0 && start !== -1) {
        const block = s.slice(start, i + 1);
        if (/^\s*{\s*./.test(block) && /}\s*$/.test(block)) {
          blocks.push(block);
        }
        start = -1;
      }
    }
  }
  return blocks;
};

/**
 * Validates if an object is a recognized search trigger JSON structure.
 * Supports wikipedia, papers, bildungsplan, imagegen, and imageedit triggers.
 */
export const isValidSearchJson = (obj: unknown): boolean => {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return false;
  const allowed = new Set([
    "wikipedia",
    "wikipedia_de",
    "wikipedia_en",
    "papers",
    "bildungsplan",
    "imagegen",
    "imageedit",
  ]);
  const keys = Object.keys(obj);
  if (keys.length !== 1) return false;
  const key = keys[0].toLowerCase();
  if (!allowed.has(key)) return false;

  const v = (obj as Record<string, unknown>)[keys[0]];

  // Handle imagegen and imageedit (uses "prompt" instead of "q")
  if (key === "imagegen" || key === "imageedit") {
    if (typeof v === "string") return v.trim().length > 0;
    if (v && typeof v === "object") {
      const vObj = v as Record<string, unknown>;
      const prompt = (vObj.prompt ?? vObj.p ?? "").toString().trim();
      // imageedit can work with just input_images and no prompt for certain operations
      const hasInputImages = Array.isArray(vObj.input_images) && vObj.input_images.length > 0;
      const useLastImage = vObj.use_last_image === true || vObj.useLastImage === true;
      return prompt.length > 0 || hasInputImages || useLastImage;
    }
    return false;
  }

  // Handle search triggers (wikipedia, papers, bildungsplan)
  if (typeof v === "string") return v.trim().length > 0;

  if (v && typeof v === "object") {
    const vObj = v as Record<string, unknown>;
    const q = (vObj.q ?? vObj.query ?? vObj.text ?? "").toString().trim();
    if (!q) return false;
    if ("n" in vObj || "limit" in vObj || "top_n" in vObj) {
      const n = Number(vObj.n ?? vObj.limit ?? vObj.top_n);
      if (!Number.isFinite(n) || n <= 0) return false;
    }
    return true;
  }
  return false;
};

/**
 * Attempts lenient JSON parsing with common fixes for malformed JSON.
 */
export const tryParseJsonLenient = (raw: string): unknown | null => {
  try {
    return JSON.parse(raw);
  } catch {
    // Continue to lenient parsing
  }
  let s = raw.trim();
  // Convert single quotes to double quotes
  s = s
    .replace(/([{,\s])'([^']+?)'\s*:/g, '$1"$2":')
    .replace(/:\s*'([^']*?)'/g, ':"$1"');
  // Remove trailing commas
  s = s.replace(/,(\s*[}\]])/g, "$1");
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
};

/**
 * Converts a validated JSON object into AutoTrigger array.
 * Supports search triggers (wikipedia, papers, bildungsplan) and imagegen triggers.
 */
export const jsonObjToTriggers = (
  obj: Record<string, unknown>,
  lang: string
): AutoTrigger[] => {
  const triggers: AutoTrigger[] = [];
  if (!obj || typeof obj !== "object") return triggers;

  const normQ = (v: unknown): string => {
    if (typeof v === "string") return v.trim();
    if (v && typeof v === "object") {
      const vObj = v as Record<string, unknown>;
      return (vObj.q ?? vObj.query ?? vObj.text ?? "").toString().trim();
    }
    return "";
  };

  const normN = (v: unknown): number | undefined => {
    if (v && typeof v === "object") {
      const vObj = v as Record<string, unknown>;
      const n = vObj.n ?? vObj.limit ?? vObj.top_n;
      const nn = Number(n);
      return Number.isFinite(nn) && nn > 0 ? nn : undefined;
    }
    return undefined;
  };

  const keys = Object.keys(obj);
  for (const key of keys) {
    const k = key.toLowerCase();
    const val = obj[key];

    // Handle imagegen trigger
    if (k === "imagegen") {
      let prompt = "";
      let model: string | undefined;
      let n: number | undefined;
      let size: string | undefined;
      let aspectRatio: string | undefined;
      let inputImages: string[] | undefined;

      if (typeof val === "string") {
        prompt = val.trim();
      } else if (val && typeof val === "object") {
        const vObj = val as Record<string, unknown>;
        prompt = (vObj.prompt ?? vObj.p ?? "").toString().trim();
        model = vObj.model ? String(vObj.model).trim() : undefined;
        const nVal = vObj.n ?? vObj.count;
        n = nVal ? Number(nVal) : undefined;
        if (n !== undefined && (!Number.isFinite(n) || n <= 0)) n = undefined;
        size = vObj.size ? String(vObj.size).trim() : undefined;
        aspectRatio = (vObj.aspectRatio ?? vObj.aspect_ratio ?? vObj.ratio)
          ? String(vObj.aspectRatio ?? vObj.aspect_ratio ?? vObj.ratio).trim()
          : undefined;
        // Parse input_images for image editing
        const imgs = vObj.input_images ?? vObj.inputImages ?? vObj.reference_images;
        if (Array.isArray(imgs)) {
          inputImages = imgs.filter((img) => typeof img === "string" && img.length > 0);
        }
      }

      if (prompt) {
        triggers.push({ kind: "imagegen", prompt, model, n, size, aspectRatio, inputImages });
      }
      continue;
    }

    // Handle imageedit trigger (dedicated image editing)
    if (k === "imageedit") {
      let prompt = "";
      let model: string | undefined;
      let n: number | undefined;
      let inputImages: string[] | undefined;
      let useLastImage = false;
      let imageId: string | undefined; // Reference to specific image by ID
      let imageIds: string[] | undefined; // Multiple image IDs

      if (typeof val === "string") {
        prompt = val.trim();
        useLastImage = true; // If just a string, assume we want to edit the last image
      } else if (val && typeof val === "object") {
        const vObj = val as Record<string, unknown>;
        prompt = (vObj.prompt ?? vObj.p ?? "").toString().trim();
        model = vObj.model ? String(vObj.model).trim() : undefined;

        // Parse n (number of output images)
        const nVal = vObj.n ?? vObj.count;
        n = nVal ? Number(nVal) : undefined;
        if (n !== undefined && (!Number.isFinite(n) || n <= 0)) n = undefined;

        // Parse input_images (explicit base64 data URLs)
        const imgs = vObj.input_images ?? vObj.inputImages ?? vObj.reference_images;
        if (Array.isArray(imgs)) {
          inputImages = imgs.filter((img) => typeof img === "string" && img.length > 0);
        }

        // Parse image_id / image_ids (reference by unique ID)
        if (vObj.image_id || vObj.imageId) {
          imageId = String(vObj.image_id ?? vObj.imageId).trim();
        }
        if (Array.isArray(vObj.image_ids ?? vObj.imageIds)) {
          imageIds = (vObj.image_ids ?? vObj.imageIds as unknown[])
            .filter((id) => typeof id === "string" && id.length > 0) as string[];
        }

        // Check for explicit use_last_image flag
        const explicitUseLastImage = vObj.use_last_image ?? vObj.useLastImage;
        if (explicitUseLastImage === true) {
          useLastImage = true;
        } else if (explicitUseLastImage === false) {
          useLastImage = false;
        } else {
          // AUTO-DETECT: If no input_images and no image_id provided, default to useLastImage
          // This fixes the bug where {"imageedit": {"prompt": "...", "n": 2}} didn't work
          const hasExplicitImages = (inputImages && inputImages.length > 0) || imageId || (imageIds && imageIds.length > 0);
          if (!hasExplicitImages && prompt) {
            useLastImage = true;
          }
        }
      }

      // imageedit requires either a prompt or input_images or image reference
      if (prompt || (inputImages && inputImages.length > 0) || useLastImage || imageId || (imageIds && imageIds.length > 0)) {
        triggers.push({
          kind: "imageedit",
          prompt,
          model,
          n,
          inputImages,
          useLastImage,
          imageId,
          imageIds,
        });
      }
      continue;
    }

    // Handle search triggers
    if (
      ["wikipedia", "wikipedia_de", "wikipedia_en", "papers", "bildungsplan"].includes(k)
    ) {
      const q = normQ(val);
      const n = normN(val);
      if (!q) continue;

      if (k === "wikipedia" || k === "wikipedia_de" || k === "wikipedia_en") {
        let collection =
          lang === "en" ? "English-ConcatX-Abstract" : "German-ConcatX-Abstract";
        if (k.endsWith("_de")) collection = "German-ConcatX-Abstract";
        if (k.endsWith("_en")) collection = "English-ConcatX-Abstract";
        triggers.push({ kind: "wikipedia", q, n, collection, autoSummarize: true });
      } else if (k === "papers") {
        triggers.push({ kind: "papers", q, n, autoSummarize: true });
      } else if (k === "bildungsplan") {
        triggers.push({ kind: "bildungsplan", q, n, autoSummarize: true });
      }
    }
  }
  return triggers;
};

/**
 * Finds JSON-based triggers in text content.
 */
export const findJsonTriggersInText = (
  raw: string,
  lang: string,
  serverLog?: (stage: string, detail?: unknown) => Promise<void>
): AutoTrigger[] => {
  serverLog?.("json.detect.start", { sampleTail: raw.slice(-250) });

  const blocks = extractCompletedJsonSearchBlocks(raw);
  const all: AutoTrigger[] = [];

  for (const b of blocks) {
    let obj: unknown = null;
    try {
      obj = JSON.parse(b);
    } catch {
      obj = null;
    }
    if (!obj) {
      obj = tryParseJsonLenient(b);
    }
    if (!obj || !isValidSearchJson(obj)) continue;
    all.push(...jsonObjToTriggers(obj as Record<string, unknown>, lang));
  }

  serverLog?.("json.detect.done", { triggers: all });

  return all;
};

/**
 * Finds legacy hashtag-based triggers in user text.
 * Supports #wikipedia, #papers, #bildungsplan, and #imagegen with optional parameters.
 *
 * Image generation formats:
 * - #imagegen:prompt - generates image with default model (nano-banana)
 * - #imagegen:model:prompt - generates image with specified model
 */
export const findHashtagTriggersInUserText = (
  raw: string,
  lang: string,
  serverLog?: (stage: string, detail?: unknown) => Promise<void>
): AutoTrigger[] => {
  const t = normalizeForTrigger(raw);

  const rxWiki =
    /#\s*wikipedia(?:_(de|en))?\s*:\s*([^:\n]+?)(?:\s*:\s*(\d+))?(?=$|\s)/i;
  const rxPapers = /#\s*papers\s*:\s*([^:\n]+?)(?:\s*:\s*(\d+))?(?=$|\s)/i;
  const rxBP = /#\s*bildungsplan\s*:\s*([^:\n]+?)(?:\s*:\s*(\d+))?(?=$|\s)/i;
  // Match #imagegen:model:prompt or #imagegen:prompt (model is optional)
  // Model names typically don't contain spaces, so we use that to distinguish
  const rxImageGen = /#\s*imagegen\s*:\s*(?:([a-zA-Z0-9_-]+)\s*:\s*)?(.+?)(?=$|\n|#)/i;

  const triggers: AutoTrigger[] = [];

  const mW = t.match(rxWiki);
  if (mW) {
    const langSuffix = (mW[1] || "").toLowerCase();
    let collection =
      lang === "en" ? "English-ConcatX-Abstract" : "German-ConcatX-Abstract";
    if (langSuffix === "de") collection = "German-ConcatX-Abstract";
    if (langSuffix === "en") collection = "English-ConcatX-Abstract";
    const q = (mW[2] || "").trim();
    const n = mW[3] ? parseInt(mW[3], 10) : undefined;
    if (q) triggers.push({ kind: "wikipedia", q, n, collection, autoSummarize: false });
  }

  const mP = t.match(rxPapers);
  if (mP) {
    const q = (mP[1] || "").trim();
    const n = mP[2] ? parseInt(mP[2], 10) : undefined;
    if (q) triggers.push({ kind: "papers", q, n, autoSummarize: false });
  }

  const mB = t.match(rxBP);
  if (mB) {
    const q = (mB[1] || "").trim();
    const n = mB[2] ? parseInt(mB[2], 10) : undefined;
    if (q) triggers.push({ kind: "bildungsplan", q, n, autoSummarize: false });
  }

  // Image generation trigger
  const mImg = t.match(rxImageGen);
  if (mImg) {
    const modelOrPrompt = (mImg[1] || "").trim();
    const promptAfterModel = (mImg[2] || "").trim();

    // If we have both parts, first is model, second is prompt
    // If only second part, it's just the prompt (default model)
    let model: string | undefined;
    let prompt: string;

    if (modelOrPrompt && promptAfterModel) {
      model = modelOrPrompt;
      prompt = promptAfterModel;
    } else {
      // Only prompt, no model specified - use default
      prompt = promptAfterModel || modelOrPrompt;
      model = undefined;
    }

    if (prompt) {
      triggers.push({ kind: "imagegen", prompt, model });
    }
  }

  serverLog?.("hashtag.detect.done", { raw, triggers });

  return triggers;
};

/**
 * Builds a summarization prompt based on successful triggers.
 * Supports localStorage overrides and i18n.
 * Note: imagegen/imageedit triggers don't need summarization, but we handle them gracefully.
 */
export const buildAutoSummaryPrompt = (trigs: AutoTrigger[], lang: string): string => {
  const topics = trigs.map((t) => {
    // imagegen/imageedit triggers use 'prompt' instead of 'q'
    const query = (t.kind === "imagegen" || t.kind === "imageedit")
      ? (t as { prompt: string }).prompt
      : (t as { q: string }).q;
    return `${t.kind}: "${query}"`;
  }).join(", ");

  // Check for localStorage override
  const overrideKey =
    lang === "de" ? "bud-e-summary-template-de" : "bud-e-summary-template-en";
  const override =
    typeof localStorage !== "undefined" ? localStorage.getItem(overrideKey) : null;
  if (override && override.includes("{topics}")) {
    return override.replaceAll("{topics}", topics);
  }

  // Default prompts (ASCII-safe via \u escapes)
  if (lang === "de") {
    return `Bitte fasse die oben angezeigten Suchergebnisse (${topics}) pr\u00E4gnant zusammen:
- Nenne die Kernaussagen in klaren Stichpunkten.
- Hebe ggf. Relevanz f\u00FCr Unterricht/Kontext hervor.
- F\u00FCge am Ende 3\u20135 kurze Bulletpoints mit Quellen/URLs und falls vorhanden auch Setienangaben aus den gezeigten Ergebnissen an.
Sei absolut faktengetreu und nutze nur die sichtbaren Ergebnisse als Grundlage.`;
  }

  // English default
  return `Please summarize the search results shown above (${topics}) concisely:
- Provide key takeaways in clear bullet points.
- Highlight relevance to the user's context if applicable.
- Add 3\u20135 short bullets with sources/URLs and if available also page numbers from the shown results. Be absolutely factual-
Use only the visible results as your basis.`;
};

/**
 * Creates a unique key for a trigger (used for deduplication).
 */
export const keyOfTrigger = (t: AutoTrigger): string => {
  if (t.kind === "imagegen") {
    return `imagegen|${t.prompt}|${t.model ?? ""}|${t.n ?? ""}`;
  }
  if (t.kind === "imageedit") {
    // Include inputImages hash for uniqueness
    const imgHash = t.inputImages?.length ? t.inputImages.length.toString() : "";
    return `imageedit|${t.prompt}|${t.model ?? ""}|${imgHash}|${t.useLastImage ?? ""}`;
  }
  // For search triggers (wikipedia, papers, bildungsplan)
  const searchTrigger = t as { q: string; n?: number; collection?: string };
  return `${t.kind}|${searchTrigger.q}|${t.kind === "wikipedia" ? searchTrigger.collection ?? "" : ""}|${searchTrigger.n ?? ""}`;
};
