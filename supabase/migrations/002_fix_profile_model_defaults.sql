UPDATE profiles
SET model = CASE model
  WHEN 'claude-sonnet-4-6' THEN 'gpt-5.4-mini'
  WHEN 'claude-sonnet-4-20250514' THEN 'gpt-5.4-mini'
  WHEN 'claude-haiku-4-5-20251001' THEN 'gpt-5.4-nano'
  WHEN 'claude-opus-4-6' THEN 'gpt-5.5'
  WHEN 'claude-opus-4-20250514' THEN 'gpt-5.5'
  ELSE model
END
WHERE model LIKE 'claude-%';

ALTER TABLE profiles
ALTER COLUMN model SET DEFAULT 'gpt-5.4-mini';
