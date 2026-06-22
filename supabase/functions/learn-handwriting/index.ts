/**
 * learn-handwriting - Supabase Edge Function
 *
 * Stores user corrections and periodically calls OpenAI to synthesize a compact
 * handwriting style guide stored on the user's profile.
 *
 * POST /functions/v1/learn-handwriting
 * Auth: Bearer <supabase-access-token>
 * Body:
 *   {
 *     noteId?: string,
 *     note_id?: string,
 *     corrections?: [{ original: string, correction: string, context?: string }],
 *     clarifications?: [{ croppedImage?: string, word: string, context?: string }]
 *   }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPENAI_URL = "https://api.openai.com/v1/responses";
const SYNTHESIZE_THRESHOLD = 5;
const MAX_CONTEXT_CHARS = 600;

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
    if (!user) return json({ error: "Unauthorized" }, 401);

    const admin = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const body = await req.json();
    const noteId = body.noteId ?? body.note_id ?? null;
    const corrections = body.corrections ?? [];
    const clarifications = body.clarifications ?? [];

    if (noteId) await assertOwnedNote(admin, noteId, user.id);

    const clarificationRows = clarifications.map((c: { word: string; context?: string; guess?: string }) => ({
      user_id: user.id,
      note_id: noteId,
      // Prefer the AI's original guess so the style guide learns "read X -> wrote Y".
      original: c.guess && String(c.guess).trim() ? String(c.guess).trim() : "[unclear]",
      correction: c.word,
      context_snippet: c.context ?? null,
    }));

    const correctionRows = corrections.map((c: { original: string; correction: string; context?: string }) => ({
      user_id: user.id,
      note_id: noteId,
      original: c.original,
      correction: c.correction,
      context_snippet: c.context ?? null,
    }));

    const allRows = [...correctionRows, ...clarificationRows]
      .filter((row) => String(row.original ?? "").trim() && String(row.correction ?? "").trim());

    if (allRows.length) {
      const { error: insErr } = await admin
        .from("handwriting_corrections")
        .insert(allRows);
      if (insErr) throw insErr;
    }

    const { count } = await admin
      .from("handwriting_corrections")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id);

    const total = count ?? 0;
    const shouldSynthesize =
      total > 0 &&
      (allRows.length === 0 || total % SYNTHESIZE_THRESHOLD === 0 || allRows.length >= SYNTHESIZE_THRESHOLD);

    if (!shouldSynthesize) {
      return json({ ok: true, synthesized: false, total });
    }

    const { data: recent } = await admin
      .from("handwriting_corrections")
      .select("original, correction, context_snippet")
      .eq("user_id", user.id)
      .order("applied_at", { ascending: false })
      .limit(30);

    const examples = (recent ?? [])
      .map((r) =>
        `- AI read: "${r.original}" -> User wrote: "${r.correction}"${
          r.context_snippet ? ` (context: "...${r.context_snippet}...")` : ""
        }`
      )
      .join("\n");

    const { data: profile } = await admin
      .from("profiles")
      .select("handwriting_context, model")
      .eq("id", user.id)
      .single();

    const existing = profile?.handwriting_context ?? "";
    const openaiKey = Deno.env.get("OPENAI_API_KEY")!;

    const prompt =
      `You are analyzing handwriting corrections to build a compact style guide.

${existing ? `EXISTING STYLE GUIDE (update it, do not blindly replace it):\n${existing}\n\n` : ""}RECENT CORRECTIONS:
${examples}

Extract concise, actionable style notes that help an AI read this person's handwriting in the future.
Focus on letter-shape confusions, punctuation habits, systematic substitutions, and recurring words.
Write in third person ("User's handwriting...").
Return one compact paragraph, max 4 sentences and under ${MAX_CONTEXT_CHARS} characters.`;

    const aiRes = await fetch(OPENAI_URL, {
      method: "POST",
      headers: {
        "authorization": `Bearer ${openaiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: resolveOpenAIModel(profile?.model),
        store: false,
        max_output_tokens: 300,
        input: prompt,
      }),
    });

    if (!aiRes.ok) {
      const err = await aiRes.json().catch(() => ({}));
      throw new Error(err.error?.message ?? `OpenAI error ${aiRes.status}`);
    }

    const aiData = await aiRes.json();
    let newContext = extractOutputText(aiData).trim();
    if (newContext.length > MAX_CONTEXT_CHARS) {
      newContext = newContext.slice(0, MAX_CONTEXT_CHARS).trim();
    }

    const { error: updateErr } = await admin
      .from("profiles")
      .update({ handwriting_context: newContext })
      .eq("id", user.id);
    if (updateErr) throw updateErr;

    return json({ ok: true, synthesized: true, context: newContext, total });
  } catch (err) {
    console.error("[learn-handwriting]", err);
    return json({ error: String(err) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
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
