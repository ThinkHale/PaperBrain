/**
 * find-relations - Supabase Edge Function
 *
 * Finds related notes for a note using OpenAI.
 *
 * POST /functions/v1/find-relations
 * Auth: Bearer <supabase-access-token>
 * Body: { noteId: string } or { note_id: string }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPENAI_URL = "https://api.openai.com/v1/responses";

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
    const noteId = body.noteId ?? body.note_id;
    if (!noteId) return json({ error: "noteId required" }, 400);

    const { data: newNote } = await admin
      .from("notes")
      .select("id, title, summary, tags")
      .eq("id", noteId)
      .eq("user_id", user.id)
      .single();

    if (!newNote) return json({ error: "Note not found" }, 404);

    const { data: candidates } = await admin
      .from("notes")
      .select("id, title, summary, tags")
      .eq("user_id", user.id)
      .neq("id", noteId)
      .eq("processing_state", "done")
      .order("created_at", { ascending: false })
      .limit(40);

    if (!candidates?.length) return json({ ok: true, relations: [] });

    const prompt =
      `Find connections between notes.

NEW NOTE:
Title: ${newNote.title}
Summary: ${newNote.summary}
Tags: ${(newNote.tags ?? []).join(", ")}

EXISTING NOTES:
${JSON.stringify(candidates.map((n) => ({ id: n.id, title: n.title, summary: n.summary, tags: n.tags })), null, 2)}

Return the most related existing notes, up to 5.
Only include notes with meaningful topical overlap. Use scores from 0 to 1, and only include scores >= 0.45.
The id must exactly match one of the existing note IDs.`;

    const openaiKey = Deno.env.get("OPENAI_API_KEY")!;
    const { data: profile } = await admin
      .from("profiles")
      .select("model")
      .eq("id", user.id)
      .single();

    const aiRes = await fetch(OPENAI_URL, {
      method: "POST",
      headers: {
        "authorization": `Bearer ${openaiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: resolveOpenAIModel(profile?.model),
        store: false,
        max_output_tokens: 1200,
        text: {
          format: {
            type: "json_schema",
            name: "paperbrain_relations",
            strict: true,
            schema: relationSchema(),
          },
        },
        input: prompt,
      }),
    });

    if (!aiRes.ok) {
      const err = await aiRes.json().catch(() => ({}));
      throw new Error(err.error?.message ?? `OpenAI error ${aiRes.status}`);
    }

    const aiData = await aiRes.json();
    const parsed = parseJSON(extractOutputText(aiData));
    const candidateIds = new Set(candidates.map((n) => n.id));
    const related = ((parsed.relations ?? []) as { id: string; score: number; reason: string }[])
      .filter((r) => candidateIds.has(r.id))
      .filter((r) => Number.isFinite(r.score) && r.score >= 0.45)
      .slice(0, 5);

    await admin
      .from("relations")
      .delete()
      .eq("from_id", noteId)
      .eq("user_id", user.id)
      .eq("manual", false);

    if (!related.length) return json({ ok: true, relations: [] });

    const rows = related.map((r) => ({
      user_id: user.id,
      from_id: noteId,
      to_id: r.id,
      score: Math.min(1, Math.max(0, r.score)),
      reason: r.reason,
      manual: false,
    }));

    const { data: saved, error: relErr } = await admin
      .from("relations")
      .upsert(rows, { onConflict: "from_id,to_id" })
      .select();
    if (relErr) throw relErr;

    return json({ ok: true, relations: saved ?? rows });
  } catch (err) {
    console.error("[find-relations]", err);
    return json({ error: String(err) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

function parseJSON(text: string) {
  const match = text.trim().match(/\{[\s\S]*\}/);
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

function relationSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["relations"],
    properties: {
      relations: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["id", "score", "reason"],
          properties: {
            id: { type: "string" },
            score: { type: "number" },
            reason: { type: "string" },
          },
        },
      },
    },
  };
}
