/**
 * transcribe-audio - Supabase Edge Function
 *
 * Downloads a voice recording from the private `note-assets` bucket and returns
 * its transcript. The client then sends the transcript to `process-note`
 * (mode: 'text', noteType: 'voice') to organize and tag it like any other note.
 *
 * POST /functions/v1/transcribe-audio
 * Auth: Bearer <supabase-access-token>
 * Body: { audioPath: string }   // path inside the note-assets bucket
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPENAI_TRANSCRIBE_URL = "https://api.openai.com/v1/audio/transcriptions";
const TRANSCRIBE_MODEL = "gpt-4o-transcribe";

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
    const audioPath: string | undefined = body.audioPath ?? body.audio_path;
    if (!audioPath) return json({ error: "audioPath required" }, 400);

    // Enforce ownership: the path must live under the caller's folder.
    if (!audioPath.startsWith(`${user.id}/`)) {
      return json({ error: "Forbidden" }, 403);
    }

    const { data: blob, error: dlErr } = await admin.storage
      .from("note-assets")
      .download(audioPath);
    if (dlErr || !blob) throw new Error(dlErr?.message ?? "Could not download audio");

    const openaiKey = Deno.env.get("OPENAI_API_KEY")!;
    const filename = audioPath.split("/").pop() || "audio.m4a";

    const form = new FormData();
    form.append("file", blob, filename);
    form.append("model", TRANSCRIBE_MODEL);
    form.append("response_format", "text");

    const res = await fetch(OPENAI_TRANSCRIBE_URL, {
      method: "POST",
      headers: { "authorization": `Bearer ${openaiKey}` },
      body: form,
    });

    if (!res.ok) {
      const err = await res.text().catch(() => "");
      throw new Error(err || `OpenAI transcription error ${res.status}`);
    }

    const transcript = (await res.text()).trim();

    await admin.from("usage_events").insert({ user_id: user.id, kind: "transcribe" });

    return json({ ok: true, transcript }, 200);
  } catch (err) {
    console.error("[transcribe-audio]", err);
    return json({ error: String(err) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
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
