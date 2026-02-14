/**
 * @file streamService.ts
 * @description Streaming service for handling LLM chat responses via Server-Sent Events.
 *              Manages the complex streaming flow including triggers, TTS, and message updates.
 * @importantFunctions createStreamHandler, StreamContext
 */

import {
  EventSourceMessage,
  fetchEventSource,
} from "https://esm.sh/@microsoft/fetch-event-source@2.0.1";

import {
  Message,
  Settings,
  AutoTrigger,
  FatalError,
  RetriableError,
} from "../types.ts";

import { makeThinkFilter } from "../utils/textProcessing.ts";
import {
  findJsonTriggersInText,
  findHashtagTriggersInUserText,
  buildAutoSummaryPrompt,
  keyOfTrigger,
} from "../utils/triggerParsing.ts";
import {
  fetchWikipedia,
  fetchPapers,
  fetchBildungsplan,
  fetchImageGen,
  formatWikipediaResults,
  formatPapersResults,
  formatBildungsplanResults,
  formatImageGenResults,
} from "./apiService.ts";

/**
 * Finds the highest image ID number for a given prefix across all messages.
 * Handles multiple formats: gen_XXXXX, upl_XXXXX, and legacy img_XXX.
 *
 * @param messages - Array of messages to scan
 * @param prefix - The prefix to search for ("gen", "upl", or "img" for legacy)
 * @returns The highest ID number found, or 0 if none
 */
export const findHighestImageIdForPrefix = (
  messages: Message[],
  prefix: "gen" | "upl" | "img"
): number => {
  let maxId = 0;
  const pattern = new RegExp(`^${prefix}_(\\d+)$`);

  for (const msg of messages) {
    if (Array.isArray(msg.content)) {
      for (const part of msg.content) {
        if (part?.type === "image_url" && part?.id) {
          const match = String(part.id).match(pattern);
          if (match) {
            const num = parseInt(match[1], 10);
            if (num > maxId) maxId = num;
          }
        }
      }
    }
  }

  return maxId;
};

/**
 * Generates a unique generated image ID based on existing images in messages.
 * Format: gen_XXXXX where XXXXX is a zero-padded 5-digit number.
 *
 * @param messages - Array of messages to scan for existing image IDs
 * @param index - Optional index offset for batch generation
 * @returns A unique image ID string (e.g., "gen_00001", "gen_00002")
 */
export const generateImageId = (messages: Message[], index: number = 0): string => {
  // Find the highest existing ID numbers across all formats
  const genMax = findHighestImageIdForPrefix(messages, "gen");
  const uplMax = findHighestImageIdForPrefix(messages, "upl");
  const legacyMax = findHighestImageIdForPrefix(messages, "img");

  // Use the maximum across all formats to ensure no collisions
  const maxId = Math.max(genMax, uplMax, legacyMax);

  // Generate next ID with zero-padding (5 digits)
  const nextId = maxId + 1 + index;
  return `gen_${String(nextId).padStart(5, "0")}`;
};

/**
 * Finds an image URL by its unique ID in the message history.
 * Supports all ID formats: gen_XXXXX, upl_XXXXX, and legacy img_XXX.
 *
 * @param messages - Array of messages to search
 * @param imageId - The image ID to find (e.g., "gen_00001", "upl_00001", "img_001")
 * @returns The image URL if found, null otherwise
 */
export const findImageByIdInMessages = (messages: Message[], imageId: string): string | null => {
  for (const msg of messages) {
    if (Array.isArray(msg.content)) {
      for (const part of msg.content) {
        if (part?.type === "image_url" && part?.id === imageId && part?.image_url?.url) {
          return part.image_url.url;
        }
      }
    }
  }
  return null;
};

/**
 * Builds context hints for images in a message to help the LLM understand them.
 * Returns a text description of the images attached to the message.
 *
 * @param images - Array of image content parts with metadata
 * @returns A text string describing the attached images
 */
