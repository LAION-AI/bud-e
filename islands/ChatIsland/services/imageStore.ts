/**
 * @file imageStore.ts
 * @description IndexedDB-based storage for generated/uploaded images.
 *              Offloads large base64 image data from localStorage to IndexedDB,
 *              preventing QuotaExceededError when saving chat messages.
 *
 *              Keys are namespaced by chat suffix to prevent cross-chat collisions:
 *              e.g., "0:gen_00001" vs "1:gen_00001"
 */

const DB_NAME = "bude-images";
const DB_VERSION = 1;
const STORE_NAME = "images";

/**
 * Placeholder prefix used in localStorage to reference IndexedDB-stored images.
 * Format: idb://chatSuffix:imageId
 */
export const IDB_PLACEHOLDER = "idb://";

let dbPromise: Promise<IDBDatabase> | null = null;

/**
 * Opens (or creates) the IndexedDB database for image storage.
 */
function openDB(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME);
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => {
      console.warn("[imageStore] IndexedDB open failed:", req.error);
      reject(req.error);
    };
  });
  return dbPromise;
}

/**
 * Builds a namespaced storage key: "chatSuffix:imageId"
 */
function storageKey(chatSuffix: string, imageId: string): string {
  return `${chatSuffix}:${imageId}`;
}

/**
 * Stores an image in IndexedDB, namespaced by chat suffix.
 */
export async function saveImage(chatSuffix: string, imageId: string, dataUrl: string): Promise<void> {
  try {
    const db = await openDB();
    const key = storageKey(chatSuffix, imageId);
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readwrite");
      tx.objectStore(STORE_NAME).put(dataUrl, key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch (e) {
    console.warn("[imageStore] Failed to save image:", chatSuffix, imageId, e);
  }
}

/**
 * Retrieves an image from IndexedDB by chat suffix and image ID.
 */
export async function loadImage(chatSuffix: string, imageId: string): Promise<string | null> {
  try {
    const db = await openDB();
    const key = storageKey(chatSuffix, imageId);
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readonly");
      const req = tx.objectStore(STORE_NAME).get(key);
      req.onsuccess = () => resolve(req.result ?? null);
      req.onerror = () => reject(req.error);
    });
  } catch (e) {
    console.warn("[imageStore] Failed to load image:", chatSuffix, imageId, e);
    return null;
  }
}

/**
 * Deletes an image from IndexedDB.
 */
export async function deleteImage(chatSuffix: string, imageId: string): Promise<void> {
  try {
    const db = await openDB();
    const key = storageKey(chatSuffix, imageId);
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readwrite");
      tx.objectStore(STORE_NAME).delete(key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch (e) {
    console.warn("[imageStore] Failed to delete image:", chatSuffix, imageId, e);
  }
}

/**
 * Strips large base64 data URLs from messages and replaces them with
 * IndexedDB placeholders (idb://chatSuffix:imageId). Saves the actual data to IndexedDB.
 *
 * Call this BEFORE persisting messages to localStorage.
 *
 * @param messages - Messages to process
 * @param chatSuffix - The chat suffix to namespace images under
 */
// deno-lint-ignore no-explicit-any
export async function stripImagesForStorage(messages: any[], chatSuffix: string): Promise<any[]> {
  const savePromises: Promise<void>[] = [];

  const stripped = messages.map((msg) => {
    if (!Array.isArray(msg.content)) return msg;

    const newContent = msg.content.map((part: Record<string, unknown>) => {
      if (
        part?.type === "image_url" &&
        part?.id &&
        // deno-lint-ignore no-explicit-any
        (part as any)?.image_url?.url &&
        // deno-lint-ignore no-explicit-any
        typeof (part as any).image_url.url === "string" &&
        // deno-lint-ignore no-explicit-any
        (part as any).image_url.url.startsWith("data:")
      ) {
        const imageId = part.id as string;
        // deno-lint-ignore no-explicit-any
        const dataUrl = (part as any).image_url.url as string;

        // Save to IndexedDB namespaced by chat
        savePromises.push(saveImage(chatSuffix, imageId, dataUrl));

        // Replace with placeholder including chat suffix
        return {
          ...part,
          image_url: { url: `${IDB_PLACEHOLDER}${chatSuffix}:${imageId}` },
        };
      }
      return part;
    });

    return { ...msg, content: newContent };
  });

  // Wait for all image saves to complete
  await Promise.all(savePromises);
  return stripped;
}

/**
 * Restores IndexedDB placeholders back to actual base64 data URLs.
 *
 * Call this AFTER loading messages from localStorage.
 *
 * @param messages - Messages to rehydrate
 * @param chatSuffix - The chat suffix to look up images under
 */
// deno-lint-ignore no-explicit-any
export async function rehydrateImages(messages: any[], chatSuffix: string): Promise<any[]> {
  const loadPromises: { msg: number; part: number; id: string; suffix: string }[] = [];

  // Identify all placeholders
  for (let m = 0; m < messages.length; m++) {
    const msg = messages[m];
    if (!Array.isArray(msg.content)) continue;
    for (let p = 0; p < msg.content.length; p++) {
      const part = msg.content[p];
      if (
        part?.type === "image_url" &&
        part?.id &&
        part?.image_url?.url &&
        typeof part.image_url.url === "string" &&
        part.image_url.url.startsWith(IDB_PLACEHOLDER)
      ) {
        // Parse the placeholder: idb://chatSuffix:imageId
        const ref = part.image_url.url.slice(IDB_PLACEHOLDER.length);
        const colonIdx = ref.indexOf(":");
        if (colonIdx >= 0) {
          // New format with chat suffix
          loadPromises.push({
            msg: m,
            part: p,
            suffix: ref.slice(0, colonIdx),
            id: ref.slice(colonIdx + 1),
          });
        } else {
          // Legacy format without chat suffix - use provided chatSuffix
          loadPromises.push({
            msg: m,
            part: p,
            suffix: chatSuffix,
            id: ref,
          });
        }
      }
    }
  }

  if (loadPromises.length === 0) return messages;

  // Load all images from IndexedDB in parallel
  const results = await Promise.all(
    loadPromises.map(async (ref) => ({
      ...ref,
      data: await loadImage(ref.suffix, ref.id),
    }))
  );

  // Deep copy messages and restore data URLs
  const restored = messages.map((msg) => ({
    ...msg,
    content: Array.isArray(msg.content) ? [...msg.content] : msg.content,
  }));

  for (const { msg, part, data } of results) {
    if (data && Array.isArray(restored[msg].content)) {
      restored[msg].content[part] = {
        ...restored[msg].content[part],
        image_url: { url: data },
      };
    }
  }

  return restored;
}
