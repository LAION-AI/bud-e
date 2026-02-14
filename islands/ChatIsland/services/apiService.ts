/**
 * @file apiService.ts
 * @description API service functions for external data fetching (Wikipedia, Papers, Bildungsplan, ImageGen).
 *              Also contains debug logging utility for development.
 * @importantFunctions fetchWikipedia, fetchPapers, fetchBildungsplan, fetchImageGen, serverLog
 */

import {
  WikipediaResult,
  BildungsplanResponse,
  PapersResponse,
  PapersItem,
  ImageGenResult,
} from "../types.ts";

/**
 * Debug logging function that sends logs to the server.
 * Only active when DEBUG is true.
 */
export const createServerLogger = (
  debug: boolean,
  getCurrentChatSuffix: () => string
) => {
  return async (stage: string, detail?: unknown): Promise<void> => {
    if (!debug) return;
    try {
      await fetch("/api/debug", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          stage,
          chat: getCurrentChatSuffix(),
          detail,
        }),
      });
    } catch {
      // Debug should never interrupt the flow
    }
  };
};

/**
 * Fetches curriculum/education plan results from the Bildungsplan API.
 */
export const fetchBildungsplan = async (
  query: string,
  top_n: number,
  universalApiKey: string,
  serverLog?: (stage: string, detail?: unknown) => Promise<void>
): Promise<BildungsplanResponse> => {
  try {
    await serverLog?.("api.fetch.bildungsplan.req", { query, top_n });

    const response = await fetch("/api/bildungsplan", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        query,
        top_n,
        universalApiKey,
      }),
    });

    await serverLog?.("api.fetch.bildungsplan.rsp", {
      ok: response.ok,
      status: response.status,
    });

    if (!response.ok) {
      console.error(
        "bildungsplan API HTTP",
        response.status,
        await response.text().catch(() => "")
      );
      return { results: [] };
    }

    const data = (await response.json()) as BildungsplanResponse | null;

    await serverLog?.("api.fetch.bildungsplan.parsed", {
      count: data?.results?.length ?? 0,
    });

    return data ?? { results: [] };
  } catch (error) {
    console.error("Error in bildungsplan API:", error);
    await serverLog?.("api.fetch.bildungsplan.error", { error: String(error) });
    return { results: [] };
  }
};

/**
 * Fetches Wikipedia search results.
 */
export const fetchWikipedia = async (
  text: string,
  collection: string,
  n: number,
  universalApiKey: string,
  serverLog?: (stage: string, detail?: unknown) => Promise<void>
): Promise<WikipediaResult[]> => {
  try {
    await serverLog?.("api.fetch.wikipedia.req", { text, collection, n });

    const response = await fetch("/api/wikipedia", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text,
        collection,
        n,
        universalApiKey,
      }),
    });

    await serverLog?.("api.fetch.wikipedia.rsp", {
      ok: response.ok,
      status: response.status,
    });

    if (!response.ok) {
      console.error(
        "wikipedia API HTTP",
        response.status,
        await response.text().catch(() => "")
      );
      return [];
    }

    const data = (await response.json()) as WikipediaResult[] | null;

    await serverLog?.("api.fetch.wikipedia.parsed", { count: data?.length ?? 0 });

    return data ?? [];
  } catch (error) {
    console.error("Error in wikipedia API:", error);
    await serverLog?.("api.fetch.wikipedia.error", { error: String(error) });
    return [];
  }
};

/**
 * Fetches academic papers from the papers API.
 */
export const fetchPapers = async (
  query: string,
  limit: number,
  universalApiKey: string,
  serverLog?: (stage: string, detail?: unknown) => Promise<void>
): Promise<PapersResponse> => {
  try {
    await serverLog?.("api.fetch.papers.req", { query, limit });

    const response = await fetch("/api/papers", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        query,
        limit,
        universalApiKey,
      }),
    });

    await serverLog?.("api.fetch.papers.rsp", {
      ok: response.ok,
      status: response.status,
    });

    if (!response.ok) {
      console.error(
        "papers API HTTP",
        response.status,
        await response.text().catch(() => "")
      );
      return { payload: { items: [] } };
    }

    const data = (await response.json()) as PapersResponse | null;

    await serverLog?.("api.fetch.papers.parsed", {
      count: data?.payload?.items?.length ?? 0,
    });

    return data ?? { payload: { items: [] } };
  } catch (error) {
    console.error("Error in papers API:", error);
    await serverLog?.("api.fetch.papers.error", { error: String(error) });
    return { payload: { items: [] } };
  }
};

/**
 * Formats Wikipedia results into display text.
 */
