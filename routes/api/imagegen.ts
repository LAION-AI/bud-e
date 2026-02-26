/**
 * @file imagegen.ts
 * @description API route for image generation using middleware, Google's Gemini API or OpenAI-compatible APIs.
 *              Supports multiple models including Gemini Flash Image (nano-banana).
 * @importantFunctions POST handler for /api/imagegen
 */

import { Handlers } from "$fresh/server.ts";

const MIDDLEWARE_BASE_URL = Deno.env.get("MIDDLEWARE_URL") || "";

// Default image generation model (FLUX.2 Klein - fast, sub-second generation)
const DEFAULT_MODEL = "flux-2-klein-9b";

/**
 * Model aliases for user convenience
 *
 * Available image generation models:
 * - gemini-2.5-flash-image: Fast, good quality (default)
 * - gemini-3-pro-image-preview: Best quality, supports text+images input/output
 * - imagen-3.0-generate-002: Google Imagen 3 (text-to-image only)
 *
 * Black Forest Labs FLUX.2 models:
 * - flux-2-klein-4b: Fastest, sub-second generation (~$0.014/image)
 * - flux-2-klein-9b: Better prompt understanding (~$0.014/image)
 * - flux-2-pro: Production-grade, balanced (~$0.03-0.05/image)
 * - flux-2-max: Maximum quality, complex instructions (~$0.07/image)
 *
 * Gemini 3 Pro Image specs (from Google docs):
 * - Max input tokens: 65,536 | Max output tokens: 32,768
 * - Max images per prompt: 14
 * - Supported aspect ratios: 1:1, 3:2, 2:3, 3:4, 4:3, 4:5, 5:4, 9:16, 16:9, 21:9
 */
const MODEL_ALIASES: Record<string, string> = {
  // Primary aliases (most used)
  "nano-banana": "gemini-2.5-flash-image",
  "nano-banana-pro": "gemini-3-pro-image-preview", // Gemini 3 Pro Image - best quality

  // Gemini aliases
  "gemini-flash-image": "gemini-2.5-flash-image",
  "gemini-pro-image": "gemini-3-pro-image-preview", // Gemini 3 Pro Image - best quality
  "gemini-2.5-flash": "gemini-2.5-flash-image",

  // Imagen aliases
  "imagen": "imagen-3.0-generate-002",
  "imagen-3": "imagen-3.0-generate-002",
  "imagen-4": "imagen-4.0-generate-001",

  // Black Forest Labs FLUX.2 aliases
  "flux-2": "flux-2-pro",
  "flux-2-klein": "flux-2-klein-9b",
  "flux-klein": "flux-2-klein-9b",
  "flux-pro": "flux-2-pro",
  "flux-max": "flux-2-max",
  "flux": "flux-2-pro",  // Default to pro variant

  // OpenAI aliases (for compatibility)
  "dall-e-3": "dall-e-3",
  "dall-e-2": "dall-e-2",
};

/**
 * RFC4648 Base32 decode (no padding required).
 */
