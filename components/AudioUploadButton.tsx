/**
 * @file AudioUploadButton.tsx
 * @description Button component for uploading audio files (MP3, WAV, OGG, etc.)
 *              for transcription via the STT API. Shows upload status and handles
 *              the transcription workflow.
 * @importantFunctions AudioUploadButton
 */

import { useRef, useState } from "preact/hooks";
import { IS_BROWSER } from "$fresh/runtime.ts";

// Supported audio formats for transcription
const ACCEPTED_AUDIO_FORMATS = [
  "audio/mpeg",      // MP3
  "audio/mp3",       // MP3 alternative
  "audio/wav",       // WAV
  "audio/wave",      // WAV alternative
  "audio/x-wav",     // WAV alternative
  "audio/ogg",       // OGG
  "audio/flac",      // FLAC
  "audio/x-flac",    // FLAC alternative
  "audio/mp4",       // M4A/MP4 audio
  "audio/x-m4a",     // M4A
  "audio/aac",       // AAC
  "audio/webm",      // WebM audio
].join(",");

// File extension list for accept attribute
const ACCEPTED_EXTENSIONS = ".mp3,.wav,.ogg,.flac,.m4a,.aac,.webm,.mp4";

interface AudioUploadButtonProps {
  onTranscriptionComplete: (transcription: string, fileName: string) => void;
  onTranscriptionStart?: () => void;
  onTranscriptionError?: (error: string) => void;
  sttUrl: string;
  sttKey: string;
  sttModel: string;
  universalApiKey: string;
  disabled?: boolean;
}

/**
 * Audio upload button component that handles file selection,
 * transcription via STT API, and returns the result.
 */
function AudioUploadButton({
  onTranscriptionComplete,
  onTranscriptionStart,
  onTranscriptionError,
  sttUrl,
  sttKey,
  sttModel,
  universalApiKey,
  disabled = false,
}: AudioUploadButtonProps) {
  const [isTranscribing, setIsTranscribing] = useState(false);
  const [currentFileName, setCurrentFileName] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const onButtonClick = () => {
    if (!isTranscribing) {
      fileInputRef.current?.click();
    }
  };

  const handleAudioUpload = async (event: Event) => {
    const target = event.target as HTMLInputElement;
    const file = target.files?.[0];

    if (!file) return;

    // Validate file type
    const isValidType = file.type.startsWith("audio/") ||
      /\.(mp3|wav|ogg|flac|m4a|aac|webm|mp4)$/i.test(file.name);

    if (!isValidType) {
      onTranscriptionError?.("Please select a valid audio file (MP3, WAV, OGG, FLAC, M4A, AAC, or WebM)");
      return;
    }

    // Check file size (limit to 25MB for most STT APIs)
    const maxSize = 25 * 1024 * 1024; // 25MB
    if (file.size > maxSize) {
      onTranscriptionError?.("Audio file is too large. Maximum size is 25MB.");
      return;
    }

    setCurrentFileName(file.name);
    setIsTranscribing(true);
    onTranscriptionStart?.();

    try {
      const transcription = await transcribeAudio(file);
      onTranscriptionComplete(transcription, file.name);
    } catch (error) {
      console.error("Transcription error:", error);
      onTranscriptionError?.(
        error instanceof Error ? error.message : "Failed to transcribe audio"
      );
    } finally {
      setIsTranscribing(false);
      setCurrentFileName(null);
      // Reset file input so the same file can be selected again
      if (fileInputRef.current) {
        fileInputRef.current.value = "";
      }
    }
  };

  const transcribeAudio = async (file: File): Promise<string> => {
    const formData = new FormData();
    formData.append("audio", file, file.name);

    // Configure STT settings
    let useThisSttUrl = sttUrl;
    let useThisSttModel = sttModel;

    // Handle Groq API key
    if (sttKey.startsWith("gsk_")) {
      useThisSttUrl = sttUrl || "https://api.groq.com/openai/v1/audio/transcriptions";
      useThisSttModel = sttModel || "whisper-large-v3-turbo";
    }

    formData.append("sttUrl", useThisSttUrl);
    formData.append("sttKey", sttKey);
    formData.append("sttModel", useThisSttModel);
    formData.append("universalApiKey", universalApiKey);

    const response = await fetch("/api/stt", {
      method: "POST",
      body: formData,
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => "Unknown error");
      throw new Error(`Transcription failed: ${errorText}`);
    }

    const transcription = await response.text();

    if (!transcription || transcription.trim() === "") {
      throw new Error("Received empty transcription");
    }

    return transcription;
  };

  const buttonTitle = isTranscribing
    ? `Transcribing: ${currentFileName}`
    : "Upload audio file for transcription";

  return (
    <>
      <input
        type="file"
        ref={fileInputRef}
        onChange={handleAudioUpload}
        accept={`${ACCEPTED_AUDIO_FORMATS},${ACCEPTED_EXTENSIONS}`}
        class="hidden"
        disabled={disabled || isTranscribing}
      />
      <button
        onClick={onButtonClick}
        disabled={!IS_BROWSER || disabled || isTranscribing}
        class={`md:absolute md:right-3 md:bottom-[7rem] disabled:opacity-50 disabled:cursor-not-allowed rounded-md p-2 bg-gray-100
          ${isTranscribing ? "animate-pulse bg-orange-100" : ""}`}
        title={buttonTitle}
      >
        {isTranscribing ? (
          // Loading spinner icon
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            class="icon text-orange-600 animate-spin"
          >
            <path stroke="none" d="M0 0h24v24H0z" fill="none" />
            <path d="M12 3a9 9 0 1 0 9 9" />
          </svg>
        ) : (
          // Audio file upload icon
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            class="icon text-blue-600/50"
          >
            <path stroke="none" d="M0 0h24v24H0z" fill="none" />
            {/* Music note / audio file icon */}
            <path d="M14 3v4a1 1 0 0 0 1 1h4" />
            <path d="M17 21h-10a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2h7l5 5v11a2 2 0 0 1 -2 2z" />
            <path d="M11 16m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0" />
            <path d="M13 16v-5l2 1" />
          </svg>
        )}
      </button>
    </>
  );
}

export default AudioUploadButton;