export const formatWikipediaResults = (
  results: WikipediaResult[],
  lang: string,
  content: Record<string, string>
): string => {
  return results
    .map(
      (r, i) =>
        `**${content.result} ${i + 1} ${content.of} ${results.length}**\n**${content.wikipediaTitle}**: ${r.Title}\n**${content.wikipediaURL}**: ${r.URL}\n**${content.wikipediaContent}**: ${r.content}\n**${content.wikipediaScore}**: ${r.score}`
    )
    .join("\n\n");
};

/**
 * Formats Papers results into display text.
 */
export const formatPapersResults = (
  items: PapersItem[],
  lang: string,
  content: Record<string, string>
): string => {
  return items
    .map((it, i) => {
      const authors = it.authors?.join(", ") || "";
      const subjs = it.subjects?.join(", ") || "";
      const T = content.papersTitle ?? "Title";
      const A = content.papersAuthors ?? "Authors";
      const S = content.papersSubjects ?? "Subjects";
      const AB = content.papersAbstract ?? "Abstract";
      const doiLabel = "DOI";
      return `**${content.result} ${i + 1} ${content.of} ${items.length}**\n**${T}**: ${it.title}\n**${A}**: ${authors}\n**${S}**: ${subjs}\n**${doiLabel}**: ${it.doi}\n**${AB}**: ${it.abstract}`;
    })
    .join("\n\n");
};

/**
 * Formats Bildungsplan results into display text.
 */
export const formatBildungsplanResults = (
  results: { text: string; score: number }[],
  lang: string,
  content: Record<string, string>
): string => {
  return results
    .map(
      (r, i) =>
        `**${content.result} ${i + 1} ${content.of} ${results.length}**\n${r.text}\n\n**Score**: ${r.score}`
    )
    .join("\n\n");
};

/**
 * Generates images using the imagegen API.
 * Default model is "nano-banana" (Gemini Flash Image / Imagen 3).
 * Supports inputImages for image editing (Gemini models).
 */
export const fetchImageGen = async (
  prompt: string,
  universalApiKey: string,
  options?: {
    model?: string;
    n?: number;
    size?: string;
    aspectRatio?: string;
    inputImages?: string[]; // Reference images for editing
  },
  serverLog?: (stage: string, detail?: unknown) => Promise<void>
): Promise<ImageGenResult> => {
  // Default model is "nano-banana" which maps to imagen-3.0-generate-002
  const model = options?.model || "nano-banana";

  try {
    await serverLog?.("api.fetch.imagegen.req", { prompt, model, options });

    // Build request body
    // deno-lint-ignore no-explicit-any
    const requestBody: Record<string, any> = {
      prompt,
      model,
      n: options?.n || 1,
      size: options?.size || "1024x1024",
      aspectRatio: options?.aspectRatio || "1:1",
      universalApiKey,
    };

    // Add input_images for image editing if provided
    if (options?.inputImages && options.inputImages.length > 0) {
      requestBody.input_images = options.inputImages;
    }

    const response = await fetch("/api/imagegen", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(requestBody),
    });

    await serverLog?.("api.fetch.imagegen.rsp", {
      ok: response.ok,
      status: response.status,
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => "Unknown error");
      console.error("imagegen API HTTP", response.status, errorText);
      return { images: [], error: `HTTP ${response.status}: ${errorText}` };
    }

    const data = (await response.json()) as ImageGenResult | null;

    await serverLog?.("api.fetch.imagegen.parsed", {
      count: data?.images?.length ?? 0,
      model: data?.model,
    });

    return data ?? { images: [], error: "Empty response" };
  } catch (error) {
    console.error("Error in imagegen API:", error);
    await serverLog?.("api.fetch.imagegen.error", { error: String(error) });
    return { images: [], error: String(error) };
  }
};

/**
 * Formats image generation results into display content.
 * Returns an array of image data URLs that can be rendered.
 */
export const formatImageGenResults = (
  result: ImageGenResult,
  prompt: string,
  content: Record<string, string>
): { text: string; images: string[] } => {
  if (result.error) {
    const errorLabel = content.imageGenError ?? "Image generation error";
    return {
      text: `**${errorLabel}**: ${result.error}`,
      images: [],
    };
  }

  if (!result.images || result.images.length === 0) {
    const noImagesLabel = content.imageGenNoImages ?? "No images were generated";
    return {
      text: `**${noImagesLabel}**`,
      images: [],
    };
  }

  const generatedLabel = content.imageGenGenerated ?? "Generated image";
  const promptLabel = content.imageGenPrompt ?? "Prompt";
  const modelLabel = content.imageGenModel ?? "Model";

  const text = `**${generatedLabel}** (${result.images.length})\n**${promptLabel}**: ${prompt}\n**${modelLabel}**: ${result.model || "nano-banana"}`;

  return {
    text,
    images: result.images,
  };
};
