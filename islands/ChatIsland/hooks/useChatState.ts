/**
 * @file useChatState.ts
 * @description Core state management hook for the chat system.
 *              Manages messages, settings, query input, and related state.
 * @importantFunctions useChatState
 */

import { useState, useEffect, useRef } from "preact/hooks";
import { Message, Settings, AudioFileDict, PdfFile } from "../types.ts";
import { chatIslandContent } from "../../../internalization/content.ts";

/**
 * Default settings loaded from localStorage
 */
const loadSettingsFromStorage = (): Settings => ({
  universalApiKey: localStorage.getItem("bud-e-universal-api-key") || "",
  apiUrl: localStorage.getItem("bud-e-api-url") || "",
  apiKey: localStorage.getItem("bud-e-api-key") || "",
  apiModel: localStorage.getItem("bud-e-model") || "",
  ttsUrl: localStorage.getItem("bud-e-tts-url") || "",
  ttsKey: localStorage.getItem("bud-e-tts-key") || "",
  ttsModel: localStorage.getItem("bud-e-tts-model") || "tts-1",
  sttUrl: localStorage.getItem("bud-e-stt-url") || "",
  sttKey: localStorage.getItem("bud-e-stt-key") || "",
  sttModel: localStorage.getItem("bud-e-stt-model") || "",
  systemPrompt: localStorage.getItem("bud-e-system-prompt") || "",
  vlmUrl: localStorage.getItem("bud-e-vlm-url") || "",
  vlmKey: localStorage.getItem("bud-e-vlm-key") || "",
  vlmModel: localStorage.getItem("bud-e-vlm-model") || "",
  vlmCorrectionModel: localStorage.getItem("bud-e-vlm-correction-model") || "",
});

/**
 * Saves settings to localStorage
 */
const saveSettingsToStorage = (settings: Settings): void => {
  localStorage.setItem("bud-e-universal-api-key", settings.universalApiKey);
  localStorage.setItem("bud-e-api-url", settings.apiUrl);
  localStorage.setItem("bud-e-api-key", settings.apiKey);
  localStorage.setItem("bud-e-model", settings.apiModel);
  localStorage.setItem("bud-e-tts-url", settings.ttsUrl);
  localStorage.setItem("bud-e-tts-key", settings.ttsKey);
  localStorage.setItem("bud-e-tts-model", settings.ttsModel);
  localStorage.setItem("bud-e-stt-url", settings.sttUrl);
  localStorage.setItem("bud-e-stt-key", settings.sttKey);
  localStorage.setItem("bud-e-stt-model", settings.sttModel);
  localStorage.setItem("bud-e-system-prompt", settings.systemPrompt);
  localStorage.setItem("bud-e-vlm-url", settings.vlmUrl);
  localStorage.setItem("bud-e-vlm-key", settings.vlmKey);
  localStorage.setItem("bud-e-vlm-model", settings.vlmModel);
  localStorage.setItem("bud-e-vlm-correction-model", settings.vlmCorrectionModel);
};

export interface UseChatStateReturn {
  // Core message state
  messages: Message[];
  setMessages: (msgs: Message[] | ((prev: Message[]) => Message[])) => void;
  messagesRef: React.MutableRefObject<Message[]>;

  // Query/input state
  query: string;
  setQuery: (q: string) => void;

  // Chat switching
  currentChatSuffix: string;
  setCurrentChatSuffix: (suffix: string) => void;
  localStorageKeys: string[];
  setLocalStorageKeys: (keys: string[] | ((prev: string[]) => string[])) => void;

  // Settings
  settings: Settings;
  setSettings: (s: Settings) => void;
  showSettings: boolean;
  setShowSettings: (show: boolean) => void;
  handleSaveSettings: (newSettings: Settings) => void;

  // Stream state
  isStreamComplete: boolean;
  setIsStreamComplete: (complete: boolean) => void;
  abortRef: React.MutableRefObject<AbortController | null>;

  // Edit state
  currentEditIndex: number | undefined;
  setCurrentEditIndex: (index: number | undefined) => void;

