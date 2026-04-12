/**
 * @file ChatIsland.tsx
 * @description Main orchestrator component for the chat interface.
 *              Combines hooks, services, and UI components to provide the complete chat experience.
 *              This file serves as the entry point and composes all sub-modules.
 * @importantFunctions ChatIsland (default export)
 */

import { useEffect, useCallback, useState } from "preact/hooks";
import ChatTemplate from "../components/ChatTemplate.tsx";
import { ChatSubmitButton } from "../components/ChatSubmitButton.tsx";
import ImageUploadButton from "../components/ImageUploadButton.tsx";
import AudioUploadButton from "../components/AudioUploadButton.tsx";
import VoiceRecordButton from "../components/VoiceRecordButton.tsx";
import { PdfUploadButton, PdfFile } from "../components/PdfUploadButton.tsx";
import Settings from "../components/Settings.tsx";
import { chatIslandContent } from "../internalization/content.ts";

// Import from refactored modules
import {
  Message,
  AudioItem,
  useChatState,
  useChatPersistence,
  useAudioPlayback,
  createServerLogger,
  ChatHeader,
} from "./ChatIsland/index.ts";
import { startStream, StreamContext } from "./ChatIsland/services/streamService.ts";
import { rehydrateImages } from "./ChatIsland/services/imageStore.ts";

// Debug flag
const DEBUG = true;

