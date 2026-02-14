/**
 * @file PdfUploadButton.tsx
 * @description Button component for uploading PDF files with progress tracking.
 *              Converts PDFs to base64 for inclusion in chat messages.
 * @importantFunctions PdfUploadButton, handlePdfUpload
 */

import { useRef, useState } from "preact/hooks";
import { IS_BROWSER } from "$fresh/runtime.ts";

export interface PdfFile {
  type: "pdf";
  name: string;
  mime_type: string;
  data: string; // base64
}

type Variant = "floating" | "inline";

export function PdfUploadButton({
  onPdfsUploaded,
  variant = "floating",
}: {
  onPdfsUploaded: (pdfs: PdfFile[]) => void;
  variant?: Variant;
}) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);

  const clearInput = () => { if (fileInputRef.current) fileInputRef.current.value = ""; };
  const onButtonClick = () => { clearInput(); fileInputRef.current?.click(); };

  /**
   * Converts a file to base64 with progress tracking.
   */
  const fileToBase64 = (file: File, onProgress?: (percent: number) => void) => new Promise<string>((resolve, reject) => {
    const reader = new FileReader();

    reader.onprogress = (e) => {
      if (e.lengthComputable && onProgress) {
        const percent = (e.loaded / e.total) * 100;
        onProgress(percent);
      }
    };

    reader.onload = () => {
      const dataUrl = String(reader.result || "");
      const commaIdx = dataUrl.indexOf(",");
      if (commaIdx === -1) return reject(new Error("Invalid DataURL"));
      resolve(dataUrl.slice(commaIdx + 1));
    };
    reader.onerror = () => reject(reader.error || new Error("FileReader error"));
    reader.onabort = () => reject(new Error("File read aborted"));
    reader.readAsDataURL(file);
  });

  /**
   * Handles PDF file upload with progress tracking.
   */
  const handlePdfUpload = async (event: Event) => {
    try {
      if (busy) return;
      setBusy(true);
      setUploadProgress(0);

      const target = event.target as HTMLInputElement;
      const list = target?.files;
      if (!list || list.length === 0) { clearInput(); setBusy(false); return; }

      const seen = new Set<string>();
      const files = Array.from(list).filter((f) => {
        const key = `${f.name}|${f.size}|${f.lastModified}`;
        const isPdf = f.type === "application/pdf" || f.name.toLowerCase().endsWith(".pdf");
        if (!isPdf || seen.has(key)) return false;
        seen.add(key);
        return true;
      });

      const uploaded: PdfFile[] = [];
      const totalFiles = files.length;

      for (let i = 0; i < files.length; i++) {
        const f = files[i];
        const base64 = await fileToBase64(f, (filePercent) => {
          // Calculate overall progress across all files
          const overallProgress = ((i * 100) + filePercent) / totalFiles;
          setUploadProgress(Math.round(overallProgress));
        });
        uploaded.push({ type: "pdf", name: f.name, mime_type: f.type || "application/pdf", data: base64 });
        // Update progress after each file completes
        setUploadProgress(Math.round(((i + 1) / totalFiles) * 100));
      }

      if (uploaded.length) onPdfsUploaded(uploaded);
    } catch (e) {
      console.error("PDF upload failed:", e);
    } finally {
      clearInput();
      setBusy(false);
      setUploadProgress(0);
    }
  };

  const pos = variant === "floating"
    ? "md:absolute md:right-3 md:bottom-[13rem]"
    : "relative";

  return (
    <>
      <input
        type="file" ref={fileInputRef} onChange={handlePdfUpload}
        accept="application/pdf" multiple class="hidden"
      />
      <div class={`${pos} relative`}>
        <button
          onClick={onButtonClick} disabled={!IS_BROWSER || busy}
          class="disabled:opacity-50 disabled:cursor-not-allowed rounded-md p-2 bg-gray-100 text-blue-600/50 hover:bg-gray-200 transition-colors"
          title={busy ? "Uploading PDFs..." : "Select PDF(s)"}
        >
          {busy ? (
            /* Loading spinner during upload */
            <svg class="animate-spin" xmlns="http://www.w3.org/2000/svg" width="24" height="24"
                 viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-opacity="0.25" />
              <path d="M12 2a10 10 0 0 1 10 10" stroke="currentColor" stroke-linecap="round" />
            </svg>
          ) : (
            /* PDF icon */
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"
              viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"
              stroke-linecap="round" stroke-linejoin="round"
              class="icon icon-tabler icon-tabler-file-type-pdf">
              <path stroke="none" d="M0 0h24v24H0z" fill="none"/>
              <path d="M14 3v4a1 1 0 0 0 1 1h4" />
              <path d="M5 12v-7a2 2 0 0 1 2 -2h7l5 5v4" />
              <path d="M5 18h1.5a1.5 1.5 0 0 0 0 -3h-1.5v6" />
              <path d="M17 18h2" /><path d="M20 15h-3v6" />
              <path d="M11 15v6h1a2 2 0 0 0 2 -2v-2a2 2 0 0 0 -2 -2h-1z" />
            </svg>
          )}
        </button>

        {/* Progress bar overlay during upload */}
        {busy && (
          <div class="absolute -bottom-1 left-0 right-0 h-1 bg-gray-200 rounded-full overflow-hidden">
            <div
              class="h-full bg-blue-500 transition-all duration-200"
              style={{ width: `${uploadProgress}%` }}
            />
          </div>
        )}
      </div>
    </>
  );
}

export default PdfUploadButton;
