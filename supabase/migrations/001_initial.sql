-- PaperBrain Database Schema
-- Run with: supabase db push  (or supabase migration up)

-- ── Extensions ────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── Profiles (extends auth.users) ─────────────────────────────
CREATE TABLE IF NOT EXISTS profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  display_name    TEXT,
  model           TEXT    NOT NULL DEFAULT 'gpt-5.4-mini',
  -- Compact style guide accumulated from handwriting corrections
  -- e.g. "User's 'a' often looks like 'o'; dotted 'i' is often missed"
  handwriting_context TEXT NOT NULL DEFAULT '',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own profile"   ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);

-- Auto-create profile on sign-up
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO profiles (id, display_name)
  VALUES (NEW.id, SPLIT_PART(NEW.email, '@', 1));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── Notes ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title            TEXT NOT NULL DEFAULT 'Untitled',
  transcription    TEXT NOT NULL DEFAULT '',
  organized        TEXT NOT NULL DEFAULT '',
  summary          TEXT NOT NULL DEFAULT '',
  tags             TEXT[]  NOT NULL DEFAULT '{}',
  key_points       TEXT[]  NOT NULL DEFAULT '{}',
  source_type      TEXT    NOT NULL DEFAULT 'image'  CHECK (source_type IN ('image','pdf')),
  processing_state TEXT    NOT NULL DEFAULT 'done'   CHECK (processing_state IN ('pending','transcribing','summarizing','done','error')),
  error_message    TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notes_user_id    ON notes(user_id);
CREATE INDEX IF NOT EXISTS notes_created_at ON notes(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS notes_tags       ON notes USING GIN(tags);

ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can CRUD own notes" ON notes FOR ALL USING (auth.uid() = user_id);

-- ── Note Images (stored in Supabase Storage) ───────────────────
CREATE TABLE IF NOT EXISTS note_images (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id      UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  storage_path TEXT NOT NULL,   -- path inside the 'note-images' storage bucket
  page_number  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS note_images_note_id ON note_images(note_id);

ALTER TABLE note_images ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can CRUD own images" ON note_images FOR ALL USING (auth.uid() = user_id);

-- ── Annotations (visual regions drawn on images) ──────────────
CREATE TABLE IF NOT EXISTS annotations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id     UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  image_index INTEGER NOT NULL DEFAULT 0,         -- which page (0-indexed)
  shape_type  TEXT NOT NULL CHECK (shape_type IN ('rect','ellipse','freehand')),
  -- rect:     { x, y, w, h }  (all 0-1 normalized to image dimensions)
  -- ellipse:  { cx, cy, rx, ry }
  -- freehand: { points: [[x,y], ...] }
  shape_data  JSONB NOT NULL,
  tag         TEXT,                               -- associated tag label
  label       TEXT,                               -- optional display label
  color       TEXT NOT NULL DEFAULT '#6366f1',    -- hex color
  -- AI-extracted content for this region (filled after region re-process)
  region_content TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS annotations_note_id ON annotations(note_id);

ALTER TABLE annotations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can CRUD own annotations" ON annotations FOR ALL USING (auth.uid() = user_id);

-- ── Relations (note ↔ note connections) ───────────────────────
CREATE TABLE IF NOT EXISTS relations (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  from_id    UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  to_id      UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  score      REAL NOT NULL DEFAULT 0 CHECK (score >= 0 AND score <= 1),
  reason     TEXT,
  manual     BOOLEAN NOT NULL DEFAULT false,   -- true = user drew this in mind map
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(from_id, to_id)
);

CREATE INDEX IF NOT EXISTS relations_from_id ON relations(from_id);
CREATE INDEX IF NOT EXISTS relations_to_id   ON relations(to_id);

ALTER TABLE relations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can CRUD own relations" ON relations FOR ALL USING (auth.uid() = user_id);

-- ── Handwriting Corrections (AI learning) ─────────────────────
CREATE TABLE IF NOT EXISTS handwriting_corrections (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  note_id         UUID REFERENCES notes(id) ON DELETE SET NULL,
  original        TEXT NOT NULL,    -- what the AI transcribed
  correction      TEXT NOT NULL,    -- what the user changed it to
  context_snippet TEXT,             -- surrounding text for context
  applied_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS corrections_user_id ON handwriting_corrections(user_id);

ALTER TABLE handwriting_corrections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can CRUD own corrections" ON handwriting_corrections FOR ALL USING (auth.uid() = user_id);

-- ── Mind Map Positions (user-arranged node layout) ────────────
CREATE TABLE IF NOT EXISTS mindmap_positions (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  node_type TEXT NOT NULL CHECK (node_type IN ('note','tag')),
  node_id   TEXT NOT NULL,    -- note UUID or tag string
  x         REAL NOT NULL,
  y         REAL NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, node_type, node_id)
);

ALTER TABLE mindmap_positions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can CRUD own positions" ON mindmap_positions FOR ALL USING (auth.uid() = user_id);

-- ── updated_at triggers ───────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER notes_updated_at    BEFORE UPDATE ON notes    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER mindmap_updated_at  BEFORE UPDATE ON mindmap_positions FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Private Storage Bucket + Policies ─────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'note-images',
  'note-images',
  false,
  15728640,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Users can upload own note images" ON storage.objects;
CREATE POLICY "Users can upload own note images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'note-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can view own note images" ON storage.objects;
CREATE POLICY "Users can view own note images"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'note-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can update own note images" ON storage.objects;
CREATE POLICY "Users can update own note images"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'note-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'note-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can delete own note images" ON storage.objects;
CREATE POLICY "Users can delete own note images"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'note-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
