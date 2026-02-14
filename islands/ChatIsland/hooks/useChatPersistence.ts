/**
 * @file useChatPersistence.ts
 * @description Hook for chat persistence operations including localStorage management,
 *              chat creation/deletion, and import/export functionality.
 * @importantFunctions useChatPersistence, safePersist, startNewChat, deleteCurrentChat
 */

import { useRef, useCallback } from "preact/hooks";
import { Message } from "../types.ts";
import { chatIslandContent } from "../../../internalization/content.ts";

export interface UseChatPersistenceParams {
  lang: string;
  currentChatSuffix: string;
  localStorageKeys: string[];
  setMessages: (msgs: Message[]) => void;
  setCurrentChatSuffix: (suffix: string) => void;
  setLocalStorageKeys: (keys: string[] | ((prev: string[]) => string[])) => void;
  stopAndResetAudio: () => void;
  resetComposerHeight: () => void;
}

export interface UseChatPersistenceReturn {
  safePersist: (msgs: Message[], suffix: string) => void;
  safePersistThrottled: (msgs: Message[], suffix: string) => void;
  flushPersistThrottle: () => void;
  startNewChat: () => void;
  deleteCurrentChat: () => void;
  deleteAllChats: () => void;
  saveChatsToLocalFile: () => void;
  restoreChatsFromLocalFile: (e: Event) => void;
}

/**
 * Hook for managing chat persistence to localStorage.
 * Handles saving, loading, creating, and deleting chats.
 */
