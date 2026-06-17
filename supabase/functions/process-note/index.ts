/**
 * process-note - Supabase Edge Function
 *
 * Accepts images (base64 data URLs), calls OpenAI, saves/updates the note,
 * stores new images, and returns the note record.
 *
 * POST /functions/v1/process-note
 * Auth: Bearer <supabase-access-token>
 * Body:
 *   {
 *     images: string[],
 *     mode?: 'full' | 'region',
 *     tag?: string,
 *     noteId?: string,        // camelCase used by web
 *     note_id?: string        // snake_case accepted for native clients
 *   }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPENAI_URL = "https://api.openai.com/v1/responses";
const MAX_IMAGES = 25;
const MAX_DATA_URL_BYTES = 15 * 1024 * 1024;

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
    const { images, mode = "full", tag } = body as {
      images?: string[];
      mode?: "full" | "region";
      tag?: string;
      noteId?: string;
      note_id?: string;
    };
    const noteId = body.noteId ?? body.note_id;

    if (!images?.length) return json({ error: "images required" }, 400);
    if (images.length > MAX_IMAGES) return json({ error: `max ${MAX_IMAGES} images` }, 400);
    for (const image of images) validateDataUrl(image);
    if (noteId) await assertOwnedNote(admin, noteId, user.id);

    const { data: profile } = await admin
      .from("profiles")
      .select("handwriting_context, model")
      .eq("id", user.id)
      .single();

    const hwContext = profile?.handwriting_context ?? "";
    const openaiKey = Deno.env.get("OPENAI_API_KEY")!;

    const imageBlocks = images.map((dataUrl: string) => ({
      type: "input_image",
      image_url: dataUrl,
    }));

    let prompt: string;
    let maxTokens: number;
    let schema: Record<string, unknown>;

    if (mode === "region") {
      maxTokens = 1200;
      schema = regionSchema();
      prompt =
        `You are transcribing a specific annotated region of a handwritten note.
This region is tagged as: "${tag ?? "unlabeled"}".
${hwContext ? `\nHandwriting notes from user corrections:\n${hwContext}\n` : ""}
Tasks:
1. Transcribe all text visible in this image region verbatim. Mark unclear text as [unclear].
2. Return a short, well-formatted Markdown summary of the region.
3. Keep the provided tag value unless it is empty.`;
    } else {
      maxTokens = 5000;
      schema = noteSchema();
      const pageWord = images.length > 1
        ? `these ${images.length} pages`
        : "this page";
      prompt =
        `You are an expert at reading handwritten notes and organizing information clearly.
${hwContext ? `\nHandwriting notes from previous user corrections:\n${hwContext}\nPlease apply these style notes when transcribing.\n` : ""}
Analyze ${pageWord}.

Return:
- A concise descriptive title, max 60 characters.
- A complete verbatim transcription preserving line breaks. Mark unclear text as [unclear].
- The same content reorganized as Markdown using headings, bullets, and bold key terms.
- A 2-3 sentence summary.
- 3 to 8 lowercase topic tags.
- 3 to 8 key points.`;
    }

    const aiRes = await fetch(OPENAI_URL, {
      method: "POST",
      headers: {
        "authorization": `Bearer ${openaiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: resolveOpenAIModel(profile?.model),
        store: false,
        max_output_tokens: maxTokens,
        text: {
          format: {
            type: "json_schema",
            name: mode === "region" ? "paperbrain_region" : "paperbrain_note",
            strict: true,
            schema,
          },
        },
        input: [
          {
            role: "user",
            content: [
              ...imageBlocks,
              { type: "input_text", text: prompt },
            ],
          },
        ],
      }),
    });

    if (!aiRes.ok) {
      const err = await aiRes.json().catch(() => ({}));
      throw new Error(err.error?.message ?? `OpenAI error ${aiRes.status}`);
    }

    const aiData = await aiRes.json();
    const parsed = parseJSON(extractOutputText(aiData));

    if (mode === "region") {
      return json({ ok: true, region: parsed }, 200);
    }

    if (noteId) {
      const { data: note, error: updateErr } = await admin
        .from("notes")
        .update({
          title: parsed.title ?? "Untitled",
          transcription: parsed.transcription ?? "",
          organized: parsed.organized ?? "",
          summary: parsed.summary ?? "",
          tags: normalizeStringArray(parsed.tags),
          key_points: normalizeStringArray(parsed.keyPoints),
          source_type: images.length > 1 ? "pdf" : "image",
          processing_state: "done",
          error_message: null,
        })
        .eq("id", noteId)
        .eq("user_id", user.id)
        .select()
        .single();

      if (updateErr) throw updateErr;
      return json({ ok: true, note }, 200);
    }

    const { data: note, error: insertErr } = await admin
      .from("notes")
      .insert({
        user_id: user.id,
        title: parsed.title ?? "Untitled",
        transcription: parsed.transcription ?? "",
        organized: parsed.organized ?? "",
        summary: parsed.summary ?? "",
        tags: normalizeStringArray(parsed.tags),
        key_points: normalizeStringArray(parsed.keyPoints),
        source_type: images.length > 1 ? "pdf" : "image",
        processing_state: "done",
      })
      .select()
      .single();

    if (insertErr) throw insertErr;

    const imageRows = [];
    for (let i = 0; i < images.length; i++) {
      const dataUrl = images[i];
      const comma = dataUrl.indexOf(",");
      const mediaType = dataUrl.slice(5, comma).split(";")[0] || "image/jpeg";
      const ext = mediaType === "image/png" ? "png" : mediaType === "image/webp" ? "webp" : "jpg";
      const base64 = dataUrl.slice(comma + 1);
      const binary = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
      const path = `${user.id}/${note.id}/${i}.${ext}`;

      const { error: uploadErr } = await admin.storage.from("note-images").upload(path, binary, {
        contentType: mediaType,
        upsert: true,
      });
      if (uploadErr) throw uploadErr;

      imageRows.push({
        note_id: note.id,
        user_id: user.id,
        storage_path: path,
        page_number: i,
      });
    }

    if (imageRows.length) {
      const { error: imageErr } = await admin.from("note_images").insert(imageRows);
      if (imageErr) throw imageErr;
    }

    return json({ ok: true, note }, 200);
  } catch (err) {
    console.error("[process-note]", err);
    return json({ error: String(err) }, 500);
  }
});

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

function noteSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["title", "transcription", "organized", "summary", "tags", "keyPoints"],
    properties: {
      title: { type: "string" },
      transcription: { type: "string" },
      organized: { type: "string" },
      summary: { type: "string" },
      tags: {
        type: "array",
        items: { type: "string" },
      },
      keyPoints: {
        type: "array",
        items: { type: "string" },
      },
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
