-- Secure organization and production-job chat.
-- Prerequisites: migrations 002, 004, 006, and 012.

BEGIN;

ALTER TABLE chat_groups
ADD COLUMN IF NOT EXISTS organization_id UUID
REFERENCES organizations(id) ON DELETE CASCADE;

ALTER TABLE chat_groups
ADD COLUMN IF NOT EXISTS name TEXT NOT NULL DEFAULT 'Чат';

ALTER TABLE chat_groups
ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'group';

ALTER TABLE chat_groups
ADD COLUMN IF NOT EXISTS created_by UUID
REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE chat_groups
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE chat_groups
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE chat_groups
ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE chat_groups
ADD COLUMN IF NOT EXISTS job_id UUID
REFERENCES production_jobs(id) ON DELETE CASCADE;

ALTER TABLE chat_groups
ADD COLUMN IF NOT EXISTS scope_key TEXT;

ALTER TABLE chat_groups
DROP CONSTRAINT IF EXISTS chat_groups_kind_check;

ALTER TABLE chat_groups
ADD CONSTRAINT chat_groups_kind_check
CHECK (kind IN ('organization', 'group', 'direct', 'job'));

CREATE UNIQUE INDEX IF NOT EXISTS chat_groups_scope_key
ON chat_groups(scope_key)
WHERE scope_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS chat_groups_job_idx
ON chat_groups(job_id, updated_at DESC);

ALTER TABLE chat_group_members
ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'member';

ALTER TABLE chat_group_members
ADD COLUMN IF NOT EXISTS joined_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS chat_group_members_identity_key
ON chat_group_members(group_id, user_id);

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS organization_id UUID
REFERENCES organizations(id) ON DELETE CASCADE;

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS group_id UUID
REFERENCES chat_groups(id) ON DELETE CASCADE;

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS sender_id UUID
REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS message_type TEXT NOT NULL DEFAULT 'text';

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS text TEXT;

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::JSONB;

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS protocol_owner_user_id UUID
REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS protocol_id TEXT;

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS asset_kind TEXT;

ALTER TABLE chat_messages
DROP CONSTRAINT IF EXISTS chat_messages_message_type_check;

ALTER TABLE chat_messages
ADD CONSTRAINT chat_messages_message_type_check
CHECK (
  message_type IN (
    'text',
    'check_result',
    'protocol',
    'image',
    'asset',
    'system'
  )
);

