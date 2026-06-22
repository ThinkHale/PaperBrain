/**
 * process-note - Supabase Edge Function
 *
 * Transcribes/organizes a note from images (base64 data URLs) OR from raw text,
 * assigns curated categories + finer topic tags, detects the note type, extracts
 * to-do action items, and (for images) locates unclear words with bounding boxes.
 *
 * POST /functions/v1/process-note
 * Auth: Bearer <supabase-access-token>
 * Body:
 *   {
 *     mode?: 'full' | 'region' | 'text',   // default 'full'
 *     images?: string[],                    // required for full / region
 *     text?: string,                        // required for text mode
 *     noteType?: string,                    // text mode: 'typed' | 'voice'
 *     tag?: string,                         // region mode
 *     noteId?: string,                      // camelCase (web)
 *     note_id?: string                      // snake_case (native)
 *   }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPENAI_URL = "https://api.openai.com/v1/responses";
const MAX_IMAGES = 25;
const MAX_DATA_URL_BYTES = 15 * 1024 * 1024;

const NOTE_TYPES = [
  "handwritten",
  "postit",
  "notebook",
  "whiteboard",
  "printed",
  "diagram",
  "mixed",
];

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  try {
    const authHeader = req.headers.get("authorization") ?? "";
    const accessToken = authHeader.replace(/^Bearer\s+/i, "").trim();
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const user = await getUserFromAccessToken(supabaseUrl, supabaseAnonKey, accessToken);
    if (!user) {
      console.error("[process-note] auth error: invalid token", "header present:", !!authHeader);
      return json({ error: "Unauthorized" }, 401);
    }

    const admin = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const body = await req.json();
    const { images, mode = "full", tag, text } = body as {
      images?: string[];
      mode?: "full" | "region" | "text";
      tag?: string;
      text?: string;
      noteType?: string;
      noteId?: string;
      note_id?: string;
    };
    const noteId = body.noteId ?? body.note_id;
    const clientNoteType = typeof body.noteType === "string" ? body.noteType : undefined;

    if (mode === "text") {
      if (!text?.trim()) return json({ error: "text required" }, 400);
    } else {
      if (!images?.length) return json({ error: "images required" }, 400);
      if (images.length > MAX_IMAGES) return json({ error: `max ${MAX_IMAGES} images` }, 400);
      for (const image of images) validateDataUrl(image);
    }
    if (noteId) await assertOwnedNote(admin, noteId, user.id);

    const { data: profile } = await admin
      .from("profiles")
      .select("handwriting_context, model")
      .eq("id", user.id)
      .single();

    const hwContext = profile?.handwriting_context ?? "";
    const openaiKey = Deno.env.get("OPENAI_API_KEY")!;

    // The user's curated vocabulary keeps tagging consistent instead of granular.
    const vocab = await fetchVocabulary(admin, user.id);

    // ── Region mode: unchanged behaviour (used by annotation re-process) ──
    if (mode === "region") {
      const aiData = await callOpenAI(openaiKey, {
        model: resolveOpenAIModel(profile?.model),
        maxTokens: 1200,
        schemaName: "illuminote_region",
        schema: regionSchema(),
        input: [{
          role: "user",
          content: [
            ...images!.map((dataUrl) => ({ type: "input_image", image_url: dataUrl })),
            { type: "input_text", text: regionPrompt(tag, hwContext) },
          ],
        }],
      });
      const parsed = parseJSON(extractOutputText(aiData));
      return json({ ok: true, region: parsed }, 200);
    }

    // ── Full (image) or text mode ──
    const isText = mode === "text";
    const schema = isText ? textSchema() : noteSchema();
    const prompt = isText
      ? textPrompt(vocab)
      : fullPrompt(images!.length, hwContext, vocab);

    const input = isText
      ? [{ role: "user", content: [{ type: "input_text", text: `${prompt}\n\nNOTE TEXT:\n${text}` }] }]
      : [{
        role: "user",
        content: [
          ...images!.map((dataUrl) => ({ type: "input_image", image_url: dataUrl })),
          { type: "input_text", text: prompt },
        ],
      }];

    const aiData = await callOpenAI(openaiKey, {
      model: resolveOpenAIModel(profile?.model),
      maxTokens: isText ? 4000 : 5000,
      schemaName: isText ? "illuminote_text" : "illuminote_note",
      schema,
      input,
    });
    const parsed = parseJSON(extractOutputText(aiData));

    // Resolve the note type: client wins for typed/voice; otherwise the model's guess.
    const resolvedNoteType = isText
      ? (clientNoteType === "voice" ? "voice" : "typed")
      : (NOTE_TYPES.includes(parsed.noteType) ? parsed.noteType : "handwritten");
    const resolvedSourceType = isText
      ? (clientNoteType === "voice" ? "voice" : "typed")
      : (images!.length > 1 ? "pdf" : "image");

    const noteFields = {
      title: parsed.title ?? "Untitled",
      transcription: isText ? (text ?? "") : (parsed.transcription ?? ""),
      organized: parsed.organized ?? "",
      summary: parsed.summary ?? "",
      tags: normalizeStringArray(parsed.tags),
      categories: normalizeStringArray(parsed.categories),
      key_points: normalizeStringArray(parsed.keyPoints),
      note_type: resolvedNoteType,
      unclear_regions: isText ? [] : normalizeRegions(parsed.unclearRegions),
      source_type: resolvedSourceType,
      processing_state: "done",
      error_message: null,
    };

    let note;
    if (noteId) {
      const { data, error: updateErr } = await admin
        .from("notes")
        .update(noteFields)
        .eq("id", noteId)
        .eq("user_id", user.id)
        .select()
        .single();
      if (updateErr) throw updateErr;
      note = data;
    } else {
      const { data, error: insertErr } = await admin
        .from("notes")
        .insert({ user_id: user.id, ...noteFields })
        .select()
        .single();
      if (insertErr) throw insertErr;
      note = data;

      if (!isText) await storeImages(admin, images!, user.id, note.id);
    }

    // Derived data: to-dos, vocabulary growth, usage metering.
    await syncTodos(admin, user.id, note.id, parsed.todos, !!noteId);
    await growVocabulary(admin, user.id, noteFields.categories, noteFields.tags, vocab);
    await recordUsage(admin, user.id, "ai_process");

    return json({ ok: true, note }, 200);
  } catch (err) {
    console.error("[process-note]", err);
    return json({ error: String(err) }, 500);
  }
});

// ── OpenAI ────────────────────────────────────────────────────

async function callOpenAI(
  openaiKey: string,
  opts: {
    model: string;
    maxTokens: number;
    schemaName: string;
    schema: Record<string, unknown>;
    input: unknown;
  },
) {
  const res = await fetch(OPENAI_URL, {
    method: "POST",
    headers: {
      "authorization": `Bearer ${openaiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: opts.model,
      store: false,
      max_output_tokens: opts.maxTokens,
      text: {
        format: {
          type: "json_schema",
          name: opts.schemaName,
          strict: true,
          schema: opts.schema,
        },
      },
      input: opts.input,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error?.message ?? `OpenAI error ${res.status}`);
  }
  return await res.json();
}

// ── Prompts ───────────────────────────────────────────────────

function vocabularyBlock(vocab: { categories: string[]; topics: string[] }): string {
  const cats = vocab.categories.length ? vocab.categories.join(", ") : "Business, Personal, To-Do, Ideas, Projects, Finance, Health, Learning, Reference";
  const topics = vocab.topics.length ? `\nExisting topic tags (reuse when they fit): ${vocab.topics.join(", ")}` : "";
  return `\nAVAILABLE CATEGORIES (assign 1-3 that best fit; only invent a new category if none apply): ${cats}${topics}\n`;
}

function fullPrompt(
  pageCount: number,
  hwContext: string,
  vocab: { categories: string[]; topics: string[] },
): string {
  const pageWord = pageCount > 1 ? `these ${pageCount} pages` : "this page";
  return `You are an expert at reading handwritten notes and organizing information clearly.
${hwContext ? `\nHandwriting notes from previous user corrections:\n${hwContext}\nPlease apply these style notes when transcribing.\n` : ""}
Analyze ${pageWord}.
${vocabularyBlock(vocab)}
Return:
- title: a concise descriptive title, max 60 characters.
- transcription: a complete verbatim transcription preserving line breaks. Mark unclear text as [unclear].
- organized: the same content reorganized as Markdown using headings, bullets, and bold key terms.
- summary: a 2-3 sentence summary.
- categories: 1 to 3 high-level categories chosen from the AVAILABLE CATEGORIES list above (exact spelling). Invent a new one only if nothing fits.
- tags: up to 5 lowercase, specific topic tags. Reuse existing topic tags above when they apply.
- keyPoints: 3 to 8 key points.
- noteType: the physical kind of note, one of: ${NOTE_TYPES.join(", ")}.
- todos: any action items / tasks the note asks the writer to do, each as a short imperative string. Empty array if none.
- unclearRegions: for EACH [unclear] mark in the transcription, one entry with:
    guess (your best single-word guess), page (0-indexed page number),
    x, y, w, h (the word's bounding box on that page, all normalized 0.0-1.0 where
    x,y is the top-left corner), and context (the few words around it).
  Make the box generous enough to clearly contain the word. Empty array if nothing is unclear.`;
}

function textPrompt(vocab: { categories: string[]; topics: string[] }): string {
  return `You are organizing a note the user typed or dictated.
${vocabularyBlock(vocab)}
Return:
- title: a concise descriptive title, max 60 characters.
- organized: the note reorganized as clean Markdown (headings, bullets, bold key terms).
- summary: a 2-3 sentence summary.
- categories: 1 to 3 high-level categories chosen from the AVAILABLE CATEGORIES list above (exact spelling). Invent a new one only if nothing fits.
- tags: up to 5 lowercase, specific topic tags. Reuse existing topic tags above when they apply.
- keyPoints: 3 to 8 key points.
- todos: any action items / tasks mentioned, each as a short imperative string. Empty array if none.`;
}

function regionPrompt(tag: string | undefined, hwContext: string): string {
  return `You are transcribing a specific annotated region of a handwritten note.
This region is tagged as: "${tag ?? "unlabeled"}".
${hwContext ? `\nHandwriting notes from user corrections:\n${hwContext}\n` : ""}
Tasks:
1. Transcribe all text visible in this image region verbatim. Mark unclear text as [unclear].
2. Return a short, well-formatted Markdown summary of the region.
3. Keep the provided tag value unless it is empty.`;
}

// ── Schemas ───────────────────────────────────────────────────

function noteSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: [
      "title", "transcription", "organized", "summary",
      "categories", "tags", "keyPoints", "noteType", "todos", "unclearRegions",
    ],
    properties: {
      title: { type: "string" },
      transcription: { type: "string" },
      organized: { type: "string" },
      summary: { type: "string" },
      categories: { type: "array", items: { type: "string" } },
      tags: { type: "array", items: { type: "string" } },
      keyPoints: { type: "array", items: { type: "string" } },
      noteType: { type: "string", enum: NOTE_TYPES },
      todos: { type: "array", items: { type: "string" } },
      unclearRegions: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["guess", "page", "x", "y", "w", "h", "context"],
          properties: {
            guess: { type: "string" },
            page: { type: "integer" },
            x: { type: "number" },
            y: { type: "number" },
            w: { type: "number" },
            h: { type: "number" },
            context: { type: "string" },
          },
        },
      },
    },
  };
}

function textSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["title", "organized", "summary", "categories", "tags", "keyPoints", "todos"],
    properties: {
      title: { type: "string" },
      organized: { type: "string" },
      summary: { type: "string" },
      categories: { type: "array", items: { type: "string" } },
      tags: { type: "array", items: { type: "string" } },
      keyPoints: { type: "array", items: { type: "string" } },
      todos: { type: "array", items: { type: "string" } },
    },
  };
}

function regionSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["transcription", "content", "tag"],
    properties: {
      transcription: { type: "string" },
      content: { type: "string" },
      tag: { type: "string" },
    },
  };
}

// ── Derived data ──────────────────────────────────────────────

async function fetchVocabulary(admin: any, userId: string) {
  const { data } = await admin
    .from("tags")
    .select("name, kind")
    .eq("user_id", userId);
  const categories = (data ?? []).filter((t: any) => t.kind === "category").map((t: any) => t.name);
  const topics = (data ?? []).filter((t: any) => t.kind === "topic").map((t: any) => t.name);
  return { categories, topics };
}

/** Re-sync AI-extracted todos for a note. Manual todos are never touched. */
async function syncTodos(admin: any, userId: string, noteId: string, todos: unknown, isUpdate: boolean) {
  const items = normalizeStringArray(todos);
  if (isUpdate) {
    await admin.from("todos").delete().eq("note_id", noteId).eq("source", "ai");
  }
  if (!items.length) return;
  const rows = items.map((text, i) => ({
    user_id: userId,
    note_id: noteId,
    text,
    source: "ai",
    position: i,
  }));
  const { error } = await admin.from("todos").insert(rows);
  if (error) console.error("[process-note] todo insert", error);
}

