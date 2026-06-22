# Illuminote

Your thoughts. Intelligently connected.

Upload photos or PDFs of handwritten notes, and let OpenAI transcribe, organize, and connect them across your devices.

## Features

- **Upload & Transcribe** — Drag-drop images or PDFs, or use your phone camera. OpenAI reads the handwriting and produces clean organized notes.
- **AI Handwriting Learning** — Edit any transcription mistake; the app learns your handwriting style over time to improve accuracy.
- **Visual Annotations** — Draw rectangles, ellipses, or freehand over regions of an image and tag them. Re-process a region for focused AI extraction.
- **Mind Map** — Force-directed graph showing notes and their tag/relation connections. Drag nodes, pin positions, filter by tag.
- **Cross-device Sync** — Account system via Supabase Auth; notes and images stored in the cloud.

---

## Setup

### 1 — Create a Supabase project

1. Go to [supabase.com](https://supabase.com) → New project
2. Copy your **Project URL** and **anon (public) key** from *Project Settings → API*

### 2 — Run the database migrations

Use the Supabase CLI from the repo root:

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase db push
```

Or, in the Supabase Dashboard → **SQL Editor**, run the migration files in order:

```
supabase/migrations/001_initial.sql
supabase/migrations/002_fix_profile_model_defaults.sql
supabase/migrations/003_v1_1.sql
```

This creates all tables, RLS policies, triggers, the private `note-images` and `note-assets` Storage buckets, and Storage policies. Migration `003` adds note categories, note types, unclear-word regions, the tag vocabulary, the To-Do list, voice/drawing asset columns, and usage metering.

### 3 — Deploy the Edge Functions

Install the [Supabase CLI](https://supabase.com/docs/guides/cli) if you haven't, then:

```bash
# Set your OpenAI API key as a secret
supabase secrets set OPENAI_API_KEY=sk-...

# Deploy all functions
supabase functions deploy process-note
supabase functions deploy find-relations
supabase functions deploy learn-handwriting
supabase functions deploy transcribe-audio
```

> **Important:** apply migration `003_v1_1.sql` *before* deploying the updated `process-note` function — it writes to the new note columns and tables.

### 4 — Configure the frontend

Edit `config.js` with your project details:

```js
window.ILLUMINOTE_CONFIG = {
  supabaseUrl:     "https://your-project.supabase.co",
  supabaseAnonKey: "eyJ...",
};
```

> **Note:** The anon key is safe to expose in the browser — Supabase RLS protects all data.

### 5 — Deploy to GitHub Pages

Push to the `main` branch. The included GitHub Actions workflow (`.github/workflows/deploy.yml`) deploys the repo root to GitHub Pages automatically.

---

## Development (local)

No build step required — the app is plain HTML/CSS/JS ES modules. Open `index.html` in a browser (via a local server, e.g. `npx serve .`) after filling in `config.js`.

---

## Architecture

| Layer | Technology |
|---|---|
| Frontend | Vanilla JS ES modules, D3.js (mind map), PDF.js, marked.js |
| Auth | Supabase Auth (email/password) |
| Database | Supabase PostgreSQL with Row Level Security |
| File storage | Supabase Storage (private bucket) |
| AI calls | Supabase Edge Functions (Deno) → OpenAI Responses API |
| Hosting | GitHub Pages |

The OpenAI API key lives only in the Edge Function secret — it is never sent to the browser.
