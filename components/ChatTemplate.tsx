/**
 * @file ChatTemplate.tsx
 * @description Chat message display component with support for multimodal content
 *              (text, images with unique IDs, PDFs), audio playback, message editing,
 *              and auto-scroll functionality.
 * @importantFunctions ChatTemplate, MessageToolbar, renderContentPart
 */

import { useEffect } from "preact/hooks";
import { chatTemplateContent } from "../internalization/content.ts";


/* ---------- helpers ---------- */
function downloadAudioFiles(
  items: { [key: string]: { audio: HTMLAudioElement } },
) {
  const ts = new Date().toISOString().slice(0, 19).replace(/[-:]/g, "-");

  if (Object.keys(items).length === 1) {
    const single = Object.values(items)[0].audio;
    fetch(single.src).then((r) => r.blob()).then((blob) => {
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `audio-${ts}.mp3`;
      a.click();
      URL.revokeObjectURL(url);
    });
    return;
  }

  Promise.all(
    Object.values(items).map((i) => fetch(i.audio.src).then((r) => r.blob())),
  ).then((blobs) => {
    const url = URL.createObjectURL(new Blob(blobs, { type: "audio/mp3" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `audio-${ts}.mp3`;
    a.click();
    URL.revokeObjectURL(url);
  });
}

function convertDoiToUrl(doi: string): string {
  const clean = doi.replace(/^DOI:\s*/, "");
  return clean === "null" ? "#" : `https://doi.org/${clean}`;
}

// **Bold** + Links + DOI minimal robust
function renderTextWithLinksAndBold(text: string) {
  const re =
    /(https?:\/\/[^\s]+|www\.[^\s]+|DOI:\s*(?:null|[\d.]+\/[^\s]+)|\*\*.*?\*\*)/g;

  const parts = text.split(re).filter((p) => p !== "");
  return parts.map((part, i) => {
    // bold
    if (part.startsWith("**") && part.endsWith("**")) {
      return <strong key={i}>{part.slice(2, -2)}</strong>;
    }

    // DOI
    if (/^DOI:\s*/.test(part)) {
      const href = convertDoiToUrl(part);
      return (
        <a key={i} href={href} class="text-blue-600 underline" target="_blank">
          {part}
        </a>
      );
    }

    // Links
    if (/^https?:\/\//.test(part) || /^www\./.test(part)) {
      const href = part.startsWith("http") ? part : `https://${part}`;
      return (
        <a key={i} href={href} class="text-blue-600 underline" target="_blank">
          {part}
        </a>
      );
    }

    return <span key={i}>{part}</span>;
  });
}

/* ---------- message toolbar (Edit/Refresh/Speak/Download) ---------- */
function MessageToolbar(props: {
  index: number;
  role: string;
  hasAudio: boolean;
  onEdit: (i: number) => void;
  onRefresh: (i: number) => void;
  onSpeak: (i: number) => void;
  onDownload: (i: number) => void;
}) {
  const { index, role, hasAudio, onEdit, onRefresh, onSpeak, onDownload } =
    props;
  const isAssistant = role !== "user";

  return (
    <div class="flex items-center gap-2 text-gray-600">
      {/* Edit user message */}
      {!isAssistant && (
        <button
          class="hover:text-gray-800"
          title="Edit message"
          onClick={() => onEdit(index)}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="18"
            height="18"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
          >
            <path d="M12 20h9" />
            <path d="M16.5 3.5a2.121 2.121 0 1 1 3 3L7 19l-4 1 1-4Z" />
          </svg>
        </button>
      )}

      {isAssistant && (
        <>
          {/* Edit assistant message */}
          <button
            class="hover:text-gray-800"
            title="Edit message"
            onClick={() => onEdit(index)}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
            >
              <path d="M12 20h9" />
              <path d="M16.5 3.5a2.121 2.121 0 1 1 3 3L7 19l-4 1 1-4Z" />
            </svg>
          </button>

          {/* Re-run */}
          <button
            class="hover:text-gray-800"
            title="Re-run from this turn"
            onClick={() => onRefresh(index)}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
            >
              <path d="M21 12a9 9 0 1 1-3-6.7" />
              <path d="M21 3v6h-6" />
            </svg>
          </button>

          {/* Speak */}
          <button
            class="hover:text-gray-800"
            title="Speak this turn"
            onClick={() => onSpeak(index)}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
            >
              <path d="M11 5 6 9H2v6h4l5 4z" />
              <path d="M15.54 8.46a5 5 0 0 1 0 7.07" />
              <path d="M19.07 4.93a10 10 0 0 1 0 14.14" />
            </svg>
          </button>

          {/* Download audio */}
          {hasAudio && (
            <button
              class="hover:text-gray-800"
              title="Download audio"
              onClick={() => onDownload(index)}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
              >
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                <path d="M7 10l5 5 5-5" />
                <path d="M12 15V3" />
              </svg>
            </button>
          )}
        </>
      )}
    </div>
  );
}

/* ---------- component ---------- */
type AnyMsg = any;
type AnyImg = any;
type AnyPdf = any;
type AnyAudio = any;

export default function ChatTemplate(props: {
  lang: string;
  parentImages: AnyImg[];
  parentPdfs: AnyPdf[];
  messages: AnyMsg[];
  isComplete: boolean;
  onCancelAction: () => void;
  readAlways: boolean;
  autoScroll: boolean;
  currentEditIndex: number;
  audioFileDict: AnyAudio;

  onToggleAutoScrollAction: () => void;
  onToggleReadAlwaysAction: () => void;

  onSpeakAtGroupIndexAction: (groupIndex: number) => void;
  onRefreshAction: (groupIndex: number) => void;
  onEditAction: (groupIndex: number) => void;

  onUploadActionToMessages: (uploadedMessages: AnyMsg[]) => void;
  onImageChange: (images: AnyImg[]) => void;
  onPdfChange?: (pdfs: AnyPdf[]) => void;
  onTrashAction: () => void;
}) {
  const {
    lang,
    parentImages,
    parentPdfs,
    messages,
    isComplete,
    onCancelAction,
    readAlways,
    autoScroll,
    audioFileDict,
    currentEditIndex,
    onToggleAutoScrollAction,
    onToggleReadAlwaysAction,
    onImageChange,
    onPdfChange,
    onSpeakAtGroupIndexAction,
    onRefreshAction,
    onEditAction,
  } = props;

  const deleteImage = (iDel: number) => {
    const next = parentImages.filter((_: AnyImg, i: number) => i !== iDel);
    onImageChange(next);
  };

  const deletePdf = (iDel: number) => {
    const next = parentPdfs.filter((_: AnyPdf, i: number) => i !== iDel);
    if (onPdfChange) onPdfChange(next);
  };

  const renderContentPart = (content: any, idx: number) => {
    if (content?.type === "text") {
      return <span key={idx}>{renderTextWithLinksAndBold(content.text)}</span>;
    }
    if (content?.type === "image_url") {
      const imageId = content.id || null;

      // Determine source from content.source, or infer from ID prefix
      let imageSource = content.source;
      if (!imageSource && imageId) {
        if (imageId.startsWith("gen_") || imageId.startsWith("img_")) {
          imageSource = "generated";
        } else if (imageId.startsWith("upl_")) {
          imageSource = "uploaded";
        }
      }
      // Fallback: assume generated if it's a data URL with no other indicators
      if (!imageSource) {
        imageSource = content.image_url?.url?.startsWith("data:image") ? "generated" : "uploaded";
      }

      // Format display name for the badge
      const displayLabel = imageSource === "generated" ? "Generated" : "Uploaded";
      const badgeColor = imageSource === "generated" ? "bg-purple-500/70" : "bg-blue-500/70";

      return (
        <div key={idx} class="relative inline-block">
          <img
            src={content.image_url.url}
            alt={`${displayLabel} image${imageId ? ` (${imageId})` : ""}`}
            class="max-w-[400px] w-full h-auto rounded-lg shadow-md cursor-pointer hover:shadow-lg transition-shadow"
            onClick={() => {
              // Open image in new tab for full view
              const win = window.open();
              if (win) {
                win.document.write(`<img src="${content.image_url.url}" style="max-width:100%;height:auto;" />`);
                win.document.title = imageId || displayLabel + " Image";
              }
            }}
          />
          {/* Image ID Badge - shown in corner for reference */}
          {imageId && (
            <div
              class="absolute bottom-2 left-2 bg-black/60 text-white text-xs px-2 py-1 rounded font-mono cursor-pointer hover:bg-black/80"
              title={`Image ID: ${imageId} (click to copy)`}
              onClick={(e) => {
                e.stopPropagation();
                navigator.clipboard.writeText(imageId);
                // Visual feedback
                const el = e.target as HTMLElement;
                const original = el.textContent;
                el.textContent = "Copied!";
                setTimeout(() => { el.textContent = original; }, 1000);
              }}
            >
              {imageId}
            </div>
          )}
          {/* Source indicator */}
          <div class={`absolute top-2 right-2 text-xs px-2 py-0.5 rounded ${badgeColor} text-white`}>
            {displayLabel}
          </div>
        </div>
      );
    }
    if (content?.type === "pdf") {
      return (
        <div
          key={idx}
          class="flex items-center gap-2 p-2 bg-gray-200 rounded-md"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="text-red-700"
          >
            <path stroke="none" d="M0 0h24v24H0z" fill="none" />
            <path d="M14 3v4a1 1 0 0 0 1 1h4" />
            <path d="M5 12v-7a2 2 0 0 1 2 -2h7l5 5v4" />
            <path d="M5 18h1.5a1.5 1.5 0 0 0 0 -3h-1.5v6" />
            <path d="M17 18h2" />
            <path d="M20 15h-3v6" />
            <path d="M11 15v6h1a2 2 0 0 0 2 -2v-2a2 2 0 0 0 -2 -2h-1z" />
          </svg>
          <span class="font-mono text-sm">{content.name}</span>
        </div>
      );
    }
    if (typeof content === "string") {
      return <span key={idx}>{renderTextWithLinksAndBold(content)}</span>;
    }
    return null;
  };

  useEffect(() => {}, []);

  return (
    <div class="relative">
      {/* Fixed toolbar: on desktop absolute top-right; on mobile stacked above chat */}
      <div
        class="
          z-20 w-full flex flex-wrap items-center gap-2 justify-center mb-2
          md:w-auto md:absolute md:-top-12 md:right-0 md:justify-end md:mb-0
        "
      >

        {!isComplete && (
          <button
            type="button"
            onClick={onCancelAction}
            class="px-3 py-1 rounded text-sm border bg-red-600 text-white border-red-600 hover:bg-red-700"
            title="Cancel generation"
          >
            Cancel
          </button>
        )}

        <button
          type="button"
          onClick={onToggleReadAlwaysAction}
          class={`px-3 py-1 rounded text-sm border transition
            ${
              readAlways
                ? "bg-blue-600 text-white border-blue-600"
                : "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
            }`}
          title={chatTemplateContent[lang]?.readOutText ?? "Vorlesen"}
        >
          {readAlways
            ? (chatTemplateContent[lang]?.silent ?? "Stumm")
            : (chatTemplateContent[lang]?.readOutText ?? "Vorlesen")}
        </button>

        <button
          type="button"
          onClick={onToggleAutoScrollAction}
          class={`px-3 py-1 rounded text-sm border transition
            ${
              autoScroll
                ? "bg-green-600 text-white border-green-600"
                : "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
            }`}
          title={
            autoScroll
              ? (chatTemplateContent[lang]?.autoScrollOn ??
                "Automatisch scrollen: AN")
              : (chatTemplateContent[lang]?.autoScrollOff ??
                "Automatisch scrollen: AUS")
          }
        >
          {autoScroll
            ? (chatTemplateContent[lang]?.autoScrollOn ??
              "Automatisch scrollen")
            : (chatTemplateContent[lang]?.autoScrollOff ?? "Manuell scrollen")}
        </button>
      </div>

      <div
        class={
          messages?.length === 0
            ? `bg-transparent`
            : `chat-history w-full flex flex-col space-y-4 p-4 mx-auto rounded-lg shadow bg-white/75 max-h-[55vh] sm:max-h-[60vh] overflow-y-auto`
        }

      >
        {messages?.map((item: AnyMsg, groupIndex: number) => {
          const isUser = item.role === "user";
          const hasAudio =
            !!(audioFileDict?.[groupIndex]) &&
            Object.keys(audioFileDict[groupIndex]).length > 0;

          return (
            <div
              key={groupIndex}
              class={`message-group relative flex flex-col ${
                isUser ? "items-end" : "items-start"
              }`}
            >
              {/* Per-message toolbar:
                 - Mobile: relativ & unter der Bubble, gestapelt
                 - ≥ md: wie zuvor absolut links/rechts über der Bubble */}
              <div
                class={`
                  z-20 flex flex-wrap gap-2 justify-end mb-1
                  md:absolute md:-top-3 ${isUser ? "md:right-1" : "md:left-1"}
                `}
              >
                <MessageToolbar
                  index={groupIndex}
                  role={item.role}
                  hasAudio={!isUser && hasAudio}
                  onEdit={onEditAction}
                  onRefresh={onRefreshAction}
                  onSpeak={onSpeakAtGroupIndexAction}
                  onDownload={(i) => downloadAudioFiles(audioFileDict[i])}
                />
              </div>

              {/* Message bubble */}
              <div
                class={`message mt-1 whitespace-pre-wrap [overflow-wrap:anywhere] ${
                  isUser
                    ? "bg-blue-100 sm:ml-20 md:ml-40"
                    : "bg-gray-100 sm:mr-20 md:mr-40"
                } p-3 rounded-lg ${
                  isUser ? "rounded-tr-none" : "rounded-tl-none"
                } shadow ${
                  isUser && currentEditIndex === groupIndex
                    ? "ring-2 ring-orange-300"
                    : ""
                }`}
              >
                {typeof item.content === "string"
                  ? <span>{renderTextWithLinksAndBold(item.content)}</span>
                  : (
                    <div class="flex flex-col gap-2">
                      {(item.content as any[]).map((content, idx) =>
                        renderContentPart(content, idx)
                      )}
                    </div>
                  )}
              </div>
            </div>
          );
        })}

        {(parentImages?.length > 0 || parentPdfs?.length > 0) && (
          <div class="w-full flex justify-center">
            <div class="p-2 flex flex-wrap max-w-xs gap-4">
              {parentImages.map((image: AnyImg, index: number) => (
                <div class="relative group" key={`img-${index}`}>
                  <img
                    src={image.image_url.url}
                    alt={`Thumbnail ${index + 1}`}
                    class="w-32 h-32 object-cover rounded-lg shadow-xl bg-white/50"
                  />
                  <button
                    onClick={() => deleteImage(index)}
                    class="absolute top-1 right-1 bg-red-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity"
                    title="Entfernen"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      width="16"
                      height="16"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                    >
                      <path d="M18 6l-12 12" />
                      <path d="M6 6l12 12" />
                    </svg>
                  </button>
                </div>
              ))}

              {parentPdfs.map((pdf: AnyPdf, index: number) => (
                <div
                  key={`pdf-${index}`}
                  class="relative group w-32 h-32 flex flex-col items-center justify-center bg-gray-200 rounded-lg shadow-xl p-2 text-center"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="48"
                    height="48"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    class="text-red-700 mb-2"
                  >
                    <path stroke="none" d="M0 0h24v24H0z" fill="none" />
                    <path d="M14 3v4a1 1 0 0 0 1 1h4" />
                    <path d="M5 12v-7a2 2 0 0 1 2 -2h7l5 5v4" />
                    <path d="M5 18h1.5a1.5 1.5 0 0 0 0 -3h-1.5v6" />
                    <path d="M17 18h2" />
                    <path d="M20 15h-3v6" />
                    <path d="M11 15v6h1a2 2 0 0 0 2 -2v-2a2 2 0 0 0 -2 -2h-1z" />
                  </svg>
                  <span class="text-xs font-mono break-all overflow-hidden">
                    {pdf.name}
                  </span>
                  <button
                    onClick={() => deletePdf(index)}
                    class="absolute top-1 right-1 bg-red-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity"
                    title="Entfernen"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      width="16"
                      height="16"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                    >
                      <path d="M18 6l-12 12" />
                      <path d="M6 6l12 12" />
                    </svg>
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