/** Add any newly-seen categories/topics to the user's vocabulary. */
async function growVocabulary(
  admin: any,
  userId: string,
  categories: string[],
  topics: string[],
  existing: { categories: string[]; topics: string[] },
) {
  const known = new Set([
    ...existing.categories.map((c) => `category:${c.toLowerCase()}`),
    ...existing.topics.map((t) => `topic:${t.toLowerCase()}`),
  ]);
  const rows: any[] = [];
  for (const name of categories) {
    if (name && !known.has(`category:${name.toLowerCase()}`)) {
      rows.push({ user_id: userId, name, kind: "category" });
      known.add(`category:${name.toLowerCase()}`);
    }
  }
  for (const name of topics) {
    if (name && !known.has(`topic:${name.toLowerCase()}`)) {
      rows.push({ user_id: userId, name, kind: "topic" });
      known.add(`topic:${name.toLowerCase()}`);
    }
  }
  if (!rows.length) return;
  const { error } = await admin.from("tags").upsert(rows, { onConflict: "user_id,kind,name", ignoreDuplicates: true });
  if (error) console.error("[process-note] vocab upsert", error);
}

async function recordUsage(admin: any, userId: string, kind: string) {
  const { error } = await admin.from("usage_events").insert({ user_id: userId, kind });
  if (error) console.error("[process-note] usage", error);
}