export const buildImageContextHints = (images: unknown[]): string => {
  if (!images || images.length === 0) return "";

  const hints: string[] = [];

  for (const img of images) {
    // deno-lint-ignore no-explicit-any
    const imgObj = img as any;
    if (imgObj?.type === "image_url") {
      const id = imgObj.id || "unknown";
      const source = imgObj.source || "uploaded";
      const filename = imgObj.filename || "";

      if (source === "uploaded") {
        hints.push(`[Attached image: ${id}${filename ? ` (${filename})` : ""}]`);
      } else if (source === "generated") {
        hints.push(`[Generated image: ${id}]`);
      } else {
        hints.push(`[Image: ${id}]`);
      }
    }
  }

  return hints.length > 0 ? hints.join(" ") : "";
};

/**
 * Gets all image IDs from messages for display or reference.
 *
 * @param messages - Array of messages to scan
 * @returns Array of image info objects with id, source, and timestamp
 */
export const getAllImageIds = (messages: Message[]): Array<{
  id: string;
  source: "generated" | "uploaded" | "unknown";
  timestamp?: number;
}> => {
  const images: Array<{ id: string; source: "generated" | "uploaded" | "unknown"; timestamp?: number }> = [];

  for (const msg of messages) {
    if (Array.isArray(msg.content)) {
      for (const part of msg.content) {
        if (part?.type === "image_url" && part?.id) {
          images.push({
            id: part.id,
            source: part.source || "unknown",
            timestamp: part.timestamp,
          });
        }
      }
    }
  }

  return images;
};

/**
 * Context object containing all dependencies needed for streaming.
 */
export interface StreamContext {
  lang: string;
  settings: Settings;
  currentChatSuffix: string;
  messages: Message[];
  messagesRef: { current: Message[] };
  abortRef: { current: AbortController | null };

  // State setters
  setMessages: (updater: Message[] | ((prev: Message[]) => Message[])) => void;
  setIsStreamComplete: (value: boolean) => void;
  setQuery: (value: string) => void;

  // Persistence
  safePersist: (msgs: Message[], suffix: string) => void;
  safePersistThrottled: (msgs: Message[], suffix: string) => void;
  flushPersistThrottle: () => void;

  // TTS
  getTTS: (text: string, groupIndex: number, sourceFunction: string) => void;

  // Logging
  serverLog: (stage: string, detail?: unknown) => Promise<void>;

  // Content for i18n
  chatIslandContent: Record<string, Record<string, string>>;
}

/**
 * Handles trigger execution and optional auto-summarization.
 */