export const useChatPersistence = ({
  lang,
  currentChatSuffix,
  localStorageKeys,
  setMessages,
  setCurrentChatSuffix,
  setLocalStorageKeys,
  stopAndResetAudio,
  resetComposerHeight,
}: UseChatPersistenceParams): UseChatPersistenceReturn => {
  // Throttle state for persistence
  const persistThrottleRef = useRef<{
    timer?: number;
    pending?: { msgs: Message[]; suffix: string };
  }>({});

  /**
   * Safely persists messages to localStorage with error handling.
   */
  const safePersist = useCallback(
    (msgs: Message[], suffix: string) => {
      try {
        localStorage.setItem("bude-chat-" + suffix, JSON.stringify(msgs));
        const key = "bude-chat-" + suffix;
        if (!localStorageKeys.includes(key)) {
          setLocalStorageKeys((prev) => [...new Set([...prev, key])]);
        }
      } catch (e: unknown) {
        const error = e as { name?: string };
        if (error?.name === "QuotaExceededError") {
          console.warn("localStorage quota exceeded while saving chat.");
        } else {
          console.warn("Failed to persist messages:", e);
        }
      }
    },
    [localStorageKeys, setLocalStorageKeys]
  );

  /**
   * Throttled version of safePersist to avoid excessive writes during streaming.
   */
  const safePersistThrottled = useCallback(
    (msgs: Message[], suffix: string) => {
      persistThrottleRef.current.pending = { msgs, suffix };
      if (persistThrottleRef.current.timer) return;
      persistThrottleRef.current.timer = window.setTimeout(() => {
        const p = persistThrottleRef.current.pending;
        if (p) safePersist(p.msgs, p.suffix);
        if (persistThrottleRef.current.timer) {
          clearTimeout(persistThrottleRef.current.timer);
        }
        persistThrottleRef.current.timer = undefined;
        persistThrottleRef.current.pending = undefined;
      }, 250);
    },
    [safePersist]
  );

  /**
   * Flushes any pending throttled persistence immediately.
   */
  const flushPersistThrottle = useCallback(() => {
    const p = persistThrottleRef.current.pending;
    if (p) safePersist(p.msgs, p.suffix);
    if (persistThrottleRef.current.timer) {
      clearTimeout(persistThrottleRef.current.timer);
    }
    persistThrottleRef.current.timer = undefined;
    persistThrottleRef.current.pending = undefined;
  }, [safePersist]);

  /**
   * Creates a new chat with default welcome message.
   */
  const startNewChat = useCallback(() => {
    const maxValueInChatSuffix = Math.max(
      ...localStorageKeys.map((key) => Number(key.slice(10)))
    );
    const newChatSuffix = String(Number(maxValueInChatSuffix) + 1);

    const welcome: Message[] = [
      {
        role: "assistant",
        content: [chatIslandContent[lang]["welcomeMessage"]],
      },
    ];

    setMessages(welcome);
    setCurrentChatSuffix(newChatSuffix);
    safePersist(welcome, newChatSuffix);
    resetComposerHeight();
  }, [
    localStorageKeys,
    lang,
    setMessages,
    setCurrentChatSuffix,
    safePersist,
    resetComposerHeight,
  ]);

  /**
   * Deletes the current chat and switches to another.
   */
  const deleteCurrentChat = useCallback(() => {
    if (localStorageKeys.length > 1) {
      localStorage.removeItem("bude-chat-" + currentChatSuffix);

      const nextChatSuffix = localStorageKeys
        .filter((key: string) => key !== "bude-chat-" + currentChatSuffix)
        .sort((a, b) => Number(a.slice(10)) - Number(b.slice(10)))[0]
        .slice(10);

      setMessages(
        JSON.parse(String(localStorage.getItem("bude-chat-" + nextChatSuffix)))
      );
      setCurrentChatSuffix(nextChatSuffix);
    } else {
      const welcome: Message[] = [
        {
          role: "assistant",
          content: [chatIslandContent[lang]["welcomeMessage"]],
        },
      ];
      setMessages(welcome);
      safePersist(welcome, "0");
    }
    stopAndResetAudio();
  }, [
    localStorageKeys,
    currentChatSuffix,
    lang,
    setMessages,
    setCurrentChatSuffix,
    safePersist,
    stopAndResetAudio,
  ]);

  /**
   * Deletes all chats and resets to initial state.
   */
  const deleteAllChats = useCallback(() => {
    localStorage.clear();
    const welcome: Message[] = [
      {
        role: "assistant",
        content: [chatIslandContent[lang]["welcomeMessage"]],
      },
    ];
    setMessages(welcome);
    setLocalStorageKeys([]);
    setCurrentChatSuffix("0");
    safePersist(welcome, "0");
    stopAndResetAudio();
  }, [
    lang,
    setMessages,
    setLocalStorageKeys,
    setCurrentChatSuffix,
    safePersist,
    stopAndResetAudio,
  ]);

  /**
   * Exports all chats to a local JSON file.
   */
  const saveChatsToLocalFile = useCallback(() => {
    const chats: Record<string, Message[]> = {};
    for (const key of localStorageKeys) {
      chats[key] = JSON.parse(String(localStorage.getItem(key)));
    }
    const chatsString = JSON.stringify(chats);
    const blob = new Blob([chatsString], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    const currentDate = new Date();
    a.download = `chats-${currentDate.toISOString()}.json`;
    a.click();
  }, [localStorageKeys]);

  /**
   * Imports chats from a local JSON file.
   */
  const restoreChatsFromLocalFile = useCallback(
    (e: Event) => {
      const target = e.target as HTMLInputElement;
      const file = target.files?.[0];
      if (!file) {
        console.error("No file selected");
        return;
      }

      const reader = new FileReader();
      reader.onload = (event) => {
        try {
          const chats = JSON.parse(event.target?.result as string) as Record<
            string,
            Message[]
          >;

          // Restore chats to localStorage
          for (const [key, value] of Object.entries(chats)) {
            localStorage.setItem(key, JSON.stringify(value));
          }

          const newChatSuffix = chats
            ? Object.keys(chats)
                .sort((a, b) => Number(a.slice(10)) - Number(b.slice(10)))[0]
                .slice(10)
            : "0";
          setLocalStorageKeys(
            Object.keys(localStorage).filter((key) =>
              key.startsWith("bude-chat-")
            )
          );
          setCurrentChatSuffix(newChatSuffix);
          const nextMsgs = chats["bude-chat-" + newChatSuffix];
          setMessages(nextMsgs);
          safePersist(nextMsgs, newChatSuffix);
        } catch (error) {
          console.error("Error parsing JSON file:", error);
        }
      };

      reader.onerror = (error) => {
        console.error("Error reading file:", error);
      };

      reader.readAsText(file);
    },
    [setLocalStorageKeys, setCurrentChatSuffix, setMessages, safePersist]
  );

  return {
    safePersist,
    safePersistThrottled,
    flushPersistThrottle,
    startNewChat,
    deleteCurrentChat,
    deleteAllChats,
    saveChatsToLocalFile,
    restoreChatsFromLocalFile,
  };
};
