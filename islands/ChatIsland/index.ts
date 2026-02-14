/**
 * @file index.ts
 * @description Central export file for ChatIsland module components, hooks, and utilities.
 *              Provides convenient re-exports for all sub-modules.
 * @importantFunctions All exports from types, hooks, utils, services, and components
 */

// Types
export * from "./types.ts";

// Hooks
export { useChatState } from "./hooks/useChatState.ts";
export type { UseChatStateReturn } from "./hooks/useChatState.ts";

export { useChatPersistence } from "./hooks/useChatPersistence.ts";
export type {
  UseChatPersistenceParams,
  UseChatPersistenceReturn,
} from "./hooks/useChatPersistence.ts";

export { useAudioPlayback } from "./hooks/useAudioPlayback.ts";
export type {
  UseAudioPlaybackParams,
  UseAudioPlaybackReturn,
} from "./hooks/useAudioPlayback.ts";

// Utils
export {
  countWords,
  isValidDot,
  findChunkEnd,
  splitIntoSmartChunks,
  cleanForTTS,
  normalizeForTrigger,
  makeThinkFilter,
} from "./utils/textProcessing.ts";

export {
  extractCompletedJsonSearchBlocks,
  isValidSearchJson,
  tryParseJsonLenient,
  jsonObjToTriggers,
  findJsonTriggersInText,
  findHashtagTriggersInUserText,
  buildAutoSummaryPrompt,
  keyOfTrigger,
} from "./utils/triggerParsing.ts";

// Services
export {
  createServerLogger,
  fetchBildungsplan,
  fetchWikipedia,
  fetchPapers,
  fetchImageGen,
  formatWikipediaResults,
  formatPapersResults,
  formatBildungsplanResults,
  formatImageGenResults,
} from "./services/apiService.ts";

export {
  startStream,
  executeTriggers,
  generateImageId,
  findImageByIdInMessages,
  getAllImageIds,
  findHighestImageIdForPrefix,
  buildImageContextHints,
} from "./services/streamService.ts";
export type { StreamContext } from "./services/streamService.ts";

// Components
export { ChatHeader } from "./components/ChatHeader.tsx";
