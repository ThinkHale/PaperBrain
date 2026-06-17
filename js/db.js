/**
 * db.js — Supabase data layer for PaperBrain
 *
 * All functions require Auth.getToken() to be non-null (user signed in).
 * The Supabase client enforces RLS: users only see their own rows.
 */

import { client, getUser } from "./auth.js";

async function currentUserId() {
  const cached = getUser()?.id;
  if (cached) return cached;

  const { data, error } = await client.auth.getUser();
  if (error) throw error;
  if (!data.user?.id) throw new Error("You must be signed in.");
  return data.user.id;
}

// ── Notes ──────────────────────────────────────────────────────

/** Fetch all notes for the current user, newest first. */
export async function getAllNotes() {
  const { data, error } = await client
    .from("notes")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

/** Fetch a single note by id. */
export async function getNote(id) {
  const { data, error } = await client
    .from("notes")
    .select("*")
    .eq("id", id)
    .single();
  if (error) throw error;
  return data;
}

/** Update editable fields on an existing note. */
export async function saveNote(id, fields) {
  const { data, error } = await client
    .from("notes")
    .update({ ...fields, updated_at: new Date().toISOString() })
    .eq("id", id)
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Delete a note (cascade removes images, annotations, relations via FK). */
export async function deleteNote(id) {
  const { error } = await client.from("notes").delete().eq("id", id);
  if (error) throw error;
}

/**
 * Search notes by query string.
 * Uses client-side scoring across title, summary, transcription, tags.
 */
export async function searchNotes(query) {
  if (!query?.trim()) return getAllNotes();
  const terms = query.trim().toLowerCase().split(/\s+/);
  const all = await getAllNotes();
  const scored = all.map((n) => {
    let score = 0;
    for (const t of terms) {
      if ((n.title ?? "").toLowerCase().includes(t)) score += 3;
      if ((n.summary ?? "").toLowerCase().includes(t)) score += 2;
      if ((n.transcription ?? "").toLowerCase().includes(t)) score += 1;
      if ((n.tags ?? []).some((tag) => tag.includes(t))) score += 2;
    }
    return { note: n, score };
  });
  return scored
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score)
    .map((x) => x.note);
}

// ── Note Images ────────────────────────────────────────────────

/** Get signed URLs for all private images attached to a note (ordered by page). */
export async function getNoteImageUrls(noteId) {
  const { data, error } = await client
    .from("note_images")
    .select("storage_path, page_number")
    .eq("note_id", noteId)
    .order("page_number");
  if (error) throw error;

  const paths = (data ?? []).map((row) => row.storage_path);
  if (!paths.length) return [];

  const { data: signed, error: signError } = await client.storage
    .from("note-images")
    .createSignedUrls(paths, 60 * 60);
  if (signError) throw signError;

  return (signed ?? []).map((row) => row.signedUrl);
}

// ── Annotations ────────────────────────────────────────────────

/** Load all annotations for a note. */
export async function getAnnotations(noteId) {
  const { data, error } = await client
    .from("annotations")
    .select("*")
    .eq("note_id", noteId)
    .order("created_at");
  if (error) throw error;
  return data ?? [];
}

/** Upsert a single annotation. Returns saved row. */
export async function saveAnnotation(annotation) {
  const { id, ...rest } = annotation;
  if (id) {
    const { data, error } = await client
      .from("annotations")
      .update(rest)
      .eq("id", id)
      .select()
      .single();
    if (error) throw error;
    return data;
  } else {
    const userId = await currentUserId();
    const { data, error } = await client
      .from("annotations")
      .insert({ ...rest, user_id: userId })
      .select()
      .single();
    if (error) throw error;
    return data;
  }
}

/** Delete an annotation by id. */
export async function deleteAnnotation(id) {
  const { error } = await client.from("annotations").delete().eq("id", id);
  if (error) throw error;
}

// ── Relations ──────────────────────────────────────────────────

/** Get all relations for a note (either direction). */
export async function getRelations(noteId) {
  const { data, error } = await client
    .from("relations")
    .select("*")
    .or(`from_id.eq.${noteId},to_id.eq.${noteId}`);
  if (error) throw error;
  return data ?? [];
}

/** Save a manual relation between two notes. */
export async function saveRelation({ fromId, toId, reason = "", score = 0.8 }) {
  const userId = await currentUserId();
  const { data, error } = await client
    .from("relations")
    .upsert(
      { user_id: userId, from_id: fromId, to_id: toId, score, reason, manual: true },
      { onConflict: "from_id,to_id" },
    )
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Delete a relation by id. */
export async function deleteRelation(id) {
  const { error } = await client.from("relations").delete().eq("id", id);
  if (error) throw error;
}

/** Fetch all relations for the mind-map view. */
export async function getAllRelations() {
  const { data, error } = await client.from("relations").select("*");
  if (error) throw error;
  return data ?? [];
}

// ── Mind-map Positions ─────────────────────────────────────────

/** Load all saved node positions. */
export async function getMindmapPositions() {
  const { data, error } = await client.from("mindmap_positions").select("*");
  if (error) throw error;
  return data ?? [];
}

/** Save (upsert) a node position. */
export async function saveMindmapPosition({ nodeType, nodeId, x, y }) {
  const userId = await currentUserId();
  const { error } = await client.from("mindmap_positions").upsert(
    { user_id: userId, node_type: nodeType, node_id: nodeId, x, y, updated_at: new Date().toISOString() },
    { onConflict: "user_id,node_type,node_id" },
  );
  if (error) throw error;
}

// ── Profile / Settings ─────────────────────────────────────────

/** Load the current user's profile. */
export async function getProfile() {
  const { data, error } = await client
    .from("profiles")
    .select("*")
    .single();
  if (error) throw error;
  return data;
}

/** Update profile fields (model, display_name, etc.). */
export async function updateProfile(fields) {
  const userId = await currentUserId();
  const { error } = await client.from("profiles").update(fields).eq("id", userId);
  if (error) throw error;
}

// ── Data Export ────────────────────────────────────────────────

/** Export all user data as a JSON blob. */
export async function exportAll() {
  const [notes, relations] = await Promise.all([getAllNotes(), getAllRelations()]);
  return { notes, relations, exportedAt: new Date().toISOString() };
}
