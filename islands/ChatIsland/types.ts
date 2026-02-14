/**
 * @file types.ts
 * @description Type definitions and interfaces for the ChatIsland component.
 *              Centralizes all shared types used across the chat system.
 * @importantFunctions Message, AudioItem, AudioFileDict, AutoTrigger, Settings
 */

// Custom error classes for stream handling
export class RetriableError extends Error {}
export class FatalError extends Error {}

// Core message type used throughout the chat
export interface Message {
  role: string;
  // deno-lint-ignore no-explicit-any
  content: string | any[];
}

// API result types for external services
export interface WikipediaResult {
  Title: string;
  URL: string;
  content: string;
  score: number;
}

export interface BildungsplanHit {
  text: string;
  score: number;
}

export interface BildungsplanResponse {
  results: BildungsplanHit[];
}

export interface PapersItem {
  title: string;
  authors?: string[];
  subjects?: string[];
  abstract?: string;
  doi?: string;
}

export interface PapersResponse {
  payload?: { items?: PapersItem[] };
}

// Audio playback types
export interface AudioItem {
  audio: HTMLAudioElement & { __text?: string; __session?: number };
  played: boolean;
}

export type AudioFileDict = Record<number, Record<number, AudioItem>>;

// Trigger types for auto-search and image generation functionality
export type AutoTrigger =
  | { kind: "wikipedia"; q: string; n?: number; collection?: string; autoSummarize?: boolean }
  | { kind: "papers"; q: string; n?: number; autoSummarize?: boolean }
  | { kind: "bildungsplan"; q: string; n?: number; autoSummarize?: boolean }
  | { kind: "imagegen"; prompt: string; model?: string; n?: number; size?: string; aspectRatio?: string; inputImages?: string[] }
  | {
      kind: "imageedit";
      prompt: string;
      model?: string;
      n?: number; // Number of output images
      inputImages?: string[]; // Explicit base64 image data
      useLastImage?: boolean; // Use the last image in conversation
      imageId?: string; // Reference specific image by unique ID
      imageIds?: string[]; // Reference multiple images by ID
    };

/**
 * Image content part with unique identifier.
 * Used in multimodal message content arrays.
 */
export interface ImageContentPart {
  type: "image_url";
  image_url: {
    url: string; // data:image/... or https://...
    detail?: "auto" | "low" | "high";
  };
  id?: string; // Unique image identifier (e.g., "img_001")
  source?: "generated" | "uploaded"; // How the image was added
  timestamp?: number; // When the image was created/uploaded
}

// Image generation result type
export interface ImageGenResult {
  images: string[];
  model?: string;
  error?: string;
}

// Settings configuration type
export interface Settings {
  universalApiKey: string;
  apiUrl: string;
  apiKey: string;
  apiModel: string;
  ttsUrl: string;
  ttsKey: string;
  ttsModel: string;
  sttUrl: string;
  sttKey: string;
  sttModel: string;
  systemPrompt: string;
  vlmUrl: string;
  vlmKey: string;
  vlmModel: string;
  vlmCorrectionModel: string;
}

// Think filter state for streaming
export type ThinkState = { inThink: boolean; carry: string };

// PDF file type (re-exported for convenience)
export interface PdfFile {
  type: string;
  name: string;
  data: string;
}