ALTER TABLE chat_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION can_access_chat_group_v1(
  target_group UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM chat_groups AS chat
    WHERE chat.id = target_group
      AND NOT chat.is_deleted
      AND (
        (
          chat.job_id IS NOT NULL
          AND can_view_production_job_v1(chat.job_id)
        )
        OR (
          chat.job_id IS NULL
          AND chat.kind = 'organization'
          AND chat.organization_id IS NOT NULL
          AND has_organization_role_v2(
            chat.organization_id,
            ARRAY['owner', 'admin', 'employee']
          )
        )
        OR (
          chat.job_id IS NULL
          AND chat.kind <> 'organization'
          AND (
            chat.created_by = auth.uid()
            OR EXISTS (
              SELECT 1
              FROM chat_group_members AS member
              WHERE member.group_id = chat.id
                AND member.user_id = auth.uid()
            )
          )
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION can_access_chat_group_v1(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION can_access_chat_group_v1(UUID) TO authenticated;

DROP POLICY IF EXISTS "auth_read_chat_groups" ON chat_groups;
DROP POLICY IF EXISTS "auth_write_chat_groups" ON chat_groups;
DROP POLICY IF EXISTS chat_groups_select_v1 ON chat_groups;
DROP POLICY IF EXISTS chat_groups_insert_v1 ON chat_groups;
DROP POLICY IF EXISTS chat_groups_update_v1 ON chat_groups;
DROP POLICY IF EXISTS chat_groups_delete_v1 ON chat_groups;
DROP POLICY IF EXISTS "read_organization_chat_groups" ON chat_groups;
DROP POLICY IF EXISTS "create_organization_chat_groups" ON chat_groups;
DROP POLICY IF EXISTS "update_organization_chat_groups" ON chat_groups;
DROP POLICY IF EXISTS "delete_organization_chat_groups" ON chat_groups;

CREATE POLICY chat_groups_select_v1
ON chat_groups
FOR SELECT
TO authenticated
USING (can_access_chat_group_v1(id));

DROP POLICY IF EXISTS "auth_read_chat_group_members" ON chat_group_members;
DROP POLICY IF EXISTS "auth_write_chat_group_members" ON chat_group_members;
DROP POLICY IF EXISTS chat_group_members_select_v1 ON chat_group_members;
DROP POLICY IF EXISTS chat_group_members_insert_v1 ON chat_group_members;
DROP POLICY IF EXISTS chat_group_members_update_v1 ON chat_group_members;
DROP POLICY IF EXISTS chat_group_members_delete_v1 ON chat_group_members;
DROP POLICY IF EXISTS "read_accessible_chat_group_members"
ON chat_group_members;
DROP POLICY IF EXISTS "manage_accessible_chat_group_members"
ON chat_group_members;

CREATE POLICY chat_group_members_select_v1
ON chat_group_members
FOR SELECT
TO authenticated
USING (can_access_chat_group_v1(group_id));

DROP POLICY IF EXISTS "auth_read_chat_messages" ON chat_messages;
DROP POLICY IF EXISTS "auth_write_chat_messages" ON chat_messages;
DROP POLICY IF EXISTS chat_messages_select_v1 ON chat_messages;
DROP POLICY IF EXISTS chat_messages_insert_v1 ON chat_messages;
DROP POLICY IF EXISTS chat_messages_update_v1 ON chat_messages;
DROP POLICY IF EXISTS chat_messages_delete_v1 ON chat_messages;
DROP POLICY IF EXISTS "read_organization_messages" ON chat_messages;
DROP POLICY IF EXISTS "create_organization_messages" ON chat_messages;
DROP POLICY IF EXISTS "update_own_messages" ON chat_messages;
DROP POLICY IF EXISTS "delete_own_messages" ON chat_messages;

CREATE POLICY chat_messages_select_v1
ON chat_messages
FOR SELECT
TO authenticated
USING (
  NOT is_deleted
  AND can_access_chat_group_v1(group_id)
);

CREATE POLICY chat_messages_insert_v1
ON chat_messages
FOR INSERT
TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND can_access_chat_group_v1(group_id)
  AND EXISTS (
    SELECT 1
    FROM chat_groups AS chat
    WHERE chat.id = group_id
      AND chat.organization_id IS NOT DISTINCT FROM organization_id
  )
);

CREATE OR REPLACE FUNCTION list_chat_sender_profiles_v1(
  target_group UUID
)
RETURNS TABLE(
  user_id UUID,
  nickname TEXT,
  display_name TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT can_access_chat_group_v1(target_group) THEN
    RAISE EXCEPTION 'Chat access denied';
  END IF;

  RETURN QUERY
  SELECT DISTINCT
    message.sender_id,
    COALESCE(profile.nickname, ''),
    COALESCE(profile.display_name, '')
  FROM chat_messages AS message
  LEFT JOIN user_profiles AS profile
    ON profile.user_id = message.sender_id
  WHERE message.group_id = target_group
    AND NOT message.is_deleted
    AND message.sender_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION ensure_default_chat_threads_v1()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  membership organization_members%ROWTYPE;
  organization_name TEXT;
  personal_group_id UUID;
  organization_group_id UUID;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  INSERT INTO chat_groups(
    organization_id,
    name,
    kind,
    created_by,
    scope_key
  )
  VALUES (
    NULL,
    'Личные заметки',
    'direct',
    current_user_id,
    'personal:' || current_user_id::TEXT
  )
  ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
  DO UPDATE SET updated_at = chat_groups.updated_at
  RETURNING id INTO personal_group_id;

  INSERT INTO chat_group_members(group_id, user_id, role)
  VALUES (personal_group_id, current_user_id, 'admin')
  ON CONFLICT DO NOTHING;

  SELECT member.*
    INTO membership
  FROM organization_members AS member
  WHERE member.user_id = current_user_id
    AND member.role IN ('owner', 'admin', 'employee')
  ORDER BY
    CASE member.role
      WHEN 'owner' THEN 1
      WHEN 'admin' THEN 2
      ELSE 3
    END,
    member.created_at
  LIMIT 1;

  IF membership.organization_id IS NULL THEN
    RETURN;
  END IF;

  SELECT name INTO organization_name
  FROM organizations
  WHERE id = membership.organization_id;

  INSERT INTO chat_groups(
    organization_id,
    name,
    kind,
    created_by,
    scope_key
  )
  VALUES (
    membership.organization_id,
    COALESCE(organization_name, 'Организация') || ' · команда',
    'organization',
    current_user_id,
    'organization:' || membership.organization_id::TEXT
  )
  ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
  DO UPDATE SET name = EXCLUDED.name
  RETURNING id INTO organization_group_id;

  INSERT INTO chat_group_members(group_id, user_id, role)
  VALUES (
    organization_group_id,
    current_user_id,
    CASE
      WHEN membership.role IN ('owner', 'admin') THEN 'admin'
      ELSE 'member'
    END
  )
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET role = EXCLUDED.role;
END;
$$;

CREATE OR REPLACE FUNCTION ensure_job_chat_v1(
  target_job UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  selected_job production_jobs%ROWTYPE;
  selected_group_id UUID;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT can_view_production_job_v1(target_job) THEN
    RAISE EXCEPTION 'Production job access denied';
  END IF;

  SELECT * INTO selected_job
  FROM production_jobs
  WHERE id = target_job;

  INSERT INTO chat_groups(
    organization_id,
    job_id,
    name,
    kind,
    created_by,
    scope_key
  )
  VALUES (
    selected_job.organization_id,
    selected_job.id,
    'Работа № ' || selected_job.number,
    'job',
    current_user_id,
    'job:' || selected_job.id::TEXT
  )
  ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
  DO UPDATE SET name = EXCLUDED.name
  RETURNING id INTO selected_group_id;

  INSERT INTO chat_group_members(group_id, user_id, role)
  VALUES (selected_group_id, current_user_id, 'member')
  ON CONFLICT DO NOTHING;

  RETURN selected_group_id;
END;
$$;

CREATE OR REPLACE FUNCTION touch_chat_group_after_message_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE chat_groups
  SET updated_at = NEW.created_at
  WHERE id = NEW.group_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_messages_touch_group_v1 ON chat_messages;
CREATE TRIGGER chat_messages_touch_group_v1
AFTER INSERT ON chat_messages
FOR EACH ROW
EXECUTE FUNCTION touch_chat_group_after_message_v1();

REVOKE ALL ON FUNCTION ensure_default_chat_threads_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION ensure_job_chat_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_chat_sender_profiles_v1(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ensure_default_chat_threads_v1()
TO authenticated;
GRANT EXECUTE ON FUNCTION ensure_job_chat_v1(UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION list_chat_sender_profiles_v1(UUID)
TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON chat_groups FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON chat_group_members FROM authenticated;
REVOKE UPDATE, DELETE ON chat_messages FROM authenticated;
GRANT SELECT ON chat_groups TO authenticated;
GRANT SELECT ON chat_group_members TO authenticated;
GRANT SELECT, INSERT ON chat_messages TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'chat_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE chat_messages;
  END IF;
END;
$$;

COMMIT;