export default function ChatIsland({ lang }: { lang: string }) {
  // Initialize core state hook
  const state = useChatState(lang);

  // Create server logger
  const serverLog = useCallback(
    createServerLogger(DEBUG, () => state.currentChatSuffix),
    [state.currentChatSuffix]
  );

  // Composer height reset helper
  const resetComposerHeight = useCallback(() => {
    const textarea = document.querySelector<HTMLTextAreaElement>("textarea");
    if (textarea) {
      textarea.style.height = "";
      textarea.scrollTop = 0;
    }
  }, []);

  // Initialize audio playback hook
  const audio = useAudioPlayback({
    lang,
    settings: state.settings,
    audioFileDict: state.audioFileDict,
    setAudioFileDict: state.setAudioFileDict,
    stopList: state.stopList,
    setStopList: state.setStopList,
    playSessionRef: state.playSessionRef,
    readAlways: state.readAlways,
    setReadAlways: state.setReadAlways,
    setPendingManualSpeak: state.setPendingManualSpeak,
  });

  // Initialize persistence hook
  const persistence = useChatPersistence({
    lang,
    currentChatSuffix: state.currentChatSuffix,
    localStorageKeys: state.localStorageKeys,
    setMessages: state.setMessages,
    setCurrentChatSuffix: state.setCurrentChatSuffix,
    setLocalStorageKeys: state.setLocalStorageKeys,
    stopAndResetAudio: audio.stopAndResetAudio,
    resetComposerHeight,
  });

  // Create stream context for the streaming service
  const createStreamContext = useCallback(
    (): StreamContext => ({
      lang,
      settings: state.settings,
      currentChatSuffix: state.currentChatSuffix,
      messages: state.messages,
      messagesRef: state.messagesRef,
      abortRef: state.abortRef,
      setMessages: state.setMessages,
      setIsStreamComplete: state.setIsStreamComplete,
      setQuery: state.setQuery,
      safePersist: persistence.safePersist,
      safePersistThrottled: persistence.safePersistThrottled,
      flushPersistThrottle: persistence.flushPersistThrottle,
      getTTS: audio.getTTS,
      serverLog,
      chatIslandContent,
    }),
    [
      lang,
      state.settings,
      state.currentChatSuffix,
      state.messages,
      state.messagesRef,
      state.abortRef,
      state.setMessages,
      state.setIsStreamComplete,
      state.setQuery,
      persistence.safePersist,
      persistence.safePersistThrottled,
      persistence.flushPersistThrottle,
      audio.getTTS,
      serverLog,
    ]
  );

  // Start stream handler
  const handleStartStream = useCallback(
    async (transcript: string, prevMessages?: Message[]) => {
      const ctx = createStreamContext();
      await startStream(
        transcript,
        ctx,
        prevMessages,
        state.currentEditIndex,
        state.query,
        state.images,
        state.pdfs,
        resetComposerHeight,
        state.setImages,
        state.setPdfs,
        state.setCurrentEditIndex,
        state.setResetTranscript,
        state.audioFileDict,
        (t: string, acc: Message[]) => handleStartStream(t, acc)
      );
    },
    [
      createStreamContext,
      state.currentEditIndex,
      state.query,
      state.images,
      state.pdfs,
      state.setImages,
      state.setPdfs,
      state.setCurrentEditIndex,
      state.setResetTranscript,
      state.audioFileDict,
      resetComposerHeight,
    ]
  );

  // Handle refresh action
  const handleRefreshAction = useCallback(
    (groupIndex: number) => {
      if (!(groupIndex >= 0 && groupIndex < state.messages.length)) return;

      state.abortRef.current?.abort();
      state.abortRef.current = null;
      state.setIsStreamComplete(true);

      state.playSessionRef.current += 1;
      audio.stopAndResetAudio();

      let sliceStart = groupIndex;
      if (state.messages[groupIndex - 1]?.role === "user") {
        sliceStart = groupIndex - 1;
      }

      const prev = state.messages.slice(0, sliceStart);
      const upcomingAssistantGroup = prev.length;
      state.playSessionRef.current += 1;
      audio.clearGroupAudio(upcomingAssistantGroup);

      const userMsg = state.messages[sliceStart];
      let userText = "";
      if (userMsg?.role === "user") {
        if (typeof userMsg.content === "string") userText = userMsg.content;
        else if (Array.isArray(userMsg.content)) {
          const t = userMsg.content.find(
            (p: unknown) => (p as { type?: string })?.type === "text"
          );
          userText = (t as { text?: string })?.text ?? "";
        }
      }
      if (!userText.trim()) return;

      state.setStopList([]);
      state.setMessages(prev);
      persistence.safePersist(prev, state.currentChatSuffix);
      handleStartStream(userText, prev);
    },
    [
      state.messages,
      state.abortRef,
      state.setIsStreamComplete,
      state.playSessionRef,
      state.setStopList,
      state.setMessages,
      state.currentChatSuffix,
      audio.stopAndResetAudio,
      audio.clearGroupAudio,
      persistence.safePersist,
      handleStartStream,
    ]
  );

  // Handle edit action
  const handleEditAction = useCallback(
    (groupIndex: number) => {
      const message = state.messages[groupIndex];
      let contentToEdit = "";

      if (typeof message.content === "string") {
        contentToEdit = message.content;
      } else if (Array.isArray(message.content)) {
        if (typeof message.content[0] === "string") {
          contentToEdit = message.content.join("");
        } else {
          contentToEdit = message.content
            .filter((item: unknown) => (item as { type?: string }).type === "text")
            .map((item: unknown) => (item as { text?: string }).text)
            .join("");
        }
      }

      state.setQuery(contentToEdit);
      state.setStopList([]);
      state.setCurrentEditIndex(groupIndex);

      const textarea = document.querySelector("textarea");
      textarea?.focus();
    },
    [state.messages, state.setQuery, state.setStopList, state.setCurrentEditIndex]
  );

  // Handle upload action to messages
  const handleUploadActionToMessages = useCallback(
    (uploadedMessages: Message[]) => {
      const newMessages = uploadedMessages.map((msg) => [msg]).flat();
      state.setMessages(newMessages);
      persistence.safePersist(newMessages, state.currentChatSuffix);
      const textarea = document.querySelector("textarea");
      textarea?.focus();
    },
    [state.setMessages, state.currentChatSuffix, persistence.safePersist]
  );

  // Handle images uploaded
  const handleImagesUploaded = useCallback(
    (newImages: unknown[]) => {
      state.setImages((prev) => [...prev, ...newImages]);
    },
    [state.setImages]
  );

  // Handle PDFs uploaded
  const handlePdfsUploaded = useCallback(
    (newPdfs: PdfFile[]) => {
      state.setPdfs((prev) => [...prev, ...newPdfs]);
    },
    [state.setPdfs]
  );

  // Handle image change
  const handleImageChange = useCallback(
    (images_: unknown[]) => {
      state.setImages(images_);
    },
    [state.setImages]
  );

  // State for audio transcription status
  const [isAudioTranscribing, setIsAudioTranscribing] = useState(false);

  // Handle audio transcription complete
  const handleAudioTranscriptionComplete = useCallback(
    (transcription: string, fileName: string) => {
      setIsAudioTranscribing(false);
      // Add transcription to the query with context about the source file
      const prefix = `[Transcription of "${fileName}"]:\n`;
      state.setQuery((prevQuery) => {
        if (prevQuery.trim()) {
          return `${prevQuery}\n\n${prefix}${transcription}`;
        }
        return `${prefix}${transcription}`;
      });
      // Focus the textarea so user can add instructions
      const textarea = document.querySelector("textarea");
      textarea?.focus();
    },
    [state.setQuery]
  );

  // Handle audio transcription start
  const handleAudioTranscriptionStart = useCallback(() => {
    setIsAudioTranscribing(true);
  }, []);

  // Handle audio transcription error
  const handleAudioTranscriptionError = useCallback(
    (error: string) => {
      setIsAudioTranscribing(false);
      console.error("Audio transcription error:", error);
      // Optionally show error to user via alert or toast
      alert(`Transcription failed: ${error}`);
    },
    []
  );

  // Handle speak action wrapper
  const handleOnSpeakAtGroupIndexAction = useCallback(
    (groupIndex: number) => {
      audio.handleOnSpeakAtGroupIndexAction(groupIndex, state.messages);
    },
    [audio.handleOnSpeakAtGroupIndexAction, state.messages]
  );

  // ============ useEffects ============

  // 1) First load from localStorage, then rehydrate images from IndexedDB
  useEffect(() => {
    let lsKeys: string[] = Object.keys(localStorage).filter((key) =>
      key.startsWith("bude-chat-")
    );
    lsKeys = lsKeys.length > 0 ? lsKeys : ["bude-chat-0"];
    lsKeys.sort((a, b) => Number(a.slice(10)) - Number(b.slice(10)));
    const currSuffix = lsKeys.length > 0 ? String(lsKeys[0].slice(10)) : "0";
    let lsMsgs = JSON.parse(
      String(localStorage.getItem("bude-chat-" + currSuffix))
    );
    lsMsgs = lsMsgs || [
      { role: "assistant", content: [chatIslandContent[lang]["welcomeMessage"]] },
    ];
    state.setLocalStorageKeys(lsKeys);
    state.setCurrentChatSuffix(currSuffix);

    // Rehydrate images from IndexedDB (restores base64 data from idb:// placeholders)
    rehydrateImages(lsMsgs, currSuffix).then((restored) => {
      state.setMessages(restored);
    }).catch(() => {
      state.setMessages(lsMsgs); // Fallback: use messages without images
    });
  }, []);

  // 2) Persist last assistant message when stream completes
  useEffect(() => {
    if (state.isStreamComplete) {
      if ("content" in state.messages[state.messages.length - 1]) {
        const lastMessageContent = state.messages[state.messages.length - 1]["content"];

        // Extract text for TTS without modifying the original content
        let textForTTS = "";
        let hasContent = false;

        if (typeof lastMessageContent === "string") {
          textForTTS = lastMessageContent;
          hasContent = textForTTS.trim() !== "";
        } else if (Array.isArray(lastMessageContent)) {
          // Check if this is multimodal content (objects with 'type' property)
          // deno-lint-ignore no-explicit-any
          const isMultimodal = lastMessageContent.some(
            (part: any) => part && typeof part === "object" && "type" in part
          );

          if (isMultimodal) {
            // Extract text from multimodal parts for TTS, but don't modify content
            // deno-lint-ignore no-explicit-any
            textForTTS = lastMessageContent
              .filter((part: any) => part?.type === "text")
              .map((part: any) => part.text || "")
              .join("");
            // Multimodal content always counts as having content (may have images)
            hasContent = lastMessageContent.length > 0;
          } else {
            // Legacy format: array of strings - join them
            textForTTS = (lastMessageContent as string[]).join("");
            hasContent = textForTTS.trim() !== "";
            // For legacy format, we can normalize to string
            if (hasContent) {
              state.messages[state.messages.length - 1]["content"] = textForTTS;
            }
          }
        }

        if (hasContent && state.messages.length > 1) {
          persistence.safePersist(state.messages, state.currentChatSuffix);

          if (
            !state.localStorageKeys.includes("bude-chat-" + state.currentChatSuffix)
          ) {
            state.setLocalStorageKeys([
              ...state.localStorageKeys,
              "bude-chat-" + state.currentChatSuffix,
            ]);
          }
        }

        // TTS for welcome message
        if (textForTTS.trim() !== "") {
          const groupIndex = state.messages.length - 1;
          if (groupIndex === 0) {
            audio.getTTS(textForTTS, groupIndex, "stream");
          }
        }
      }
    }
  }, [state.isStreamComplete]);

  // 3) Auto-scroll & persist messages on change
  useEffect(() => {
    if (state.autoScroll) {
      const chatContainer = document.querySelector(".chat-history");
      if (chatContainer) {
        (chatContainer as HTMLElement).scrollTo({
          top: (chatContainer as HTMLElement).scrollHeight,
          behavior: "smooth",
        });
      }
    }
    if (!state.firstLoad) {
      persistence.safePersist(state.messages, state.currentChatSuffix);
      state.setLocalStorageKeys(
        Object.keys(localStorage).filter((key) => key.startsWith("bude-chat-"))
      );
    }
    if (state.firstLoad) state.setFirstLoad(false);
  }, [state.messages, state.autoScroll]);

  // 4) Switch chat
  useEffect(() => {
    const lsMsgs = JSON.parse(
      String(localStorage.getItem("bude-chat-" + state.currentChatSuffix))
    ) || [
      { role: "assistant", content: [chatIslandContent[lang]["welcomeMessage"]] },
    ];
    if (lsMsgs.length === 1) {
      if (lsMsgs[0].content[0] !== chatIslandContent[lang]["welcomeMessage"]) {
        lsMsgs[0].content[0] = chatIslandContent[lang]["welcomeMessage"];
      }
    }
    // Rehydrate images from IndexedDB when switching chats
    rehydrateImages(lsMsgs, state.currentChatSuffix).then((restored) => {
      state.setMessages(restored);
    }).catch(() => {
      state.setMessages(lsMsgs);
    });
    audio.stopAndResetAudio();
    state.setStopList([]);
    resetComposerHeight();
  }, [state.currentChatSuffix]);

  // 5) Auto-play queue if readAlways
  useEffect(() => {
    if (!state.readAlways) return;
    Object.entries(state.audioFileDict).forEach(([groupIndex, groupAudios]) => {
      const nextUnplayedIndex = audio.findNextUnplayedAudio(groupAudios);
      if (nextUnplayedIndex === null) return;

      const isLatestGroup =
        Math.max(...Object.keys(state.audioFileDict).map(Number)) <=
        Number(groupIndex);

      if (
        isLatestGroup &&
        audio.canPlayAudio(
          Number(groupIndex),
          nextUnplayedIndex,
          groupAudios,
          state.stopList
        )
      ) {
        audio.playAudio(
          groupAudios[nextUnplayedIndex].audio,
          Number(groupIndex),
          nextUnplayedIndex
        );
      }

      if (state.stopList.includes(Number(groupIndex))) {
        (Object.values(groupAudios) as AudioItem[]).forEach((item) => {
          if (!item.audio.paused) {
            item.audio.pause();
            item.audio.currentTime = 0;
          }
        });
      }
    });
  }, [state.audioFileDict, state.readAlways, state.stopList]);

  // 6) Flush throttled persist on unload/hidden
  useEffect(() => {
    const flush = () => {
      persistence.flushPersistThrottle();
      persistence.safePersist(state.messages, state.currentChatSuffix);
    };
    const vis = () => {
      if (document.visibilityState === "hidden") flush();
    };
    window.addEventListener("beforeunload", flush);
    document.addEventListener("visibilitychange", vis);
    return () => {
      window.removeEventListener("beforeunload", flush);
      document.removeEventListener("visibilitychange", vis);
    };
  }, [state.messages, state.currentChatSuffix]);

  // ============ Render ============
  return (
    <div className="w-full">
      <ChatHeader
        lang={lang}
        localStorageKeys={state.localStorageKeys}
        currentChatSuffix={state.currentChatSuffix}
        onChatSelect={state.setCurrentChatSuffix}
        onSettingsClick={() => state.setShowSettings(true)}
        onNewChat={persistence.startNewChat}
        onDeleteCurrentChat={persistence.deleteCurrentChat}
        onDeleteAllChats={persistence.deleteAllChats}
        onSaveChats={persistence.saveChatsToLocalFile}
        onRestoreChats={persistence.restoreChatsFromLocalFile}
      />

      <ChatTemplate
        lang={lang}
        parentImages={state.images}
        parentPdfs={state.pdfs}
        messages={state.messages}
        isComplete={state.isStreamComplete}
        onCancelAction={() => {
          state.abortRef.current?.abort();
          state.abortRef.current = null;
          state.setIsStreamComplete(true);
        }}
        readAlways={state.readAlways}
        autoScroll={state.autoScroll}
        audioFileDict={state.audioFileDict}
        currentEditIndex={state.currentEditIndex!}
        onSpeakAtGroupIndexAction={handleOnSpeakAtGroupIndexAction}
        onToggleReadAlwaysAction={() => audio.toggleReadAlways(!state.readAlways)}
        onToggleAutoScrollAction={() => state.setAutoScroll(!state.autoScroll)}
        onRefreshAction={handleRefreshAction}
        onEditAction={handleEditAction}
        onUploadActionToMessages={handleUploadActionToMessages}
        onImageChange={handleImageChange}
        onTrashAction={() => state.setMessages([])}
      />

      {state.showSettings && (
        <Settings
          settings={state.settings}
          onSave={state.handleSaveSettings}
          onClose={() => state.setShowSettings(false)}
          lang={lang}
        />
      )}

      {state.settings.universalApiKey ||
      (state.settings.apiKey &&
        state.settings.apiModel &&
        state.settings.apiUrl) ? (
        <div className="relative mt-4 mb-12 w-full">
          <textarea
            value={state.query}
            placeholder={chatIslandContent[lang]["placeholderText"]}
            onInput={(e) => state.setQuery(e.currentTarget.value)}
            onKeyPress={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                handleStartStream("");
              }
            }}
            className="h-64 w-full py-4 pl-4 pr-16 border border-gray-300 rounded-lg focus:outline-none cursor-text focus:border-orange-200 focus:ring-1 focus:ring-orange-300 shadow-sm resize-none placeholder-gray-400 text-base font-medium"
          />

          <ImageUploadButton
            onImagesUploaded={handleImagesUploaded}
            messages={state.messages}
          />

          <PdfUploadButton onPdfsUploaded={handlePdfsUploaded} />

          <AudioUploadButton
            onTranscriptionComplete={handleAudioTranscriptionComplete}
            onTranscriptionStart={handleAudioTranscriptionStart}
            onTranscriptionError={handleAudioTranscriptionError}
            sttUrl={state.settings.sttUrl}
            sttKey={state.settings.sttKey}
            sttModel={state.settings.sttModel}
            universalApiKey={state.settings.universalApiKey}
            disabled={isAudioTranscribing}
          />

          <VoiceRecordButton
            resetTranscript={state.resetTranscript}
            sttUrl={state.settings.sttUrl}
            sttKey={state.settings.sttKey}
            sttModel={state.settings.sttModel}
            universalApiKey={state.settings.universalApiKey}
            onFinishRecording={(finalTranscript) => {
              // Combine existing query (e.g., from audio file transcription) with voice recording
              const existingText = state.query.trim();
              const combinedText = existingText
                ? `${existingText}\n\n${finalTranscript}`
                : finalTranscript;
              handleStartStream(combinedText);
            }}
            onInterimTranscript={(interimTranscript) => {
              state.setQuery((q) => (q ? q + " " : "") + interimTranscript);
            }}
          />

          <ChatSubmitButton
            onClick={() => handleStartStream("")}
            disabled={
              !state.query &&
              state.images.length === 0 &&
              state.pdfs.length === 0
            }
          />
        </div>
      ) : (
        <div className="relative mt-4 mb-12 bg-gray-700 rounded-md">
          <div className="text-center text-md p-4 text-white">
            {chatIslandContent[lang]["noSettings"]}
          </div>
        </div>
      )}
    </div>
  );
}
