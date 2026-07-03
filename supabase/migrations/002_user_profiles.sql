-- ═══════════════════════════════════════════════════════════════
-- foto-compare: User nicknames for login and future chat
-- Выполнить в Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS user_profiles (
  user_id      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email        TEXT NOT NULL UNIQUE,
  nickname     TEXT NOT NULL UNIQUE,
  display_name TEXT,
  organization_name TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS organization_name TEXT;

CREATE INDEX IF NOT EXISTS idx_user_profiles_nickname ON user_profiles(nickname);

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_read_user_profiles"
ON user_profiles
FOR SELECT
TO anon, authenticated
USING (true);

CREATE POLICY "auth_insert_own_user_profile"
ON user_profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "auth_update_own_user_profile"
ON user_profiles
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