async function storeImages(admin: any, images: string[], userId: string, noteId: string) {
  const imageRows = [];
  for (let i = 0; i < images.length; i++) {
    const dataUrl = images[i];
    const comma = dataUrl.indexOf(",");
    const mediaType = dataUrl.slice(5, comma).split(";")[0] || "image/jpeg";
    const ext = mediaType === "image/png" ? "png" : mediaType === "image/webp" ? "webp" : "jpg";
    const base64 = dataUrl.slice(comma + 1);
    const binary = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    const path = `${userId}/${noteId}/${i}.${ext}`;

    const { error: uploadErr } = await admin.storage.from("note-images").upload(path, binary, {
      contentType: mediaType,
      upsert: true,
    });
    if (uploadErr) throw uploadErr;

    imageRows.push({ note_id: noteId, user_id: userId, storage_path: path, page_number: i });
  }
  if (imageRows.length) {
    const { error: imageErr } = await admin.from("note_images").insert(imageRows);
    if (imageErr) throw imageErr;
  }
}

// ── Helpers ───────────────────────────────────────────────────

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

function validateDataUrl(dataUrl: string) {
  if (!/^data:image\/(jpeg|jpg|png|webp);base64,/i.test(dataUrl)) {
    throw new Error("images must be image data URLs");
  }
  if (dataUrl.length > MAX_DATA_URL_BYTES) {
    throw new Error("image data URL is too large");
  }
}

