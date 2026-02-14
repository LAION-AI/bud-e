/**
 * @file useAudioPlayback.ts
 * @description Hook for managing audio playback including TTS queue, audio state,
 *              and playback controls for the chat system.
 * @importantFunctions useAudioPlayback, getTTS, playAudio, stopAndResetAudio
 */

import { useRef, useCallback } from "preact/hooks";
import { AudioItem, AudioFileDict, Settings } from "../types.ts";
import { cleanForTTS, splitIntoSmartChunks } from "../utils/textProcessing.ts";
import { chatIslandContent } from "../../../internalization/content.ts";

export interface UseAudioPlaybackParams {
  lang: string;
  settings: Settings;
  audioFileDict: AudioFileDict;
  setAudioFileDict: (dict: AudioFileDict | ((prev: AudioFileDict) => AudioFileDict)) => void;
  stopList: number[];
  setStopList: (list: number[] | ((prev: number[]) => number[])) => void;
  playSessionRef: React.MutableRefObject<number>;
  readAlways: boolean;
  setReadAlways: (value: boolean) => void;
  setPendingManualSpeak: (set: Set<number> | ((prev: Set<number>) => Set<number>)) => void;
}

export interface UseAudioPlaybackReturn {
  getTTS: (text: string, groupIndex: number, sourceFunction: string) => Promise<void>;
  playAudio: (audio: HTMLAudioElement, groupIndex: number, audioIndex: number) => Promise<void>;
  findNextUnplayedAudio: (groupAudios: Record<number, AudioItem>) => number | null;
  canPlayAudio: (
    groupIndex: number,
    audioIndex: number,
    groupAudios: Record<number, AudioItem>,
    stopList_: number[]
  ) => boolean;
  startOrderedPlaybackForGroup: (groupIndex: number) => void;
  wireNeighborChaining: (groupIndex: number, idx: number) => void;
  stopAndResetAudio: () => void;
  toggleReadAlways: (value: boolean) => void;
  speakMessageInSmartChunks: (groupIndex: number, fullText: string) => void;
  handleOnSpeakAtGroupIndexAction: (
    groupIndex: number,
    messages: { content: unknown }[]
  ) => void;
  clearGroupAudio: (gi: number) => void;
  indexFromSourceFunction: (sourceFunction: string) => number;
  scheduleTTSJob: (fn: () => Promise<void>) => void;
}

// TTS concurrency pool configuration
const TTS_POOL_LIMIT = 6;

/**
 * Hook for managing audio playback in the chat system.
 * Handles TTS requests, audio queueing, and playback state.
 */
