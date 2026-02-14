import { useEffect, useRef, useState } from "preact/hooks";
import { IS_BROWSER } from "$fresh/runtime.ts";

/**
 * VoiceRecordButton component.
 *
 * @component
 * @param {Object} props
 * @param {Function} props.onFinishRecording
 * @param {Function} props.onInterimTranscript
 * @param {number} props.resetTranscript
 * @param {string} props.sttUrl
 * @param {string} props.sttKey
 * @param {string} props.sttModel
 * @param {string} props.universalApiKey
 */
function VoiceRecordButton({
  onFinishRecording,
  onInterimTranscript,
  resetTranscript,
  sttUrl,
  sttKey,
  sttModel,
  universalApiKey,
}: {
  onFinishRecording: (transcript: string) => void;
  onInterimTranscript: (transcript: string) => void;
  resetTranscript: number;
  sttUrl: string;
  sttKey: string;
  sttModel: string;
  universalApiKey: string;
}) {
  const [isRecording, setIsRecording] = useState(false);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const recognitionRef = useRef<SpeechRecognition | null>(null);

  // deno-lint-ignore no-explicit-any
  (globalThis as any).SpeechRecognition =
    // deno-lint-ignore no-explicit-any
    (globalThis as any).SpeechRecognition ||
    // deno-lint-ignore no-explicit-any
    (globalThis as any).webkitSpeechRecognition;

  useEffect(() => {
    if (resetTranscript > 0) {
      console.log("Resetting transcript due to reset signal change.");
    }
    restartRecording();
  }, [resetTranscript]);

  function restartRecording() {
    if (recognitionRef.current) {
      recognitionRef.current.onend = null;
      recognitionRef.current.stop();
      // deno-lint-ignore no-explicit-any
      recognitionRef.current = new (globalThis as any).SpeechRecognition();
      (recognitionRef.current as SpeechRecognition).continuous = false;
      (recognitionRef.current as SpeechRecognition).lang = "de-DE";
      (recognitionRef.current as SpeechRecognition).interimResults = true;
      (recognitionRef.current as SpeechRecognition).onend = onEnd;
      (recognitionRef.current as SpeechRecognition).addEventListener(
        "result",
        onSpeak,
      );
      (recognitionRef.current as SpeechRecognition).start();
      setIsRecording(true);
    }
  }

  async function toggleRecording() {
    if (isRecording) {
      mediaRecorderRef.current?.stop();
      setIsRecording(false);
    } else {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mediaRecorder = new MediaRecorder(stream);
      mediaRecorderRef.current = mediaRecorder;

      mediaRecorder.ondataavailable = (event) => {
        audioChunksRef.current.push(event.data);
      };

      mediaRecorder.onstop = async () => {
        const audioBlob = new Blob(audioChunksRef.current, {
          type: "audio/wav",
        });
        audioChunksRef.current = [];
        await sendAudioToServer(audioBlob);
      };

      mediaRecorder.start();
      setIsRecording(true);
    }
  }

  const sendAudioToServer = async (audioBlob: Blob) => {
    const formData = new FormData();
    formData.append("audio", audioBlob, "recording.wav");

    if (sttKey.startsWith("gsk_")) {
      sttUrl = sttUrl == ""
        ? "https://api.groq.com/openai/v1/audio/transcriptions"
        : sttUrl;
      sttModel = sttModel == "" ? "whisper-large-v3-turbo" : sttModel;
    }

    formData.append("sttUrl", sttUrl);
    formData.append("sttKey", sttKey);
    formData.append("sttModel", sttModel);
    formData.append("universalApiKey", universalApiKey);

    try {
      const response = await fetch("/api/stt", {
        method: "POST",
        body: formData,
      });

      if (response.ok) {
        console.log("Audio uploaded successfully");
        const text = await response.text();
        console.log("Text from VoiceRecordButton:", text);
        onFinishRecording(text);
      } else {
        console.error("Failed to upload audio");
      }
    } catch (error) {
      console.error("Error uploading audio:", error);
    }
  };

  function onEnd() {
    console.log("Speech recognition has stopped. Starting again .");
    setIsRecording(false);
  }

  const prependToTranscript = "";
  // deno-lint-ignore no-explicit-any
  function onSpeak(event: any) {
    let interimTranscript = "";
    for (let i = event.resultIndex; i < event.results.length; ++i) {
      if (event.results[i].isFinal) {
        console.log("Final transcript: ", event.results[i][0].transcript);
        interimTranscript = event.results[i][0].transcript;
      } else {
        interimTranscript += event.results[i][0].transcript;
      }
    }
    if (interimTranscript) {
      console.log("Interim transcript: ", prependToTranscript);
      onInterimTranscript(prependToTranscript + interimTranscript);
    }
  }

  return (
    <button
      onClick={toggleRecording}
      disabled={!IS_BROWSER}
      class={`absolute right-3 bottom-[4rem] disabled:opacity-50 disabled:cursor-not-allowed rounded-md p-2 bg-gray-100
        ${isRecording ? "animate-pulse bg-red-600" : ""}`}
      title={isRecording ? "Aufnahme läuft" : "Sprache aufnehmen"}
    >
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
        class={`icon icon-tabler icons-tabler-outline icon-tabler-microphone ${
          isRecording ? "text-white" : "text-blue-600"
        }`}
      >
        <path stroke="none" d="M0 0h24v24H0z" fill="none" />
        <path d="M9 2m0 3a3 3 0 0 1 3 -3h0a3 3 0 0 1 3 3v5a3 3 0 0 1 -3 3h0a3 3 0 0 1 -3 -3z" />
        <path d="M5 10a7 7 0 0 0 14 0" />
        <path d="M8 21l8 0" />
        <path d="M12 17l0 4" />
      </svg>
    </button>
  );
}

export default VoiceRecordButton;
