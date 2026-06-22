-- Illuminote V1.1 schema
-- Adds: richer note structure (categories, note_type, unclear_regions, drawing/audio),
--       a tag vocabulary (categories + topics), a To-Do list, and usage metering.
-- All changes are additive and safe to run against live data.

-- ── Notes: richer structure ───────────────────────────────────
ALTER TABLE notes ADD COLUMN IF NOT EXISTS note_type       TEXT    NOT NULL DEFAULT 'handwritten';
ALTER TABLE notes ADD COLUMN IF NOT EXISTS categories      TEXT[]  NOT NULL DEFAULT '{}';
ALTER TABLE notes ADD COLUMN IF NOT EXISTS unclear_regions JSONB   NOT NULL DEFAULT '[]';
ALTER TABLE notes ADD COLUMN IF NOT EXISTS drawing_path    TEXT;   -- raw PKDrawing blob in note-assets
ALTER TABLE notes ADD COLUMN IF NOT EXISTS audio_path      TEXT;   -- voice recording in note-assets

-- Widen source_type to cover the new capture kinds.
ALTER TABLE notes DROP CONSTRAINT IF EXISTS notes_source_type_check;
ALTER TABLE notes ADD  CONSTRAINT notes_source_type_check
  CHECK (source_type IN ('image','pdf','typed','drawing','voice','mixed'));

CREATE INDEX IF NOT EXISTS notes_categories ON notes USING GIN(categories);

-- ── Tag vocabulary (curated categories + finer topics) ────────
CREATE TABLE IF NOT EXISTS tags (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  kind       TEXT NOT NULL DEFAULT 'topic' CHECK (kind IN ('category','topic')),
  color      TEXT,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, kind, name)
);

CREATE INDEX IF NOT EXISTS tags_user ON tags(user_id, kind);

ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can CRUD own tags" ON tags FOR ALL USING (auth.uid() = user_id);

-- ── To-Do items (AI-extracted or manual) ──────────────────────
CREATE TABLE IF NOT EXISTS todos (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  note_id    UUID REFERENCES notes(id) ON DELETE SET NULL,
  text       TEXT NOT NULL,
  done       BOOLEAN NOT NULL DEFAULT false,
  due_date   DATE,
  source     TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('ai','manual')),
  position   INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS todos_user    ON todos(user_id, done, position);
CREATE INDEX IF NOT EXISTS todos_note_id ON todos(note_id);

ALTER TABLE todos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can CRUD own todos" ON todos FOR ALL USING (auth.uid() = user_id);

CREATE TRIGGER todos_updated_at BEFORE UPDATE ON todos
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Usage metering groundwork (recorded, NOT gated in V1.1) ────
CREATE TABLE IF NOT EXISTS usage_events (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL,            -- 'ai_process' | 'transcribe' | 'voice'
  units      INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS usage_user_time ON usage_events(user_id, created_at DESC);

ALTER TABLE usage_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own usage" ON usage_events FOR SELECT USING (auth.uid() = user_id);

-- ── Default category seeding ──────────────────────────────────
-- Shared helper so both the signup trigger and the backfill use one source of truth.
CREATE OR REPLACE FUNCTION seed_default_tags(target_user UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  defaults TEXT[][] := ARRAY[
    ARRAY['Business',  '#3B82F6'],
    ARRAY['Personal',  '#EC4899'],
    ARRAY['To-Do',     '#F59E0B'],
    ARRAY['Ideas',     '#8B5CF6'],
    ARRAY['Projects',  '#10B981'],
    ARRAY['Finance',   '#22C55E'],
    ARRAY['Health',    '#EF4444'],
    ARRAY['Learning',  '#06B6D4'],
    ARRAY['Reference', '#64748B']
  ];
  row TEXT[];
BEGIN
  FOREACH row SLICE 1 IN ARRAY defaults LOOP
    INSERT INTO tags (user_id, name, kind, color, is_default)
    VALUES (target_user, row[1], 'category', row[2], true)
    ON CONFLICT (user_id, kind, name) DO NOTHING;
  END LOOP;
END;
$$;

-- Extend the existing signup trigger to also seed default categories.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO profiles (id, display_name)
  VALUES (NEW.id, SPLIT_PART(NEW.email, '@', 1));
  PERFORM seed_default_tags(NEW.id);
  RETURN NEW;
END;
$$;

-- Backfill default categories for everyone who already has a profile (the TestFlight tester).
DO $$
DECLARE p RECORD;
BEGIN
  FOR p IN SELECT id FROM profiles LOOP
    PERFORM seed_default_tags(p.id);
  END LOOP;
END;
$$;

-- ── note-assets private bucket (audio + drawing blobs) ────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'note-assets',
  'note-assets',
  false,
  26214400,  -- 25 MB
  ARRAY['audio/m4a', 'audio/x-m4a', 'audio/mpeg', 'audio/mp4', 'audio/wav', 'application/octet-stream']
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Users can upload own note assets" ON storage.objects;
CREATE POLICY "Users can upload own note assets"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'note-assets'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can view own note assets" ON storage.objects;
CREATE POLICY "Users can view own note assets"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'note-assets'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can update own note assets" ON storage.objects;
CREATE POLICY "Users can update own note assets"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'note-assets'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'note-assets'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Users can delete own note assets" ON storage.objects;
CREATE POLICY "Users can delete own note assets"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'note-assets'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
