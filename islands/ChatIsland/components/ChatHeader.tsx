/**
 * @file ChatHeader.tsx
 * @description Header component for the chat interface containing chat tabs,
 *              settings button, and chat management controls.
 * @importantFunctions ChatHeader
 */

import { chatIslandContent } from "../../../internalization/content.ts";

interface ChatHeaderProps {
  lang: string;
  localStorageKeys: string[];
  currentChatSuffix: string;
  onChatSelect: (suffix: string) => void;
  onSettingsClick: () => void;
  onNewChat: () => void;
  onDeleteCurrentChat: () => void;
  onDeleteAllChats: () => void;
  onSaveChats: () => void;
  onRestoreChats: (e: Event) => void;
}

/**
 * Settings gear icon SVG
 */
const SettingsIcon = () => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    height="24"
    viewBox="0 -960 960 960"
    width="24"
  >
    <path d="m370-80-16-128q-13-5-24.5-12T307-235l-119 50L78-375l103-78q-1-7-1-13.5v-27q0-6.5 1-13.5L78-585l110-190 119 50q11-8 23-15t24-12l16-128h220l16 128q13 5 24.5 12t22.5 15l119-50 110 190-103 78q1 7 1 13.5v27q0 6.5-2 13.5l103 78-110 190-118-50q-11 8-23 15t-24 12L590-80H370Zm112-260q58 0 99-41t41-99q0-58-41-99t-99-41q-58 0-99 41t-41 99q0 58 41 99t99 41Z" />
  </svg>
);

/**
 * Delete file icon SVG
 */
const DeleteFileIcon = () => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    className="inline-block"
    height="24px"
    viewBox="0 -960 960 960"
    width="24px"
    fill="#000000"
  >
    <path d="M240-800v200-200 640-9.5 9.5-640Zm0 720q-33 0-56.5-23.5T160-160v-640q0-33 23.5-56.5T240-880h320l240 240v174q-19-7-39-10.5t-41-3.5v-120H520v-200H240v640h254q8 23 20 43t28 37H240Zm396-20-56-56 84-84-84-84 56-56 84 84 84-84 56 56-83 84 83 84-56 56-84-83-84 83Z" />
  </svg>
);

/**
 * Download icon SVG
 */
const DownloadIcon = () => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    className="inline"
    height="24px"
    viewBox="0 -960 960 960"
    width="24px"
    fill="#000000"
  >
    <path d="M480-320 280-520l56-58 104 104v-326h80v326l104-104 56 58-200 200ZM240-160q-33 0-56.5-23.5T160-240v-120h80v120h480v-120h80v120q0 33-23.5 56.5T720-160H240Z" />
  </svg>
);

/**
 * Upload icon SVG
 */
const UploadIcon = () => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    className="inline"
    height="24px"
    viewBox="0 -960 960 960"
    width="24px"
    fill="#000000"
  >
    <path d="M440-200h80v-167l64 64 56-57-160-160-160 160 57 56 63-63v167ZM240-80q-33 0-56.5-23.5T160-160v-640q0-33 23.5-56.5T240-880h320l240 240v480q0 33-23.5 56.5T720-80H240Zm280-520v-200H240v640h480v-440H520ZM240-800v-200 200-640-640Z" />
  </svg>
);

/**
 * Chat header component with chat selection and management controls.
 */
export const ChatHeader = ({
  lang,
  localStorageKeys,
  currentChatSuffix,
  onChatSelect,
  onSettingsClick,
  onNewChat,
  onDeleteCurrentChat,
  onDeleteAllChats,
  onSaveChats,
  onRestoreChats,
}: ChatHeaderProps) => {
  const content = chatIslandContent[lang];

  return (
    <div className="flex items-center mb-4 flex-wrap">
      {/* Settings button */}
      <button
        className="rounded-full bg-slate-200 px-4 py-2 mx-2 mb-2"
        onClick={onSettingsClick}
      >
        <SettingsIcon />
      </button>

      {/* Chat tabs */}
      {[...localStorageKeys]
        .sort((a, b) => Number(a.slice(10)) - Number(b.slice(10)))
        .map((key) => {
          const chatSuffix = key.substring(10);
          return (
            <button
              key={key}
              className={`rounded-full ${
                chatSuffix === currentChatSuffix
                  ? "bg-slate-400 text-white font-bold"
                  : "bg-slate-200"
              } px-4 py-2 mx-2 mb-2`}
              onClick={() => onChatSelect(chatSuffix)}
            >
              {Number(chatSuffix) + 1}
            </button>
          );
        })}

      {/* New chat button */}
      <button
        className="rounded-full bg-slate-200 px-4 py-2 mx-2 mb-2"
        onClick={onNewChat}
      >
        +
      </button>

      {/* Delete current chat button */}
      {Object.keys(localStorageKeys).length > 0 && (
        <button
          className="rounded-full bg-red-200 font-bold px-4 py-2 mx-2 mb-2"
          onClick={onDeleteCurrentChat}
        >
          <DeleteFileIcon />
          {content["deleteCurrentChat"]}
        </button>
      )}

      {/* Delete all chats button */}
      {Object.keys(localStorageKeys).length > 0 && (
        <button
          className="rounded-full bg-red-200 font-bold px-4 py-2 mx-2 mb-2"
          onClick={onDeleteAllChats}
        >
          <DeleteFileIcon />
          {content["deleteAllChats"]}
        </button>
      )}

      {/* Save chats button */}
      {Object.keys(localStorageKeys).length > 0 && (
        <button
          className="rounded-full bg-green-200 font-bold px-4 py-2 mx-2 mb-2"
          onClick={onSaveChats}
        >
          <DownloadIcon />
        </button>
      )}

      {/* Restore chats input and button */}
      <input
        type="file"
        id="restoreChatFromLocalFile"
        style={{ display: "none" }}
        onChange={onRestoreChats}
      />
      <button
        className="rounded-full bg-green-200 font-bold px-4 py-2 mx-2 mb-2"
        onClick={() =>
          document.getElementById("restoreChatFromLocalFile")?.click()
        }
      >
        <UploadIcon />
      </button>
    </div>
  );
};

export default ChatHeader;