export const executeTriggers = async (
  triggers: AutoTrigger[],
  ctx: StreamContext,
  seenTriggerKeys: Set<string>
): Promise<{ anyResults: boolean; accumulated: Message[]; successTrigs: AutoTrigger[] }> => {
  if (!triggers.length) {
    return { anyResults: false, accumulated: ctx.messagesRef.current, successTrigs: [] };
  }

  // Deduplicate triggers
  const fresh: AutoTrigger[] = [];
  for (const t of triggers) {
    const k = keyOfTrigger(t);
    if (!seenTriggerKeys.has(k)) {
      seenTriggerKeys.add(k);
      fresh.push(t);
    }
  }
  if (!fresh.length) {
    return { anyResults: false, accumulated: ctx.messagesRef.current, successTrigs: [] };
  }

  await ctx.serverLog("triggers.begin", { requested: triggers, deduped: fresh });

  let accumulated: Message[] = ctx.messagesRef.current;
  let anyResults = false;
  const successTrigs: AutoTrigger[] = [];
  const content = ctx.chatIslandContent[ctx.lang];
  const noResultsMsg =
    ctx.lang === "de"
      ? "Entschuldigung, die Suche hat keine Ergebnisse geliefert oder ist fehlgeschlagen."
      : "Sorry, the search returned no results or failed.";

  for (const trig of fresh) {
    if (trig.kind === "wikipedia") {
      await ctx.serverLog("wikipedia.call", {
        q: trig.q,
        n: trig.n ?? 5,
        collection: trig.collection,
      });
      const n = trig.n ?? 5;
      const collection =
        trig.collection ??
        (ctx.lang === "en" ? "English-ConcatX-Abstract" : "German-ConcatX-Abstract");
      const res = await fetchWikipedia(
        trig.q,
        collection,
        n,
        ctx.settings.universalApiKey,
        ctx.serverLog
      );
      const out = formatWikipediaResults(res, ctx.lang, content);
      await ctx.serverLog("wikipedia.result", { length: out.length, empty: !out.trim() });
      if (out.trim()) {
        anyResults = true;
        successTrigs.push(trig);
      }
      accumulated = [
        ...accumulated,
        { role: "assistant", content: out.trim() || noResultsMsg },
      ];
      ctx.setMessages(accumulated);
      ctx.safePersist(accumulated, ctx.currentChatSuffix);
    } else if (trig.kind === "papers") {
      await ctx.serverLog("papers.call", { q: trig.q, n: trig.n ?? 5 });
      const limit = trig.n ?? 5;
      const res = await fetchPapers(
        trig.q,
        limit,
        ctx.settings.universalApiKey,
        ctx.serverLog
      );
      const items = res?.payload?.items || [];
      const out = formatPapersResults(items, ctx.lang, content);
      await ctx.serverLog("papers.result", { length: out.length, empty: !out.trim() });
      if (out.trim()) {
        anyResults = true;
        successTrigs.push(trig);
      }
      accumulated = [
        ...accumulated,
        { role: "assistant", content: out.trim() || noResultsMsg },
      ];
      ctx.setMessages(accumulated);
      ctx.safePersist(accumulated, ctx.currentChatSuffix);
    } else if (trig.kind === "bildungsplan") {
      await ctx.serverLog("bildungsplan.call", { q: trig.q, n: trig.n ?? 5 });
      const top_n = trig.n ?? 5;
      const res = await fetchBildungsplan(
        trig.q,
        top_n,
        ctx.settings.universalApiKey,
        ctx.serverLog
      );
      const results = res?.results || [];
      const out = formatBildungsplanResults(results, ctx.lang, content);
      await ctx.serverLog("bildungsplan.result", {
        length: out.length,
        empty: !out.trim(),
      });
      if (out.trim()) {
        anyResults = true;
        successTrigs.push(trig);
      }
      accumulated = [
        ...accumulated,
        { role: "assistant", content: out.trim() || noResultsMsg },
      ];
      ctx.setMessages(accumulated);
      ctx.safePersist(accumulated, ctx.currentChatSuffix);
    } else if (trig.kind === "imagegen") {
      // Image generation trigger
      await ctx.serverLog("imagegen.call", {
        prompt: trig.prompt,
        model: trig.model,
        n: trig.n,
        size: trig.size,
        aspectRatio: trig.aspectRatio,
        hasInputImages: !!(trig.inputImages && trig.inputImages.length > 0),
      });

      const imageGenErrorMsg =
        ctx.lang === "de"
          ? "Entschuldigung, die Bildgenerierung ist fehlgeschlagen."
          : "Sorry, the image generation failed.";

      const res = await fetchImageGen(
        trig.prompt,
        ctx.settings.universalApiKey,
        {
          model: trig.model,
          n: trig.n,
          size: trig.size,
          aspectRatio: trig.aspectRatio,
          inputImages: trig.inputImages,
        },
        ctx.serverLog
      );

      const formatted = formatImageGenResults(res, trig.prompt, content);

      await ctx.serverLog("imagegen.result", {
        imageCount: res.images?.length ?? 0,
        hasError: !!res.error,
      });

      if (res.images && res.images.length > 0) {
        anyResults = true;
        // Note: imagegen triggers don't need auto-summarization, so we don't push to successTrigs
      }

      // Build message content with images as multimodal content (including unique IDs)
      // deno-lint-ignore no-explicit-any
      let messageContent: string | any[];
      if (formatted.images.length > 0) {
        // Include both text and images in the message with unique IDs
        // deno-lint-ignore no-explicit-any
        const contentParts: any[] = [{ type: "text", text: formatted.text }];

        // Find highest existing image ID across all formats (gen_, upl_, img_)
        const genMax = findHighestImageIdForPrefix(accumulated, "gen");
        const uplMax = findHighestImageIdForPrefix(accumulated, "upl");
        const legacyMax = findHighestImageIdForPrefix(accumulated, "img");
        const baseId = Math.max(genMax, uplMax, legacyMax);

        // Add each image with a unique ID using gen_ prefix (5 digits)
        for (let i = 0; i < formatted.images.length; i++) {
          const imgUrl = formatted.images[i];
          const imageId = `gen_${String(baseId + 1 + i).padStart(5, "0")}`;
          contentParts.push({
            type: "image_url",
            image_url: { url: imgUrl },
            id: imageId,
            source: "generated",
            timestamp: Date.now(),
          });
        }
        messageContent = contentParts;
      } else {
        messageContent = formatted.text || imageGenErrorMsg;
      }

      accumulated = [
        ...accumulated,
        { role: "assistant", content: messageContent },
      ];
      ctx.setMessages(accumulated);
      ctx.safePersist(accumulated, ctx.currentChatSuffix);
    } else if (trig.kind === "imageedit") {
      // Image editing trigger - uses input_images for reference
      await ctx.serverLog("imageedit.call", {
        prompt: trig.prompt,
        model: trig.model,
        n: trig.n,
        hasInputImages: !!(trig.inputImages && trig.inputImages.length > 0),
        useLastImage: trig.useLastImage,
        imageId: trig.imageId,
        imageIds: trig.imageIds,
      });

      const imageEditErrorMsg =
        ctx.lang === "de"
          ? "Entschuldigung, die Bildbearbeitung ist fehlgeschlagen."
          : "Sorry, the image editing failed.";

      // Resolve input images from various sources
      let inputImages = trig.inputImages || [];

      // Helper function to find image by ID in messages
      const findImageById = (messages: Message[], targetId: string): string | null => {
        for (const msg of messages) {
          if (Array.isArray(msg.content)) {
            for (const part of msg.content) {
              if (part?.type === "image_url" && part?.id === targetId && part?.image_url?.url) {
                return part.image_url.url;
              }
            }
          }
        }
        return null;
      };

      // Helper function to find last N images in messages
      const findLastImages = (messages: Message[], count: number = 1): string[] => {
        const images: string[] = [];
        for (let i = messages.length - 1; i >= 0 && images.length < count; i--) {
          const msg = messages[i];
          if (Array.isArray(msg.content)) {
            for (let j = msg.content.length - 1; j >= 0 && images.length < count; j--) {
              const part = msg.content[j];
              if (part?.type === "image_url" && part?.image_url?.url) {
                images.unshift(part.image_url.url); // Add to front to maintain order
              }
            }
          }
        }
        return images;
      };

      // Priority 1: Find images by explicit ID
      if (trig.imageId && inputImages.length === 0) {
        const foundImage = findImageById(accumulated, trig.imageId);
        if (foundImage) {
          inputImages = [foundImage];
          await ctx.serverLog("imageedit.foundById", { imageId: trig.imageId });
        }
      }

      // Priority 2: Find images by multiple IDs
      if (trig.imageIds && trig.imageIds.length > 0 && inputImages.length === 0) {
        for (const id of trig.imageIds) {
          const foundImage = findImageById(accumulated, id);
          if (foundImage) {
            inputImages.push(foundImage);
          }
        }
        await ctx.serverLog("imageedit.foundByIds", {
          requestedIds: trig.imageIds,
          foundCount: inputImages.length,
        });
      }

      // Priority 3: Use last image(s) if useLastImage is true
      if (trig.useLastImage && inputImages.length === 0) {
        inputImages = findLastImages(accumulated, 1);
        await ctx.serverLog("imageedit.usingLastImage", { found: inputImages.length > 0 });
      }

      if (inputImages.length === 0) {
        // No input images found - provide helpful error message
        const noImageMsg =
          ctx.lang === "de"
            ? `Kein Bild zum Bearbeiten gefunden.${trig.imageId ? ` Bild-ID "${trig.imageId}" existiert nicht.` : ""} Bitte laden Sie ein Bild hoch oder generieren Sie zuerst eines.`
            : `No image found to edit.${trig.imageId ? ` Image ID "${trig.imageId}" does not exist.` : ""} Please upload an image or generate one first.`;
        accumulated = [
          ...accumulated,
          { role: "assistant", content: noImageMsg },
        ];
        ctx.setMessages(accumulated);
        ctx.safePersist(accumulated, ctx.currentChatSuffix);
        continue;
      }

      // Use a model that supports image editing (Gemini)
      const editModel = trig.model || "nano-banana";

      const res = await fetchImageGen(
        trig.prompt || "Edit this image",
        ctx.settings.universalApiKey,
        {
          model: editModel,
          n: trig.n,
          inputImages: inputImages,
        },
        ctx.serverLog
      );

      const formatted = formatImageGenResults(res, trig.prompt || "Image edit", content);

      await ctx.serverLog("imageedit.result", {
        imageCount: res.images?.length ?? 0,
        hasError: !!res.error,
      });

      if (res.images && res.images.length > 0) {
        anyResults = true;
      }

      // Build message content with edited images (including unique IDs)
      // deno-lint-ignore no-explicit-any
      let messageContent: string | any[];
      if (formatted.images.length > 0) {
        // deno-lint-ignore no-explicit-any
        const contentParts: any[] = [{ type: "text", text: formatted.text }];

        // Find highest existing image ID across all formats (gen_, upl_, img_)
        const genMax = findHighestImageIdForPrefix(accumulated, "gen");
        const uplMax = findHighestImageIdForPrefix(accumulated, "upl");
        const legacyMax = findHighestImageIdForPrefix(accumulated, "img");
        const baseId = Math.max(genMax, uplMax, legacyMax);

        // Add each edited image with a unique ID using gen_ prefix (5 digits)
        for (let i = 0; i < formatted.images.length; i++) {
          const imgUrl = formatted.images[i];
          const imageId = `gen_${String(baseId + 1 + i).padStart(5, "0")}`;
          contentParts.push({
            type: "image_url",
            image_url: { url: imgUrl },
            id: imageId,
            source: "generated",
            timestamp: Date.now(),
          });
        }
        messageContent = contentParts;
      } else {
        messageContent = formatted.text || imageEditErrorMsg;
      }

      accumulated = [
        ...accumulated,
        { role: "assistant", content: messageContent },
      ];
      ctx.setMessages(accumulated);
      ctx.safePersist(accumulated, ctx.currentChatSuffix);
    }
  }

  return { anyResults, accumulated, successTrigs };
};

