/**
 * @file imageStore.ts
 * @description IndexedDB-based storage for generated/uploaded images.
 *              Offloads large base64 image data from localStorage to IndexedDB,
 *              preventing QuotaExceededError when saving chat messages.
 */

const DB_NAME = "bude-images";
const DB_VERSION = 1;
const STORE_NAME = "images";

/**
 * Placeholder prefix used in localStorage to reference IndexedDB-stored images.
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
 * Stores an image in IndexedDB by its ID.
 */
export async function saveImage(id: string, dataUrl: string): Promise<void> {
  try {
    const db = await openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readwrite");
      tx.objectStore(STORE_NAME).put(dataUrl, id);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch (e) {
    console.warn("[imageStore] Failed to save image:", id, e);
  }
}

/**
 * Retrieves an image from IndexedDB by its ID.
 */
export async function loadImage(id: string): Promise<string | null> {
  try {
    const db = await openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readonly");
      const req = tx.objectStore(STORE_NAME).get(id);
      req.onsuccess = () => resolve(req.result ?? null);
      req.onerror = () => reject(req.error);
    });
  } catch (e) {
    console.warn("[imageStore] Failed to load image:", id, e);
    return null;
  }
}

/**
 * Deletes an image from IndexedDB.
 */
export async function deleteImage(id: string): Promise<void> {
  try {
    const db = await openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readwrite");
      tx.objectStore(STORE_NAME).delete(id);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch (e) {
    console.warn("[imageStore] Failed to delete image:", id, e);
  }
}

/**
 * Strips large base64 data URLs from messages and replaces them with
 * IndexedDB placeholders (idb://imageId). Saves the actual data to IndexedDB.
 *
 * Call this BEFORE persisting messages to localStorage.
 */
// deno-lint-ignore no-explicit-any
export async function stripImagesForStorage(messages: any[]): Promise<any[]> {
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

        // Save to IndexedDB in background
        savePromises.push(saveImage(imageId, dataUrl));

        // Replace with placeholder in localStorage copy
        return {
          ...part,
          image_url: { url: `${IDB_PLACEHOLDER}${imageId}` },
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
 */
// deno-lint-ignore no-explicit-any
export async function rehydrateImages(messages: any[]): Promise<any[]> {
  const loadPromises: { msg: number; part: number; id: string }[] = [];

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
        loadPromises.push({
          msg: m,
          part: p,
          id: part.id,
        });
      }
    }
  }

  if (loadPromises.length === 0) return messages;

  // Load all images from IndexedDB in parallel
  const results = await Promise.all(
    loadPromises.map(async (ref) => ({
      ...ref,
      data: await loadImage(ref.id),
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