export const useAudioPlayback = ({
  lang,
  settings,
  audioFileDict,
  setAudioFileDict,
  stopList,
  setStopList,
  playSessionRef,
  readAlways,
  setReadAlways,
  setPendingManualSpeak,
}: UseAudioPlaybackParams): UseAudioPlaybackReturn => {
  // TTS queue management
  const ttsActiveRef = useRef(0);
  const ttsQueueRef = useRef<(() => Promise<void>)[]>([]);

  /**
   * Pumps the TTS queue, starting jobs up to the pool limit.
   */
  const pumpTtsQueue = useCallback(() => {
    while (ttsActiveRef.current < TTS_POOL_LIMIT && ttsQueueRef.current.length) {
      const job = ttsQueueRef.current.shift()!;
      ttsActiveRef.current++;
      job()
        .catch((e) => console.error("TTS job error:", e))
        .finally(() => {
          ttsActiveRef.current--;
          pumpTtsQueue();
        });
    }
  }, []);

  /**
   * Schedules a TTS job to be processed by the queue.
   */
  const scheduleTTSJob = useCallback(
    (fn: () => Promise<void>) => {
      ttsQueueRef.current.push(fn);
      pumpTtsQueue();
    },
    [pumpTtsQueue]
  );

  /**
   * Parses the audio index from a source function string.
   */
  const indexFromSourceFunction = useCallback((sourceFunction: string): number => {
    const m = sourceFunction.match(/(?:^|_)stream(\d+)/);
    return m ? Math.max(0, Number(m[1]) - 1) : 0;
  }, []);

  /**
   * Finds the next unplayed audio in a group.
   */
  const findNextUnplayedAudio = useCallback(
    (groupAudios: Record<number, AudioItem>): number | null => {
      const [nextUnplayed] = Object.entries(groupAudios)
        .sort(([a], [b]) => Number(a) - Number(b))
        .find(([_, item]) => !item.played) || [];
      return nextUnplayed !== undefined ? Number(nextUnplayed) : null;
    },
    []
  );

  /**
   * Determines if an audio clip can be played based on group state.
   */
  const canPlayAudio = useCallback(
    (
      groupIndex: number,
      audioIndex: number,
      groupAudios: Record<number, AudioItem>,
      stopList_: number[]
    ): boolean => {
      if (stopList_.includes(Number(groupIndex))) return false;

      // Never start a new clip if any clip in this group is currently playing
      const anyPlaying = Object.values(groupAudios).some(
        (it) => !it.audio.paused && !it.audio.ended
      );
      if (anyPlaying) return false;

      // First clip: only start when nothing else is playing
      if (audioIndex === 0) return true;

      // For subsequent clips, require the predecessor to have ended
      const prev = groupAudios[audioIndex - 1];
      return !!prev && prev.played && prev.audio.ended === true;
    },
    []
  );

  /**
   * Plays an audio element and updates its state.
   */
  const playAudio = useCallback(
    async (audio: HTMLAudioElement, groupIndex: number, audioIndex: number) => {
      try {
        await audio.play();
        setAudioFileDict((prev) => {
          const next = { ...prev };
          const group = { ...(next[groupIndex] || {}) };
          const item = { ...(group[audioIndex] || {}) } as AudioItem;
          item.played = true;
          group[audioIndex] = item;
          next[groupIndex] = group;
          return next;
        });
      } catch (err) {
        console.warn("Audio play() rejected:", err);
      }
    },
    [setAudioFileDict]
  );

  /**
   * Clears all audio for a specific group, releasing resources.
   */
  const clearGroupAudio = useCallback(
    (gi: number) => {
      const group = audioFileDict[gi];
      if (!group) return;
      Object.values(group).forEach(({ audio }) => {
        try {
          audio.pause();
          audio.currentTime = 0;
        } catch {}
        try {
          if (audio.src?.startsWith("blob:")) URL.revokeObjectURL(audio.src);
        } catch {}
        audio.onended = null;
        audio.src = "";
      });
      setAudioFileDict((prev) => {
        const next = { ...prev };
        delete next[gi];
        return next;
      });
    },
    [audioFileDict, setAudioFileDict]
  );

  /**
   * Stops and resets all audio across all groups.
   */
  const stopAndResetAudio = useCallback(() => {
    try {
      Object.values(audioFileDict).forEach((group) => {
        Object.values(group || {}).forEach((item) => {
          const a = item?.audio;
          if (!a) return;
          try {
            a.pause();
          } catch {}
          try {
            a.currentTime = 0;
          } catch {}
          try {
            const src = a.src;
            if (src && src.startsWith("blob:")) URL.revokeObjectURL(src);
          } catch {}
          a.onended = null;
          a.src = "";
        });
      });
    } catch {}
    setAudioFileDict({});
    setStopList([]);
  }, [audioFileDict, setAudioFileDict, setStopList]);

  /**
   * Toggles the read-always mode for automatic TTS.
   */
  const toggleReadAlways = useCallback(
    (value: boolean) => {
      setReadAlways(value);
      if (!value) {
        Object.values(audioFileDict).forEach((group) => {
          Object.values(group).forEach((item: AudioItem) => {
            if (!item.audio.paused) {
              item.audio.pause();
              item.audio.currentTime = 0;
            }
          });
        });
        setStopList(Object.keys(audioFileDict).map(Number));
      }
    },
    [audioFileDict, setReadAlways, setStopList]
  );

  /**
   * Starts ordered playback for a specific group.
   */
  const startOrderedPlaybackForGroup = useCallback(
    (groupIndex: number) => {
      // Pause all other groups
      const newStopList = stopList.slice();
      Object.entries(audioFileDict).forEach(([gStr, group]) => {
        const gi = Number(gStr);
        if (gi !== groupIndex) {
          Object.values(group).forEach((item) => {
            if (!item.audio.paused) {
              item.audio.pause();
              item.audio.currentTime = 0;
            }
          });
          if (!newStopList.includes(gi)) newStopList.push(gi);
        }
      });
      setStopList(newStopList);

      // Play first or next-unplayed audio
      const group = audioFileDict[groupIndex];
      if (!group) return;
      const nextIdx = findNextUnplayedAudio(group);
      const first = nextIdx !== null ? group[nextIdx]?.audio : group[0]?.audio;
      if (!first) return;

      first.play().catch((err) => console.warn("Audio play() rejected on start:", err));
    },
    [audioFileDict, stopList, setStopList, findNextUnplayedAudio]
  );

  /**
   * Wires up chaining between neighboring audio elements.
   */
  const wireNeighborChaining = useCallback(
    (groupIndex: number, idx: number) => {
      const group = audioFileDict[groupIndex] || {};
      const prevEl = group[idx - 1]?.audio;
      const currEl = group[idx]?.audio;
      if (!currEl) return;

      const session = playSessionRef.current;

      // Clean up blob after element ends
      const src = currEl.src;
      currEl.addEventListener(
        "ended",
        () => {
          try {
            if (src && src.startsWith("blob:")) URL.revokeObjectURL(src);
          } catch {}
        },
        { once: true }
      );

      // If readAlways is ON, useEffect orchestrates sequential playback
      if (readAlways) return;

      // Chain only if both belong to the same session
      if (
        prevEl &&
        (prevEl as HTMLAudioElement & { __session?: number }).__session ===
          (currEl as HTMLAudioElement & { __session?: number }).__session
      ) {
        const playNextOnce = () => {
          if (session !== playSessionRef.current) return;
          currEl.play().catch((err) =>
            console.warn("Audio play() rejected in chain:", err)
          );
        };
        prevEl.addEventListener("ended", playNextOnce, { once: true });

        // Manual fast-path: if prev already finished when current arrives
        if (prevEl.ended && !stopList.includes(groupIndex)) {
          currEl.play().catch((err) =>
            console.warn("Audio play() rejected (prev already ended):", err)
          );
        }
      }
    },
    [audioFileDict, playSessionRef, readAlways, stopList]
  );

  /**
   * Fetches TTS audio for given text.
   */
  const getTTS = useCallback(
    async (text: string, groupIndex: number, sourceFunction: string) => {
      // Only return early if readAlways is false AND this is a pure streaming request
      if (!readAlways && /^stream\d+$/.test(sourceFunction)) return;

      const ttsText = cleanForTTS(text);

      // Handle welcome message with pre-recorded audio
      if (text === chatIslandContent[lang]["welcomeMessage"]) {
        const audioUrl =
          text === chatIslandContent["de"]["welcomeMessage"]
            ? "./intro.mp3"
            : "./intro-en.mp3";

        const audio = new Audio(audioUrl) as HTMLAudioElement & {
          __text?: string;
          __session?: number;
        };
        audio.__text = text;
        audio.__session = playSessionRef.current;

        const sourceFunctionIndex = indexFromSourceFunction(sourceFunction);

        setAudioFileDict((prev) => {
          const next = { ...prev };
          const group = { ...(next[groupIndex] || {}) };
          group[sourceFunctionIndex] = { audio, played: false };
          next[groupIndex] = group;
          return next;
        });

        // Pause other groups
        const newStopList = stopList.slice();
        for (let i = 0; i < groupIndex; i++) {
          const g = audioFileDict[i];
          if (g) {
            Object.values(g).forEach((item) => {
              if (!item.audio.paused) {
                item.audio.pause();
                item.audio.currentTime = 0;
                if (!newStopList.includes(i)) newStopList.push(i);
              }
            });
          }
        }
        setStopList(newStopList);
        return;
      }

      // Queue the TTS fetch
      scheduleTTSJob(async () => {
        try {
          const response = await fetch("/api/tts", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              text: ttsText,
              textPosition: sourceFunction,
              voice: lang === "en" ? "Stefanie" : "Florian",
              ttsKey: settings.ttsKey,
              ttsUrl: settings.ttsUrl,
              ttsModel: settings.ttsModel,
              universalApiKey: settings.universalApiKey,
            }),
          });

          if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
          }

          const contentType = response.headers.get("Content-Type") || "audio/mpeg";
          const audioData = await response.arrayBuffer();
          const audioBlob = new Blob([audioData], { type: contentType });
          const audioUrl = URL.createObjectURL(audioBlob);
          const audio = new Audio(audioUrl) as HTMLAudioElement & {
            __text?: string;
            __session?: number;
          };
          audio.__text = text;
          audio.__session = playSessionRef.current;

          const idx = indexFromSourceFunction(sourceFunction);
          setAudioFileDict((prev) => {
            const next = { ...prev };
            const group = { ...(next[groupIndex] || {}) };
            group[idx] = { audio, played: false };
            next[groupIndex] = group;
            return next;
          });

          wireNeighborChaining(groupIndex, idx);

          audio.addEventListener("ended", () => {
            setAudioFileDict((prev) => {
              const next = { ...prev };
              const group = { ...(next[groupIndex] || {}) };
              const item = { ...(group[idx] || {}) } as AudioItem;
              item.played = true;
              group[idx] = item;
              next[groupIndex] = group;
              return next;
            });
          });
        } catch (error) {
          console.error("Error fetching TTS:", error);
        }
      });
    },
    [
      lang,
      settings,
      readAlways,
      audioFileDict,
      stopList,
      playSessionRef,
      setAudioFileDict,
      setStopList,
      scheduleTTSJob,
      indexFromSourceFunction,
      wireNeighborChaining,
    ]
  );

  /**
   * Speaks a message using smart chunking for better TTS flow.
   */
  const speakMessageInSmartChunks = useCallback(
    (groupIndex: number, fullText: string) => {
      const chunks = splitIntoSmartChunks(fullText);
      if (chunks.length === 0) return;

      // Clear old audios for this group
      setAudioFileDict((prev) => {
        const next = { ...prev };
        next[groupIndex] = {};
        return next;
      });

      // Mark that we should autostart when first chunk arrives
      setPendingManualSpeak((prev) => {
        const cp = new Set(prev);
        cp.add(groupIndex);
        return cp;
      });

      // Fire all chunks concurrently
      chunks.forEach((chunk, i) => {
        getTTS(chunk, groupIndex, `manual_stream${i + 1}`);
      });
    },
    [getTTS, setAudioFileDict, setPendingManualSpeak]
  );

  /**
   * Handles speak action for a specific message group.
   */
  const handleOnSpeakAtGroupIndexAction = useCallback(
    (groupIndex: number, messages: { content: unknown }[]) => {
      if (groupIndex < 0 || groupIndex >= messages.length) return;

      const lastMessage = messages[groupIndex];
      const currentText = Array.isArray(lastMessage?.content)
        ? (lastMessage.content as { type?: string; text?: string }[])
            .filter((c) => c?.type === "text")
            .map((c) => c?.text ?? "")
            .join("")
        : (lastMessage?.content ?? "");

      const text = String(currentText || "").trim();
      if (!text) return;

      if (!audioFileDict[groupIndex]) {
        speakMessageInSmartChunks(groupIndex, text);
        return;
      }

      const firstItem = audioFileDict[groupIndex][0];
      const prevText = firstItem?.audio?.__text ?? "";
      if (text !== String(prevText).trim()) {
        speakMessageInSmartChunks(groupIndex, text);
        return;
      }

      const indexThatIsPlaying = Object.entries(audioFileDict[groupIndex]).findIndex(
        ([_, item]) => !item.audio.paused
      );

      if (indexThatIsPlaying !== -1) {
        // Pause all playing audio
        Object.values(audioFileDict).forEach((group) => {
          Object.values(group).forEach((item) => {
            if (!item.audio.paused) {
              item.audio.pause();
              item.audio.currentTime = 0;
            }
          });
        });

        setStopList([...stopList, groupIndex]);
        setAudioFileDict({ ...audioFileDict });
      } else {
        setStopList(stopList.filter((item) => item !== groupIndex));
        // Pause all and restart
        Object.values(audioFileDict).forEach((group) => {
          Object.values(group).forEach((item) => {
            if (!item.audio.paused) {
              item.audio.pause();
              item.audio.currentTime = 0;
            }
          });
        });

        startOrderedPlaybackForGroup(groupIndex);
      }
    },
    [
      audioFileDict,
      stopList,
      setStopList,
      setAudioFileDict,
      speakMessageInSmartChunks,
      startOrderedPlaybackForGroup,
    ]
  );

  return {
    getTTS,
    playAudio,
    findNextUnplayedAudio,
    canPlayAudio,
    startOrderedPlaybackForGroup,
    wireNeighborChaining,
    stopAndResetAudio,
    toggleReadAlways,
    speakMessageInSmartChunks,
    handleOnSpeakAtGroupIndexAction,
    clearGroupAudio,
    indexFromSourceFunction,
    scheduleTTSJob,
  };
};