function base32DecodeNoPadding(s: string): Uint8Array {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const clean = s.trim().toUpperCase().replace(/=+$/g, "");
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (let i = 0; i < clean.length; i++) {
    const ch = clean[i];
    const idx = alphabet.indexOf(ch);
    if (idx === -1) throw new Error("Invalid Base32 character");
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((value >>> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

/**
 * Convert "host:port" → "http://host:port" with IPv6 bracket handling
 */
function hostPortToHttpBase(hostPort: string): string {
  const last = hostPort.lastIndexOf(":");
  let host = hostPort;
  let port = "";
  if (last !== -1) {
    host = hostPort.slice(0, last);
    port = hostPort.slice(last + 1);
  }
  const isIPv6 = host.includes(":");
  const bracketHost = isIPv6 ? `[${host}]` : host;
  const portPart = port ? `:${port}` : "";
  return `http://${bracketHost}${portPart}`;
}

/**
 * Decode middleware base URL from the composite universal key.
 */
function decodeMiddlewareBaseFromUniversalKey(universalApiKey: string | undefined | null): string | null {
  const raw = (universalApiKey || "").trim();
  const hash = raw.indexOf("#");
  if (hash < 0) return null;
  const suffix = raw.slice(hash + 1);

  if (/^https?:\/\/.+/i.test(suffix)) {
    return suffix.replace(/\/+$/g, "");
  }

  if (!suffix.startsWith("v1")) return null;
  try {
    const b32 = suffix.slice(2);
    const bytes = base32DecodeNoPadding(b32);
    for (let i = 0; i < bytes.length; i++) bytes[i] = bytes[i] ^ 0x5a;
    const hostPort = new TextDecoder().decode(bytes);
    if (!hostPort || hostPort.indexOf(":") === -1) return null;
    return hostPortToHttpBase(hostPort).replace(/\/+$/g, "");
  } catch {
    return null;
  }
}

/**
 * Extract the actual API key from the universal key format.
 * Universal key format: <api_key>#<encoded_middleware_url>
 * Returns the API key part (before the #)
 */
function extractApiKeyFromUniversal(universalApiKey: string): string {
  const raw = (universalApiKey || "").trim();
  const hash = raw.indexOf("#");
  if (hash > 0) {
    return raw.slice(0, hash).trim();
  }
  return raw;
}

/**
 * Resolve model alias to actual model name
 */
function resolveModel(model: string): string {
  const lower = model.toLowerCase().trim();
  return MODEL_ALIASES[lower] || model;
}

/**
 * Check if a model is a Gemini model that uses generateContent API
 */
function isGeminiModel(model: string): boolean {
  const resolved = resolveModel(model).toLowerCase();
  return resolved.startsWith("gemini-");
}

/**
 * Check if a model is an Imagen model that uses predict API
 */
function isImagenModel(model: string): boolean {
  const resolved = resolveModel(model).toLowerCase();
  return resolved.startsWith("imagen-");
}

/**
 * Generate image using middleware (OpenAI-compatible format)
 * Uses a timeout to avoid long waits if middleware is unavailable
 * Supports input_images for image editing (Gemini models)
 */
async function generateWithMiddleware(
  prompt: string,
  model: string,
  middlewareUrl: string,
  apiKey: string,
  options: { n?: number; size?: string; aspectRatio?: string; inputImages?: string[] },
  timeoutMs: number = 120000
): Promise<{ images: string[]; model?: string; error?: string }> {
  const actualModel = resolveModel(model);
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  // Build request body
  // deno-lint-ignore no-explicit-any
  const requestBody: Record<string, any> = {
    model: actualModel,
    prompt,
    n: options.n || 1,
    size: options.size || "1024x1024",
    response_format: "b64_json",
  };

  // Add aspect_ratio if provided (used by FLUX.2 and other providers)
  if (options.aspectRatio) {
    requestBody.aspect_ratio = options.aspectRatio;
  }

  // Add input_images for image editing if provided
  if (options.inputImages && options.inputImages.length > 0) {
    requestBody.input_images = options.inputImages;
  }

  try {
    const response = await fetch(middlewareUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify(requestBody),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Middleware API error:", errorText);
      return { images: [], error: `Middleware error: ${response.status} - ${errorText}` };
    }

    const data = await response.json();

    // Extract images from OpenAI-format response
    const images: string[] = [];
    if (data.data) {
      for (const item of data.data) {
        if (item.b64_json) {
          images.push(`data:image/png;base64,${item.b64_json}`);
        } else if (item.url) {
          images.push(item.url);
        }
      }
    }

    return { images, model: actualModel };
  } catch (error) {
    clearTimeout(timeoutId);
    if (error instanceof Error && error.name === "AbortError") {
      console.error("Middleware request timed out");
      return { images: [], error: "Middleware request timed out" };
    }
    console.error("Middleware API request failed:", error);
    return { images: [], error: String(error) };
  }
}

/**
 * Generate image using Google's Gemini API (generateContent with image output)
 */
async function generateWithGemini(
  prompt: string,
  model: string,
  apiKey: string,
  _options: { n?: number; aspectRatio?: string }
): Promise<{ images: string[]; model?: string; error?: string }> {
  const actualModel = resolveModel(model);

  // Gemini generateContent endpoint with image generation
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${actualModel}:generateContent?key=${apiKey}`;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [{
          parts: [{
            text: prompt
          }]
        }],
        generationConfig: {
          responseModalities: ["TEXT", "IMAGE"]
        }
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Gemini API error:", errorText);
      return { images: [], error: `Gemini API error: ${response.status} - ${errorText}` };
    }

    const data = await response.json();

    // Extract images from Gemini response
    const images: string[] = [];
    if (data.candidates) {
      for (const candidate of data.candidates) {
        if (candidate.content?.parts) {
          for (const part of candidate.content.parts) {
            if (part.inlineData?.mimeType?.startsWith("image/")) {
              const mimeType = part.inlineData.mimeType;
              const base64Data = part.inlineData.data;
              images.push(`data:${mimeType};base64,${base64Data}`);
            }
          }
        }
      }
    }

    return { images, model: actualModel };
  } catch (error) {
    console.error("Gemini API request failed:", error);
    return { images: [], error: String(error) };
  }
}

/**
 * Generate image using Google's Imagen API (predict endpoint)
 */
async function generateWithImagen(
  prompt: string,
  model: string,
  apiKey: string,
  options: { n?: number; aspectRatio?: string }
): Promise<{ images: string[]; model?: string; error?: string }> {
  const actualModel = resolveModel(model);

  // Imagen predict endpoint
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${actualModel}:predict?key=${apiKey}`;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        instances: [{ prompt }],
        parameters: {
          sampleCount: options.n || 1,
          aspectRatio: options.aspectRatio || "1:1",
        },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Imagen API error:", errorText);
      return { images: [], error: `Imagen API error: ${response.status} - ${errorText}` };
    }

    const data = await response.json();

    // Extract base64 images from response
    const images: string[] = [];
    if (data.predictions) {
      for (const pred of data.predictions) {
        if (pred.bytesBase64Encoded) {
          images.push(`data:image/png;base64,${pred.bytesBase64Encoded}`);
        }
      }
    }

    return { images, model: actualModel };
  } catch (error) {
    console.error("Imagen API request failed:", error);
    return { images: [], error: String(error) };
  }
}

/**
 * Generate image using OpenAI-compatible API
 */
async function generateWithOpenAICompatible(
  prompt: string,
  model: string,
  apiUrl: string,
  apiKey: string,
  options: { n?: number; size?: string }
): Promise<{ images: string[]; model?: string; error?: string }> {
  const actualModel = resolveModel(model);

  try {
    const response = await fetch(apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: actualModel,
        prompt,
        n: options.n || 1,
        size: options.size || "1024x1024",
        response_format: "b64_json",
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("OpenAI-compatible API error:", errorText);
      return { images: [], error: `API error: ${response.status} - ${errorText}` };
    }

    const data = await response.json();

    // Extract images from OpenAI-format response
    const images: string[] = [];
    if (data.data) {
      for (const item of data.data) {
        if (item.b64_json) {
          images.push(`data:image/png;base64,${item.b64_json}`);
        } else if (item.url) {
          images.push(item.url);
        }
      }
    }

    return { images, model: actualModel };
  } catch (error) {
    console.error("OpenAI-compatible API request failed:", error);
    return { images: [], error: String(error) };
  }
}

export const handler: Handlers = {
  async POST(req) {
    try {
      const body = await req.json();
      const {
        prompt,
        model = DEFAULT_MODEL,
        n = 1,
        size = "1024x1024",
        aspectRatio = "1:1",
        universalApiKey = "",
        imagegenApiKey = "",
        imagegenApiUrl = "",
        input_images = [], // Reference images for editing
      } = body;

      // Normalize input_images to array of strings (data URLs)
      const inputImages: string[] = Array.isArray(input_images)
        ? input_images.filter((img: unknown) => typeof img === "string" && img.length > 0)
        : [];

      if (!prompt || typeof prompt !== "string" || prompt.trim() === "") {
        return new Response(
          JSON.stringify({ error: "Missing or empty prompt" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      let result: { images: string[]; model?: string; error?: string };
      const resolvedModel = resolveModel(model);

      // Priority 1: Universal API key - try middleware first, then direct Google API
      if (universalApiKey) {
        const middlewareBase = decodeMiddlewareBaseFromUniversalKey(universalApiKey) ||
          (MIDDLEWARE_BASE_URL || "").trim();

        // Try middleware first if available
        if (middlewareBase) {
          const middlewareUrl = `${middlewareBase.replace(/\/+$/, "")}/v1/images/generations`;
          console.log("Trying middleware for image generation:", middlewareUrl);

          result = await generateWithMiddleware(
            prompt,
            model,
            middlewareUrl,
            universalApiKey,
            { n, size, aspectRatio, inputImages },
            120000 // 120 second timeout for middleware (image gen can be slow)
          );

          if (result.images.length > 0) {
            return new Response(
              JSON.stringify({ images: result.images, model: result.model || resolvedModel }),
              { status: 200, headers: { "Content-Type": "application/json" } }
            );
          }

          console.log("Middleware failed, falling back to direct API. Error:", result.error);
        }

        // Fallback: Direct Google API using the actual API key (before #)
        const actualApiKey = extractApiKeyFromUniversal(universalApiKey);

        if (actualApiKey) {
          // Use Gemini API for gemini-* models (including nano-banana aliases)
          if (isGeminiModel(model)) {
            console.log("Using Gemini API for model:", resolvedModel);
            result = await generateWithGemini(prompt, model, actualApiKey, { n, aspectRatio });
            if (result.images.length > 0) {
              return new Response(
                JSON.stringify({ images: result.images, model: result.model || resolvedModel }),
                { status: 200, headers: { "Content-Type": "application/json" } }
              );
            }
          }
          // Use Imagen API for imagen-* models
          else if (isImagenModel(model)) {
            console.log("Using Imagen API for model:", resolvedModel);
            result = await generateWithImagen(prompt, model, actualApiKey, { n, aspectRatio });
            if (result.images.length > 0) {
              return new Response(
                JSON.stringify({ images: result.images, model: result.model || resolvedModel }),
                { status: 200, headers: { "Content-Type": "application/json" } }
              );
            }
          }
          // Default: try Gemini with default model
          else {
            console.log("Using Gemini API with default model:", DEFAULT_MODEL);
            result = await generateWithGemini(prompt, DEFAULT_MODEL, actualApiKey, { n, aspectRatio });
            if (result.images.length > 0) {
              return new Response(
                JSON.stringify({ images: result.images, model: result.model || DEFAULT_MODEL }),
                { status: 200, headers: { "Content-Type": "application/json" } }
              );
            }
          }

          // Return error if we got one
          if (result && result.error) {
            return new Response(
              JSON.stringify({ error: result.error }),
              { status: 500, headers: { "Content-Type": "application/json" } }
            );
          }
        }
      }

      // Priority 2: Direct API key for image generation
      if (imagegenApiKey) {
        // Google AI key (starts with AI)
        if (imagegenApiKey.startsWith("AI")) {
          if (isGeminiModel(model)) {
            result = await generateWithGemini(prompt, model, imagegenApiKey, { n, aspectRatio });
          } else if (isImagenModel(model)) {
            result = await generateWithImagen(prompt, model, imagegenApiKey, { n, aspectRatio });
          } else {
            result = await generateWithGemini(prompt, DEFAULT_MODEL, imagegenApiKey, { n, aspectRatio });
          }
        }
        // OpenAI key
        else if (imagegenApiKey.startsWith("sk-")) {
          const url = imagegenApiUrl || "https://api.openai.com/v1/images/generations";
          result = await generateWithOpenAICompatible(prompt, model, url, imagegenApiKey, { n, size });
        }
        // Custom API
        else if (imagegenApiUrl) {
          result = await generateWithOpenAICompatible(prompt, model, imagegenApiUrl, imagegenApiKey, { n, size });
        }
        else {
          return new Response(
            JSON.stringify({ error: "Unable to determine image generation service" }),
            { status: 400, headers: { "Content-Type": "application/json" } }
          );
        }

        if (result.images.length > 0) {
          return new Response(
            JSON.stringify({ images: result.images, model: result.model || resolvedModel }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          );
        }

        return new Response(
          JSON.stringify({ error: result.error || "Failed to generate image" }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ error: "No API key provided for image generation" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );

    } catch (error) {
      console.error("Image generation error:", error);
      return new Response(
        JSON.stringify({ error: "Internal Server Error" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  },
};
