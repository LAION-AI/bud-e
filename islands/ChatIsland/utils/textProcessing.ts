/**
 * @file textProcessing.ts
 * @description Text processing utilities for TTS, chunking, and stream filtering.
 *              Contains pure functions for text manipulation without side effects.
 * @importantFunctions splitIntoSmartChunks, cleanForTTS, makeThinkFilter, normalizeForTrigger
 */

import { ThinkState } from "../types.ts";

/**
 * Counts words in a string (splits by whitespace)
 */
export const countWords = (s: string): number =>
  (s.trim().match(/[^\s]+/g) ?? []).length;

/**
 * Checks if a dot at a given index is a valid sentence-ending period.
 * Returns false for dots after single letters (A. B.) or numbers (1. 2.)
 */
export const isValidDot = (text: string, dotIdx: number): boolean => {
  const left = text.slice(0, dotIdx).trimEnd();
  const m = left.match(/([\p{L}\p{N}]+)\s*$/u);
  if (!m) return false;
  const token = m[1];
  // Single letter enumerations like A. B. C.
  if (/^[A-Za-zÄÖÜäöüß]$/.test(token)) return false;
  // Numbered lists like 1. 2. 3)
  if (/^\d+([.)])?$/.test(token)) return false;
  // Needs at least 2 letters to be a valid word ending
  return /[\p{L}]{2,}/u.test(token);
};

/**
 * Finds the end index of a chunk with at least minWords words,
 * ending at a sentence boundary if possible.
 */
export const findChunkEnd = (text: string, start: number, minWords: number): number => {
  const tail = text.slice(start);
  if (countWords(tail) <= minWords) return text.length;

  let i = start;
  while (i < text.length) {
    const ch = text[i];
    const wordsSoFar = countWords(text.slice(start, i + 1));
    if (wordsSoFar >= minWords) {
      // Check for ellipsis
      if (i + 2 < text.length && text.slice(i, i + 3) === "...") return i + 3;
      // Check for ! or ?
      if (/[!?]/.test(ch)) return i + 1;
      // Check for valid sentence-ending period
      if (ch === "." && isValidDot(text, i)) return i + 1;
    }
    i++;
  }

  // Fallback: first whitespace after minWords
  i = start;
  while (i < text.length && countWords(text.slice(start, i)) < minWords) i++;
  while (i < text.length && !/\s/.test(text[i])) i++;
  return Math.min(text.length, Math.max(i, start + 1));
};

/**
 * Splits text into smart chunks for TTS with progressive sizing.
 * First chunk: ~10 words, second: ~20 words, third: ~40 words, rest: remainder
 */
export const splitIntoSmartChunks = (text: string): string[] => {
  const t = text.trim();
  if (!t) return [];

  const end1 = findChunkEnd(t, 0, 10);
  const end2 = findChunkEnd(t, end1, 20);
  const end3 = findChunkEnd(t, end2, 40);

  const seg1 = t.slice(0, end1).trim();
  const seg2 = t.slice(end1, end2).trim();
  const seg3 = t.slice(end2, end3).trim();
  const seg4 = t.slice(end3).trim();

  const parts: string[] = [];
  if (seg1) parts.push(seg1);
  if (seg2) parts.push(seg2);
  if (seg3) parts.push(seg3);
  if (seg4) parts.push(seg4);
  return parts;
};

/**
 * Cleans text for TTS by removing markdown asterisks and emojis
 */
export const cleanForTTS = (s: string): string =>
  s
    .replace(/\*/g, "")
    .replace(
      /[\u{1F1E6}-\u{1F1FF}\u{1F300}-\u{1F5FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1F700}-\u{1F77F}\u{1F780}-\u{1F7FF}\u{1F800}-\u{1F8FF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FAFF}\u2600-\u26FF\u2700-\u27BF\uFE0F\u200D]/gu,
      ""
    )
    .replace(/\s{2,}/g, " ");

/**
 * Normalizes text for trigger detection by removing backticks and extra whitespace
 */
export const normalizeForTrigger = (raw: string): string =>
  raw
    .replace(/[`]/g, " ")
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/\s+/g, " ")
    .trim();

/**
 * Creates a streaming filter that removes <think>...</think> tags from chunks.
 * Returns an object with consume() for processing chunks and flush() for final output.
 */
export const makeThinkFilter = () => {
  const CARRY_OPEN = 16;
  const CARRY_CLOSE = 16;
  const state: ThinkState = { inThink: false, carry: "" };

  const consume = (chunk: string): string => {
    let s = state.carry + chunk;
    let out = "";
    let i = 0;

    const lowerAt = (from: number) => s.slice(from).toLowerCase();

    while (i < s.length) {
      if (!state.inThink) {
        const L = lowerAt(i);
        const rel = L.indexOf("<think");
        if (rel === -1) {
          const keepTail = Math.max(0, s.length - CARRY_OPEN);
          out += s.slice(i, keepTail);
          state.carry = s.slice(keepTail);
          break;
        } else {
          const j = i + rel;
          out += s.slice(i, j);
          const end = s.indexOf(">", j);
          if (end === -1) {
            state.carry = s.slice(j);
            break;
          }
          state.inThink = true;
          i = end + 1;
        }
      } else {
        const L = lowerAt(i);
        const rel = L.indexOf("</think");
        if (rel === -1) {
          const keepTail = Math.max(0, s.length - CARRY_CLOSE);
          state.carry = s.slice(i >= s.length ? s.length : keepTail);
          break;
        } else {
          const j = i + rel;
          const end = s.indexOf(">", j);
          if (end === -1) {
            state.carry = s.slice(j);
            break;
          }
          state.inThink = false;
          i = end + 1;
        }
      }
    }
    return out;
  };

  const flush = (): string => {
    if (!state.inThink && state.carry) {
      const tail = state.carry;
      state.carry = "";
      return tail;
    }
    state.carry = "";
    return "";
  };

  return { consume, flush };
};