function parseJSON(text: string) {
  const cleaned = text
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
  const match = cleaned.match(/\{[\s\S]*\}/);
  if (!match) throw new Error("No JSON in AI response");
  return JSON.parse(match[0]);
}

function extractOutputText(response: any): string {
  if (typeof response.output_text === "string") return response.output_text;
  const chunks: string[] = [];
  for (const item of response.output ?? []) {
    for (const content of item.content ?? []) {
      if (typeof content.text === "string") chunks.push(content.text);
    }
  }
  const text = chunks.join("\n").trim();
  if (!text) throw new Error("No text in OpenAI response");
  return text;
}

function normalizeStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => String(item ?? "").trim())
    .filter(Boolean);
}

/** Clamp region boxes to 0-1 and drop malformed entries. */
function normalizeRegions(value: unknown): unknown[] {
  if (!Array.isArray(value)) return [];
  const clamp = (n: unknown) => Math.min(1, Math.max(0, Number(n) || 0));
  return value
    .filter((r) => r && typeof r === "object")
    .map((r: any) => ({
      guess: String(r.guess ?? "").trim(),
      page: Math.max(0, Math.floor(Number(r.page) || 0)),
      x: clamp(r.x),
      y: clamp(r.y),
      w: clamp(r.w),
      h: clamp(r.h),
      context: String(r.context ?? "").trim(),
    }))
    .filter((r) => r.w > 0 && r.h > 0);
}

async function getUserFromAccessToken(supabaseUrl: string, supabaseAnonKey: string, accessToken: string) {
  if (!accessToken) return null;

  const res = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      apikey: supabaseAnonKey,
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!res.ok) return null;
  return await res.json();
}

async function assertOwnedNote(admin: any, noteId: string, userId: string) {
  const { data, error } = await admin
    .from("notes")
    .select("id")
    .eq("id", noteId)
    .eq("user_id", userId)
    .single();

  if (error || !data) throw new Error("Note not found");
}

function resolveOpenAIModel(model?: string | null) {
  switch (model) {
    case "gpt-5.5":
    case "gpt-5.4":
    case "gpt-5.4-mini":
    case "gpt-5.4-nano":
      return model;
    default:
      return "gpt-5.4-mini";
  }
}
