/**
 * api.js — Supabase Edge Function client for Illuminote
 *
 * All requests go to Supabase Edge Functions (server-side OpenAI calls).
 * No API key is needed on the client — the key lives in the Edge Function secret.
 */

import { client, getToken } from "./auth.js";

const { supabaseUrl, supabaseAnonKey } = window.ILLUMINOTE_CONFIG ?? {};

async function callFn(name, body) {
  const token = getToken() ?? (await client.auth.getSession()).data.session?.access_token;
  if (!token) {
    throw new Error("You must be signed in to use this feature.");
  }

  const res = await fetch(`${supabaseUrl}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: supabaseAnonKey,
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });

  const text = await res.text();
  const data = text ? safeJsonParse(text) : null;

  if (!res.ok) {
    if (res.status === 401) {
      throw new Error(
        "Unauthorized. Sign out and back in, then redeploy the latest process-note function if the error persists.",
      );
    }
    const message = data?.error ?? data?.message ?? text ?? `${res.status} ${res.statusText}`;
    throw new Error(message);
  }

  return data;
}

function safeJsonParse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// ── Image helpers ──────────────────────────────────────────────

/** Resize an image data-URL so neither dimension exceeds maxPx. */
export function resizeImage(dataUrl, maxPx = 1568) {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      const scale = Math.min(1, maxPx / Math.max(img.width, img.height));
      const w = Math.round(img.width * scale);
      const h = Math.round(img.height * scale);
      const canvas = document.createElement("canvas");
      canvas.width = w;
      canvas.height = h;
      canvas.getContext("2d").drawImage(img, 0, 0, w, h);
      resolve(canvas.toDataURL("image/jpeg", 0.88));
    };
    img.src = dataUrl;
  });
}

/** Read a File/Blob as a base64 data-URL. */
export function fileToDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => resolve(e.target.result);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

/**
 * Crop a rectangular region from an image data-URL.
 * rect: { x, y, w, h } — all values 0-1 (normalized).
 */
export function cropImage(dataUrl, rect) {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement("canvas");
      const cw = Math.round(rect.w * img.width);
      const ch = Math.round(rect.h * img.height);
      canvas.width = cw;
      canvas.height = ch;
      canvas.getContext("2d").drawImage(
        img,
        Math.round(rect.x * img.width),
        Math.round(rect.y * img.height),
        cw,
        ch,
        0,
        0,
        cw,
        ch,
      );
      resolve(canvas.toDataURL("image/jpeg", 0.88));
    };
    img.src = dataUrl;
  });
}

// ── Edge Function calls ────────────────────────────────────────

/**
 * Process one or more images (base64 data-URLs) as a note.
 * Returns { ok, note } with the saved note record.
 */
export async function processNote(images, { noteId } = {}) {
  const resized = await Promise.all(images.map((img) => resizeImage(img)));
  return callFn("process-note", { images: resized, mode: "full", noteId });
}

/**
 * Re-process a single cropped region.
 * Returns { ok, region: { transcription, content, tag } }
 */
export async function processRegion({ imageDataUrl, tag, noteId }) {
  const resized = await resizeImage(imageDataUrl, 1024);
  return callFn("process-note", {
    images: [resized],
    mode: "region",
    tag,
    noteId,
  });
}

/**
 * Ask OpenAI to find related notes for a given noteId (runs in background).
 * Returns { ok, relations }
 */
export async function findRelations(noteId) {
  return callFn("find-relations", { noteId });
}

/**
 * Submit text corrections and/or clarification popup results.
 * corrections:    [{ original, correction, context? }]
 * clarifications: [{ croppedImage, word, context? }]
 */
export async function learnHandwriting({ noteId, corrections = [], clarifications = [] }) {
  return callFn("learn-handwriting", { noteId, corrections, clarifications });
}