/**
 * Main stream handler that processes LLM responses.
 */
export const startStream = async (
  transcript: string,
  ctx: StreamContext,
  prevMessages?: Message[],
  currentEditIndex?: number,
  query?: string,
  images?: unknown[],
  pdfs?: unknown[],
  resetComposerHeight?: () => void,
  setImages?: (images: unknown[]) => void,
  setPdfs?: (pdfs: unknown[]) => void,
  setCurrentEditIndex?: (index: number) => void,
  setResetTranscript?: (updater: (n: number) => number) => void,
  audioFileDict?: Record<number, Record<number, { audio: HTMLAudioElement; played: boolean }>>,
  startStreamRecursive?: (transcript: string, accumulated: Message[]) => void
): Promise<void> => {
  // If editing a previous user message
  if (currentEditIndex !== undefined && currentEditIndex !== -1 && query !== undefined) {
    const updated = [...ctx.messages];
    updated[currentEditIndex] = { ...updated[currentEditIndex], content: query };
    ctx.setMessages(updated);
    ctx.safePersist(updated, ctx.currentChatSuffix);
    ctx.setQuery("");
    setCurrentEditIndex?.(-1);
    return;
  }

  // Stop any ongoing audio
  if (audioFileDict) {
    Object.values(audioFileDict).forEach((group) => {
      Object.values(group).forEach((item) => {
        if (!item.audio.paused) item.audio.pause();
        item.audio.currentTime = 0;
      });
    });
  }

  // Cancel previous stream
  ctx.abortRef.current?.abort();
  ctx.abortRef.current = new AbortController();

  ctx.setIsStreamComplete(false);
  setResetTranscript?.((n) => n + 1);

  // Build outbound user content
  const userText = transcript && transcript.trim() !== "" ? transcript : (query || "");
  let previousMessages = prevMessages || ctx.messages;

  // Normalize message content: join string arrays, but preserve multimodal arrays
  previousMessages = previousMessages.map((m) => {
    if (typeof m.content === "string") return m;
    if (Array.isArray(m.content)) {
      // Check if this is multimodal content (array of objects with 'type' property)
      const isMultimodal = m.content.some(
        (part) => part && typeof part === "object" && "type" in part
      );
      if (isMultimodal) {
        // Preserve multimodal content as-is
        return m;
      }
      // Legacy format: array of strings - join them
      if (typeof m.content[0] === "string") {
        return { role: m.role, content: (m.content as string[]).join("") };
      }
    }
    return m;
  });

  // Build image context hints for the LLM to understand attached images
  const imageContextHints = images && images.length > 0 ? buildImageContextHints(images) : "";

  // Combine user text with image context hints
  const fullUserText = imageContextHints
    ? `${userText}\n\n${imageContextHints}`
    : userText;

  const contentPayload: unknown[] = [{ type: "text", text: fullUserText }];
  if (images && images.length > 0) {
    for (const img of images) contentPayload.push(img);
  }
  if (pdfs && pdfs.length > 0) {
    for (const pdf of pdfs) contentPayload.push(pdf);
  }

  const newMessagesArr: Message[] = [
    ...previousMessages,
    { role: "user", content: contentPayload },
  ];

  // Clear composer state
  setImages?.([]);
  setPdfs?.([]);
  ctx.setMessages(newMessagesArr);
  ctx.safePersist(newMessagesArr, ctx.currentChatSuffix);
  ctx.setQuery("");
  resetComposerHeight?.();

  await ctx.serverLog("stream.begin", {
    userText,
    prevCount: previousMessages.length,
    images: images?.length || 0,
    pdfs: pdfs?.length || 0,
  });

  // Check for JSON triggers in user message
  const jsonUserTriggers = findJsonTriggersInText(userText, ctx.lang, ctx.serverLog);
  if (jsonUserTriggers.length) {
    await ctx.serverLog("json.user.detect", { triggers: jsonUserTriggers });
    const seenKeys = new Set<string>();
    const { anyResults, accumulated, successTrigs } = await executeTriggers(
      jsonUserTriggers,
      { ...ctx, messages: newMessagesArr, messagesRef: { current: newMessagesArr } },
      seenKeys
    );
    ctx.setIsStreamComplete(true);
    await ctx.serverLog("triggers.summary.maybe", {
      anyResults,
      successCount: successTrigs.length,
    });
    if (anyResults && successTrigs.length && startStreamRecursive) {
      const summaryPrompt = buildAutoSummaryPrompt(successTrigs, ctx.lang);
      startStreamRecursive(summaryPrompt, accumulated);
    }
    return;
  }

  // Check for hashtag triggers in user message
  const hashUserTriggers = findHashtagTriggersInUserText(userText, ctx.lang, ctx.serverLog);
  if (hashUserTriggers.length) {
    await ctx.serverLog("hashtag.user.detect", { triggers: hashUserTriggers });
    const seenKeys = new Set<string>();
    const { accumulated } = await executeTriggers(
      hashUserTriggers,
      { ...ctx, messages: newMessagesArr, messagesRef: { current: newMessagesArr } },
      seenKeys
    );
    ctx.setMessages(accumulated);
    ctx.safePersist(accumulated, ctx.currentChatSuffix);
    ctx.setIsStreamComplete(true);
    return;
  }

  // Streaming path (LLM)
  let assistantDraftIndex = -1;
  const ongoingStream: string[] = [];
  let currentAudioIndex = 1;
  let assistantAccum = "";
  let gotAnyText = false;
  const seenTriggerKeys = new Set<string>();
  let endFinalized = false;
  let interruptedForTrigger = false;
  let pendingInstreamTriggers: AutoTrigger[] = [];
  const filterThink = makeThinkFilter();

  const ensureDraft = () => {
    if (assistantDraftIndex !== -1) return;
    ctx.setMessages((prev: Message[]) => {
      assistantDraftIndex = prev.length;
      const next = [...prev, { role: "assistant", content: "" }];
      ctx.safePersist(next, ctx.currentChatSuffix);
      return next;
    });
  };

  const appendToAssistant = (txt: string) => {
    if (!txt) return;
    ctx.setMessages((prev: Message[]) => {
      if (assistantDraftIndex === -1) {
        assistantDraftIndex = prev.length;
        const next = [...prev, { role: "assistant", content: txt }];
        ctx.safePersist(next, ctx.currentChatSuffix);
        return next;
      }
      const idx = assistantDraftIndex;
      const last = prev[idx];

      // Extract text from content, handling multimodal format
      let prevText = "";
      if (typeof last.content === "string") {
        prevText = last.content;
      } else if (Array.isArray(last.content)) {
        // Check if this is multimodal content (objects with 'type' property)
        const isMultimodal = last.content.some(
          (part) => part && typeof part === "object" && "type" in part
        );
        if (isMultimodal) {
          // Extract text from multimodal parts
          prevText = last.content
            .filter((part) => part?.type === "text")
            .map((part) => part.text || "")
            .join("");
        } else {
          // Legacy format: array of strings
          prevText = last.content
            .filter((s) => typeof s === "string")
            .join("");
        }
      }

      const updated = { ...last, content: prevText + txt };
      const next = [...prev];
      next[idx] = updated;
      ctx.safePersistThrottled(next, ctx.currentChatSuffix);
      return next;
    });
  };

  const runTriggersAndMaybeSummarize = async (trigs: AutoTrigger[]) => {
    await ctx.serverLog("triggers.summary.maybe", { requested: trigs.length });
    const { anyResults, accumulated, successTrigs } = await executeTriggers(
      trigs,
      ctx,
      seenTriggerKeys
    );
    ctx.setIsStreamComplete(true);
    await ctx.serverLog("triggers.summary.result", {
      anyResults,
      successCount: successTrigs.length,
    });
    if (anyResults && successTrigs.length && startStreamRecursive) {
      const summaryPrompt = buildAutoSummaryPrompt(successTrigs, ctx.lang);
      startStreamRecursive(summaryPrompt, accumulated);
    }
  };

  const finalizeStream = async () => {
    if (endFinalized) return;
    endFinalized = true;

    ctx.setIsStreamComplete(true);
    ctx.setQuery("");

    const flushed = filterThink.flush();
    if (flushed) {
      appendToAssistant(flushed);
      ongoingStream.push(flushed);
      assistantAccum += flushed;
    }

    ctx.flushPersistThrottle();

    if (!gotAnyText) {
      ctx.setMessages((prev: Message[]) => {
        if (!prev.length) return prev;
        const idx = assistantDraftIndex === -1 ? prev.length - 1 : assistantDraftIndex;
        const last = prev[idx];
        const txt =
          typeof last?.content === "string"
            ? last.content
            : Array.isArray(last?.content)
              ? (last.content as string[]).join("")
              : "";
        if (last?.role === "assistant" && (!txt || txt.trim() === "")) {
          const next = [...prev];
          next.splice(idx, 1);
          ctx.safePersist(next, ctx.currentChatSuffix);
          return next;
        }
        return prev;
      });
    } else {
      const remaining = ongoingStream.join("").trim();
      if (remaining) {
        const groupIndex =
          assistantDraftIndex === -1
            ? ctx.messagesRef.current.length - 1
            : assistantDraftIndex;
        ctx.getTTS(remaining, groupIndex, `stream${currentAudioIndex}`);
      }
    }

    // After stream ends, check for triggers and maybe summarize
    const finalTriggers = findJsonTriggersInText(assistantAccum, ctx.lang, ctx.serverLog);
    await ctx.serverLog("stream.finalize", {
      gotAnyText,
      assistantAccumLen: assistantAccum.length,
      triggersFound: finalTriggers.length,
    });
    if (finalTriggers.length) {
      await ctx.serverLog("json.poststream.detect", { triggers: finalTriggers });
      await runTriggersAndMaybeSummarize(finalTriggers);
    }

    ctx.abortRef.current = null;
  };

  await ctx.serverLog("sse.request", {
    url: "/api/chat",
    model: ctx.settings.apiModel,
    apiUrl: ctx.settings.apiUrl,
    images: images?.length || 0,
    pdfs: pdfs?.length || 0,
  });

  await fetchEventSource("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      lang: ctx.lang,
      messages: newMessagesArr,
      universalApiKey: ctx.settings.universalApiKey,
      llmApiUrl: ctx.settings.apiUrl,
      llmApiKey: ctx.settings.apiKey,
      llmApiModel: ctx.settings.apiModel,
      vlmApiUrl: ctx.settings.vlmUrl,
      vlmApiKey: ctx.settings.vlmKey,
      vlmApiModel: ctx.settings.vlmModel,
      vlmCorrectionModel: ctx.settings.vlmCorrectionModel,
      systemPrompt: ctx.settings.systemPrompt,
    }),
    signal: ctx.abortRef.current?.signal,

    async onopen(response: Response) {
      await ctx.serverLog("sse.open", { ok: response.ok, status: response.status });
      if (response.ok) return;
      if (response.status !== 200) {
        const errorText = await response.text().catch(() => "");
        ensureDraft();
        appendToAssistant(
          `\n\n**BACKEND ERROR**\nStatuscode: ${response.status}\nMessage: ${errorText || response.statusText}`
        );
        throw new FatalError(errorText || response.statusText);
      }
      throw new RetriableError();
    },

    onmessage(ev: EventSourceMessage) {
      let rawChunk = "";
      try {
        if (ev.event === "error") {
          const err = (() => {
            try {
              return JSON.parse(ev.data);
            } catch {
              return { message: ev.data };
            }
          })();
          ensureDraft();
          appendToAssistant(
            `\n\n**BACKEND ERROR**\nStatuscode: ${err?.status ?? ""}\nMessage: ${err?.message ?? ""}`
          );
          return;
        }
        if (ev.event === "no_content") {
          return;
        }

        try {
          rawChunk = JSON.parse(ev.data) as string;
        } catch (parseErr) {
          console.error("SSE JSON parse error:", parseErr, "data:", ev.data);
          return;
        }
        if (!rawChunk) {
          console.log("SSE rawChunk is falsy:", rawChunk, "from data:", ev.data);
          return;
        }

        ctx.serverLog("sse.chunk", { len: rawChunk.length });
      } catch (err) {
        console.error("SSE onmessage error:", err);
        return;
      }

      // Early end marker
      if (rawChunk === "[DONE]") {
        setTimeout(() => ctx.abortRef.current?.abort(), 0);
        finalizeStream();
        return;
      }

      // THINK filter
      const chunk = filterThink.consume(rawChunk);
      if (!chunk) return;

      gotAnyText = true;
      ensureDraft();

      assistantAccum += chunk;

      // TTS buffer
      ongoingStream.push(chunk);
      const combined = ongoingStream.join("");
      const re = /(?<!\d)[.!?]/g;
      let lastIdx = -1;
      let m: RegExpExecArray | null;
      while ((m = re.exec(combined)) !== null) lastIdx = m.index;
      if (lastIdx !== -1) {
        const split = lastIdx + 1;
        const toSpeak = combined.slice(0, split).trim();
        const remaining = combined.slice(split);
        if (toSpeak) {
          const groupIndex =
            assistantDraftIndex === -1 ? newMessagesArr.length : assistantDraftIndex;
          ctx.getTTS(toSpeak, groupIndex, `stream${currentAudioIndex}`);
          currentAudioIndex++;
        }
        ongoingStream.length = 0;
        if (remaining.trim()) ongoingStream.push(remaining);
      }

      // Append to chat
      appendToAssistant(chunk);

      // Check for in-stream JSON triggers
      if (chunk.includes("}")) {
        const maybeTriggers = findJsonTriggersInText(assistantAccum, ctx.lang);
        const fresh: AutoTrigger[] = [];
        for (const t of maybeTriggers) {
          const k = keyOfTrigger(t);
          if (!seenTriggerKeys.has(k)) fresh.push(t);
        }
        if (fresh.length) {
          ctx.serverLog("json.instream.detect", {
            braceSeen: true,
            accLen: assistantAccum.length,
            triggers: fresh,
          });
          interruptedForTrigger = true;
          pendingInstreamTriggers = fresh;
          setTimeout(() => ctx.abortRef.current?.abort(), 0);
          return;
        }
      }
    },

    async onerror(err: Error) {
      await ctx.serverLog("sse.error", { message: String(err?.message || err) });
      ctx.setIsStreamComplete(true);
      ensureDraft();
      appendToAssistant(`\n\n${String(err?.message || err)}`);
      throw err;
    },

    onclose() {
      ctx.serverLog("sse.close", { interruptedForTrigger });
      if (interruptedForTrigger) {
        runTriggersAndMaybeSummarize(pendingInstreamTriggers);
        ctx.abortRef.current = null;
        return;
      }
      finalizeStream();
    },
  });
};
