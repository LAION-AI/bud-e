import { Handlers } from "$fresh/server.ts";

const STT_KEY = Deno.env.get("STT_KEY") || "";
const STT_MODEL = Deno.env.get("STT_MODEL") || "";
const STT_URL = Deno.env.get("STT_URL") || "";
const MIDDLEWARE_BASE_URL = Deno.env.get("MIDDLEWARE_URL") || "";

/* ===================== Universal-key suffix decoding =======================
   Backend encodes "<host>:<port>" as:
     token = "v1" + Base32( bytes(host:port) XOR 0x5A ), without '=' padding
   We decode it, then build "http://<host>:<port>" (IPv6 hosts get brackets).
============================================================================= */

/** RFC4648 Base32 decode (no padding required). Throws on bad chars. */
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

/** Convert "host:port" → "http://host:port" with IPv6 bracket handling */
function hostPortToHttpBase(hostPort: string): string {
  // Split at last ":" to separate port; IPv6 contains multiple ":"s.
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

/** Decode middleware base URL from the composite universal key (or return null). */
function decodeMiddlewareBaseFromUniversalKey(universalApiKey: string | undefined | null): string | null {
  const raw = (universalApiKey || "").trim();
  const hash = raw.indexOf("#");
  if (hash < 0) return null;
  const suffix = raw.slice(hash + 1);

  // Backward compatibility: accept raw http(s) suffixes if they ever existed.
  if (/^https?:\/\/.+/i.test(suffix)) {
    return suffix.replace(/\/+$/g, "");
  }

  // Expected scheme: 'v1' + Base32(no padding) of XOR'd bytes
  if (!suffix.startsWith("v1")) return null;
  try {
    const b32 = suffix.slice(2);
    const bytes = base32DecodeNoPadding(b32);
    // XOR with 0x5A to recover original "host:port" ascii
    for (let i = 0; i < bytes.length; i++) bytes[i] = bytes[i] ^ 0x5a;
    const hostPort = new TextDecoder().decode(bytes);
    if (!hostPort || hostPort.indexOf(":") === -1) return null;
    return hostPortToHttpBase(hostPort).replace(/\/+$/g, "");
  } catch {
    return null;
  }
}

export const handler: Handlers = {
  async POST(req) {
    try {
      const formData = await req.formData();
      const audioFile = formData.get("audio") as File;

      const universalApiKey = (formData.get("universalApiKey") as string) || "";

      // Initialize variables with values from settings or environment variables
      let useThisSttUrl = (formData.get("sttUrl") as string) || STT_URL;
      let useThisSttKey = (formData.get("sttKey") as string) || STT_KEY;
      let useThisSttModel = (formData.get("sttModel") as string) || STT_MODEL;

      // If a universalApiKey is provided, it overrides the specific STT settings
      if (universalApiKey) {
        const base =
          decodeMiddlewareBaseFromUniversalKey(universalApiKey) ||
          (MIDDLEWARE_BASE_URL || "").trim();
        if (base) {
          useThisSttUrl = `${base.replace(/\/+$/,"")}/v1/audio/transcriptions`;
          useThisSttKey = universalApiKey;
          // When using middleware, "whisper-1" is a safe default if unset
          if (!useThisSttModel) useThisSttModel = "whisper-1";
        }
      }

      // This is for direct-to-Groq calls and remains compatible
      if (useThisSttKey.startsWith("gsk_")) {
        useThisSttUrl = useThisSttUrl == ""
          ? "https://api.groq.com/openai/v1/audio/transcriptions"
          : useThisSttUrl;
        useThisSttModel = useThisSttModel == "" ? "whisper-large-v3-turbo" : useThisSttModel;
      }

      if (!audioFile) {
        return new Response("No audio file uploaded", { status: 400 });
      }

      if (!useThisSttKey) {
        return new Response("Missing STT API key. Please configure STT settings or Universal API Key.", { status: 400 });
      }

      if (!useThisSttUrl) {
        return new Response("Missing STT URL. Please configure STT settings.", { status: 400 });
      }

      console.log("[STT] Request:", {
        url: useThisSttUrl,
        model: useThisSttModel,
        keyPrefix: useThisSttKey?.slice(0, 10) + "...",
        fileSize: audioFile.size,
        fileType: audioFile.type,
      });

      const sttFormData = new FormData();
      sttFormData.append("file", audioFile);
      sttFormData.append("model", useThisSttModel);

      // Make the fetch request using the potentially overridden URL and key
      const response = await fetch(useThisSttUrl, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${useThisSttKey}`,
        },
        body: sttFormData,
      });

      if (!response.ok) {
        const errorBody = await response.text();
        console.error("STT API Error:", errorBody);
        console.error("STT API URL used:", useThisSttUrl);
        console.error("STT Model used:", useThisSttModel);
        console.error("STT Key prefix:", useThisSttKey?.slice(0, 10) + "...");
        // Return the actual error from the upstream API instead of generic message
        return new Response(errorBody || `STT API responded with status: ${response.status}`, {
          status: response.status,
          headers: { "Content-Type": "text/plain" }
        });
      }

      const transcription = await response.json();

      return new Response(transcription.text, {
        status: 200,
        headers: { "Content-Type": "text/plain" },
      });
    } catch (error) {
      console.error("Error transcribing audio file:", error);
      return new Response("Internal Server Error", { status: 500 });
    }
  },
};
