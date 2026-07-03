-- ═══════════════════════════════════════════════════════════════
-- foto-compare: Organizations, chat groups and shared check assets
-- Выполнить в Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS organizations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT UNIQUE,
  created_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS organization_members (
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role            TEXT NOT NULL DEFAULT 'member'
                  CHECK (role IN ('owner','admin','technologist','operator','viewer','member')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, user_id)
);

CREATE TABLE IF NOT EXISTS chat_groups (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  kind            TEXT NOT NULL DEFAULT 'group'
                  CHECK (kind IN ('organization','group','direct')),
  created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_deleted      BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS chat_group_members (
  group_id   UUID REFERENCES chat_groups(id) ON DELETE CASCADE,
  user_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role       TEXT NOT NULL DEFAULT 'member'
             CHECK (role IN ('admin','member','viewer')),
  joined_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  group_id        UUID REFERENCES chat_groups(id) ON DELETE CASCADE,
  sender_id       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  message_type    TEXT NOT NULL DEFAULT 'text'
                  CHECK (message_type IN ('text','check_result','image','system')),
  text            TEXT,
  check_result_id UUID REFERENCES check_results(id) ON DELETE SET NULL,
  reply_to_id     UUID REFERENCES chat_messages(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_deleted      BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS check_assets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  check_result_id UUID REFERENCES check_results(id) ON DELETE CASCADE,
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  kind            TEXT NOT NULL
                  CHECK (kind IN ('reference','sample','delta_map','geometry_map','preview','report')),
  storage_path    TEXT,
  local_hint      TEXT,
  visibility      TEXT NOT NULL DEFAULT 'local'
                  CHECK (visibility IN ('local','private','chat_shared','public_link')),
  expires_at      TIMESTAMPTZ,
  created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS check_comments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  check_result_id UUID REFERENCES check_results(id) ON DELETE CASCADE,
  asset_id        UUID REFERENCES check_assets(id) ON DELETE SET NULL,
  group_id        UUID REFERENCES chat_groups(id) ON DELETE SET NULL,
  author_id       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  text            TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_groups_org ON chat_groups(organization_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_group_created ON chat_messages(group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_check_assets_result ON check_assets(check_result_id);
CREATE INDEX IF NOT EXISTS idx_check_comments_result ON check_comments(check_result_id, created_at);

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE check_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE check_comments ENABLE ROW LEVEL SECURITY;

-- Черновые политики для прототипа. Перед production ограничить по membership.
CREATE POLICY "auth_read_organizations" ON organizations
FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_write_organizations" ON organizations
FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "auth_read_org_members" ON organization_members
FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_write_org_members" ON organization_members
FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "auth_read_chat_groups" ON chat_groups
FOR SELECT TO authenticated USING (NOT is_deleted);
CREATE POLICY "auth_write_chat_groups" ON chat_groups
FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "auth_read_chat_group_members" ON chat_group_members
FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_write_chat_group_members" ON chat_group_members
FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "auth_read_chat_messages" ON chat_messages
FOR SELECT TO authenticated USING (NOT is_deleted);
CREATE POLICY "auth_write_chat_messages" ON chat_messages
FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "auth_read_check_assets" ON check_assets
FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_write_check_assets" ON check_assets
FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "auth_read_check_comments" ON check_comments
FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_write_check_comments" ON check_comments
FOR ALL TO authenticated USING (true) WITH CHECK (true);

INSERT INTO storage.buckets (id, name, public)
VALUES ('check-assets', 'check-assets', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "auth_upload_check_assets" ON storage.objects
FOR INSERT TO authenticated WITH CHECK (bucket_id = 'check-assets');

CREATE POLICY "auth_read_check_assets_storage" ON storage.objects
FOR SELECT TO authenticated USING (bucket_id = 'check-assets');