  // Media uploads
  images: unknown[];
  setImages: (imgs: unknown[] | ((prev: unknown[]) => unknown[])) => void;
  pdfs: PdfFile[];
  setPdfs: (pdfs: PdfFile[] | ((prev: PdfFile[]) => PdfFile[])) => void;

  // Audio state
  audioFileDict: AudioFileDict;
  setAudioFileDict: (dict: AudioFileDict | ((prev: AudioFileDict) => AudioFileDict)) => void;
  stopList: number[];
  setStopList: (list: number[] | ((prev: number[]) => number[])) => void;
  playSessionRef: React.MutableRefObject<number>;
  pendingManualSpeak: Set<number>;
  setPendingManualSpeak: (set: Set<number> | ((prev: Set<number>) => Set<number>)) => void;

  // UI state
  readAlways: boolean;
  setReadAlways: (value: boolean) => void;
  autoScroll: boolean;
  setAutoScroll: (value: boolean) => void;

  // STT state
  resetTranscript: number;
  setResetTranscript: (value: number | ((prev: number) => number)) => void;

  // First load flag
  firstLoad: boolean;
  setFirstLoad: (value: boolean) => void;
}

/**
 * Main hook for chat state management.
 * Centralizes all state used by the chat system.
 */
export const useChatState = (lang: string): UseChatStateReturn => {
  // First load flag
  const [firstLoad, setFirstLoad] = useState(true);

  // Chat and message state
  const [query, setQuery] = useState("");
  const [currentChatSuffix, setCurrentChatSuffix] = useState("0");
  const [localStorageKeys, setLocalStorageKeys] = useState<string[]>([]);
  const [messages, setMessages] = useState<Message[]>([
    {
      role: "assistant",
      content: [chatIslandContent[lang]["welcomeMessage"]],
    },
  ]);
  const messagesRef = useRef<Message[]>(messages);

  // Settings state
  const [settings, setSettings] = useState<Settings>(loadSettingsFromStorage());
  const [showSettings, setShowSettings] = useState(false);

  // Stream state
  const [isStreamComplete, setIsStreamComplete] = useState(true);
  const abortRef = useRef<AbortController | null>(null);

  // Edit state
  const [currentEditIndex, setCurrentEditIndex] = useState<number | undefined>(-1);

  // Media state
  const [images, setImages] = useState<unknown[]>([]);
  const [pdfs, setPdfs] = useState<PdfFile[]>([]);

  // Audio state
  const [audioFileDict, setAudioFileDict] = useState<AudioFileDict>({});
  const [stopList, setStopList] = useState<number[]>([]);
  const playSessionRef = useRef(0);
  const [pendingManualSpeak, setPendingManualSpeak] = useState<Set<number>>(new Set());

  // UI preferences
  const [readAlways, setReadAlways] = useState(false);
  const [autoScroll, setAutoScroll] = useState(true);

  // STT state
  const [resetTranscript, setResetTranscript] = useState(0);

  // Keep messagesRef in sync
  useEffect(() => {
    messagesRef.current = messages;
  }, [messages]);

  // Load settings on mount
  useEffect(() => {
    setSettings(loadSettingsFromStorage());
  }, []);

  // Handle saving settings
  const handleSaveSettings = (newSettings: Settings) => {
    setSettings(newSettings);
    saveSettingsToStorage(newSettings);
    setShowSettings(false);
  };

  return {
    messages,
    setMessages,
    messagesRef,
    query,
    setQuery,
    currentChatSuffix,
    setCurrentChatSuffix,
    localStorageKeys,
    setLocalStorageKeys,
    settings,
    setSettings,
    showSettings,
    setShowSettings,
    handleSaveSettings,
    isStreamComplete,
    setIsStreamComplete,
    abortRef,
    currentEditIndex,
    setCurrentEditIndex,
    images,
    setImages,
    pdfs,
    setPdfs,
    audioFileDict,
    setAudioFileDict,
    stopList,
    setStopList,
    playSessionRef,
    pendingManualSpeak,
    setPendingManualSpeak,
    readAlways,
    setReadAlways,
    autoScroll,
    setAutoScroll,
    resetTranscript,
    setResetTranscript,
    firstLoad,
    setFirstLoad,
  };
};
