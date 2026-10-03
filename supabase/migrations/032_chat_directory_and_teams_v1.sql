-- Chat navigation: searchable personal contacts, managed teams, archived teams,
-- and one work row with separate internal/customer channels in the client.
-- Prerequisites: migrations 016, 029, and 031.

BEGIN;

ALTER TABLE chat_groups
ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS chat_groups_team_archive_idx
ON chat_groups(organization_id, archived_at, updated_at DESC)
WHERE kind = 'group' AND NOT is_deleted;

CREATE OR REPLACE FUNCTION can_manage_chat_teams_v1(target_organization UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT has_organization_role_v2(target_organization, ARRAY['admin']);
$$;

CREATE OR REPLACE FUNCTION can_open_direct_chat_v1(target_user UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH current_membership AS (
    SELECT organization_id, role
    FROM organization_members
    WHERE user_id = auth.uid()
    ORDER BY created_at
    LIMIT 1
  ), target_membership AS (
    SELECT member.organization_id, member.role
    FROM organization_members AS member
    JOIN current_membership AS current
      ON current.organization_id = member.organization_id
    WHERE member.user_id = target_user
  )
  SELECT target_user IS DISTINCT FROM auth.uid()
    AND EXISTS (
      SELECT 1
      FROM current_membership AS current
      JOIN target_membership AS target
        ON target.organization_id = current.organization_id
      WHERE (
        current.role IN ('owner', 'admin', 'employee')
        AND (
          target.role IN ('owner', 'admin', 'employee')
          OR (
            target.role = 'customer'
            AND EXISTS (
              SELECT 1
              FROM production_job_participants AS customer_participant
              WHERE customer_participant.user_id = target_user
                AND customer_participant.participant_type = 'customer'
                AND can_view_production_job_v1(customer_participant.job_id)
            )
          )
        )
      ) OR (
        current.role = 'customer'
        AND target.role IN ('owner', 'admin', 'employee')
        AND EXISTS (
          SELECT 1
          FROM production_job_participants AS customer_participant
          JOIN production_jobs AS job
            ON job.id = customer_participant.job_id
          WHERE customer_participant.user_id = auth.uid()
            AND customer_participant.participant_type = 'customer'
            AND can_view_production_job_v1(job.id)
            AND (
              job.created_by = target_user
              OR EXISTS (
                SELECT 1
                FROM production_job_participants AS staff_participant
                WHERE staff_participant.job_id = job.id
                  AND staff_participant.user_id = target_user
                  AND staff_participant.participant_type IN ('operator', 'manager')
              )
            )
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION search_chat_contacts_v1(
  search_text TEXT DEFAULT '',
  result_limit INTEGER DEFAULT 30
)
RETURNS TABLE(
  user_id UUID,
  display_name TEXT,
  nickname TEXT,
  role_label TEXT,
  can_add_to_team BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  clean_search TEXT := lower(trim(COALESCE(search_text, '')));
  safe_limit INTEGER := LEAST(GREATEST(COALESCE(result_limit, 30), 1), 100);
  current_organization UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT member.organization_id INTO current_organization
  FROM organization_members AS member
  WHERE member.user_id = auth.uid()
  ORDER BY member.created_at
  LIMIT 1;

  IF current_organization IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    member.user_id,
    COALESCE(profile.display_name, '')::TEXT,
    COALESCE(profile.nickname, '')::TEXT,
    CASE member.role
      WHEN 'owner' THEN 'Владелец'
      WHEN 'admin' THEN 'Администратор'
      WHEN 'employee' THEN 'Сотрудник'
      ELSE 'Представитель заказчика'
    END::TEXT,
    (can_manage_chat_teams_v1(current_organization)
      AND member.role IN ('owner', 'admin', 'employee'))
  FROM organization_members AS member
  LEFT JOIN user_profiles AS profile ON profile.user_id = member.user_id
  WHERE member.organization_id = current_organization
    AND member.user_id <> auth.uid()
    AND can_open_direct_chat_v1(member.user_id)
    AND (
      clean_search = ''
      OR lower(COALESCE(profile.display_name, '')) LIKE '%' || clean_search || '%'
      OR lower(COALESCE(profile.nickname, '')) LIKE '%' || clean_search || '%'
    )
  ORDER BY lower(COALESCE(NULLIF(profile.display_name, ''), profile.nickname, ''))
  LIMIT safe_limit;
END;
$$;

CREATE OR REPLACE FUNCTION open_direct_chat_v1(target_user UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  target_organization UUID;
  selected_group UUID;
  direct_scope TEXT;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT can_open_direct_chat_v1(target_user) THEN
    RAISE EXCEPTION 'Direct chat access denied';
  END IF;

  SELECT current_member.organization_id INTO target_organization
  FROM organization_members AS current_member
  JOIN organization_members AS target_member
    ON target_member.organization_id = current_member.organization_id
   AND target_member.user_id = target_user
  WHERE current_member.user_id = current_user_id
  ORDER BY current_member.created_at
  LIMIT 1;

  direct_scope := 'direct:' || target_organization::TEXT || ':'
    || LEAST(current_user_id::TEXT, target_user::TEXT)
    || ':' || GREATEST(current_user_id::TEXT, target_user::TEXT);

  INSERT INTO chat_groups(
    organization_id, name, kind, created_by, scope_key
  ) VALUES (
    target_organization, 'Личный диалог', 'direct', current_user_id, direct_scope
  )
  ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
  DO UPDATE SET is_deleted = FALSE
  RETURNING id INTO selected_group;

  INSERT INTO chat_group_members(group_id, user_id, role)
  VALUES
    (selected_group, current_user_id, 'member'),
    (selected_group, target_user, 'member')
  ON CONFLICT (group_id, user_id) DO NOTHING;

  INSERT INTO chat_thread_reads(group_id, user_id, last_read_at)
  VALUES
    (selected_group, current_user_id, now()),
    (selected_group, target_user, now())
  ON CONFLICT (group_id, user_id) DO NOTHING;

  RETURN selected_group;
END;
$$;

CREATE OR REPLACE FUNCTION list_chat_team_members_v1(target_group UUID)
RETURNS TABLE(user_id UUID, display_name TEXT, nickname TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM chat_groups AS chat
    WHERE chat.id = target_group
      AND chat.kind = 'group'
      AND can_access_chat_group_v1(chat.id)
  ) THEN
    RAISE EXCEPTION 'Chat team access denied';
  END IF;

  RETURN QUERY
  SELECT member.user_id,
    COALESCE(profile.display_name, '')::TEXT,
    COALESCE(profile.nickname, '')::TEXT
  FROM chat_group_members AS member
  LEFT JOIN user_profiles AS profile ON profile.user_id = member.user_id
  WHERE member.group_id = target_group
    AND member.user_id <> auth.uid()
  ORDER BY lower(COALESCE(NULLIF(profile.display_name, ''), profile.nickname, ''));
END;
$$;

CREATE OR REPLACE FUNCTION create_chat_team_v1(
  team_name TEXT,
  member_user_ids UUID[] DEFAULT '{}'::UUID[]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_organization UUID;
  selected_group UUID;
  clean_name TEXT := trim(COALESCE(team_name, ''));
  clean_members UUID[] := COALESCE(member_user_ids, '{}'::UUID[]);
BEGIN
  SELECT member.organization_id INTO target_organization
  FROM organization_members AS member
  WHERE member.user_id = auth.uid() AND member.role = 'admin'
  ORDER BY member.created_at
  LIMIT 1;

  IF target_organization IS NULL THEN
    RAISE EXCEPTION 'Only an administrator can create a team';
  END IF;
  IF length(clean_name) NOT BETWEEN 2 AND 80 THEN
    RAISE EXCEPTION 'Team name must contain 2-80 characters';
  END IF;
  IF cardinality(clean_members) < 1 THEN
    RAISE EXCEPTION 'Select at least one team member';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(clean_members) AS selected(user_id)
    WHERE NOT EXISTS (
      SELECT 1 FROM organization_members AS member
      WHERE member.organization_id = target_organization
        AND member.user_id = selected.user_id
        AND member.role IN ('owner', 'admin', 'employee')
    )
  ) THEN
    RAISE EXCEPTION 'A selected user is not an internal organization member';
  END IF;

  INSERT INTO chat_groups(organization_id, name, kind, created_by)
  VALUES (target_organization, clean_name, 'group', auth.uid())
  RETURNING id INTO selected_group;

  INSERT INTO chat_group_members(group_id, user_id, role)
  VALUES (selected_group, auth.uid(), 'admin')
  ON CONFLICT (group_id, user_id) DO UPDATE SET role = EXCLUDED.role;

  INSERT INTO chat_group_members(group_id, user_id, role)
  SELECT selected_group, selected.user_id, 'member'
  FROM (SELECT DISTINCT unnest(clean_members) AS user_id) AS selected
  ON CONFLICT (group_id, user_id) DO NOTHING;

  INSERT INTO chat_thread_reads(group_id, user_id, last_read_at)
  SELECT selected_group, member.user_id, now()
  FROM chat_group_members AS member
  WHERE member.group_id = selected_group
  ON CONFLICT (group_id, user_id) DO NOTHING;

  RETURN selected_group;
END;
$$;

CREATE OR REPLACE FUNCTION update_chat_team_v1(
  target_group UUID,
  team_name TEXT,
  member_user_ids UUID[] DEFAULT '{}'::UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_chat chat_groups%ROWTYPE;
  clean_name TEXT := trim(COALESCE(team_name, ''));
  clean_members UUID[] := COALESCE(member_user_ids, '{}'::UUID[]);
BEGIN
  SELECT * INTO selected_chat FROM chat_groups
  WHERE id = target_group AND kind = 'group' FOR UPDATE;
  IF selected_chat.id IS NULL
    OR NOT can_manage_chat_teams_v1(selected_chat.organization_id) THEN
    RAISE EXCEPTION 'Only an administrator can edit a team';
  END IF;
  IF selected_chat.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'Restore the team before editing it';
  END IF;
  IF length(clean_name) NOT BETWEEN 2 AND 80 THEN
    RAISE EXCEPTION 'Team name must contain 2-80 characters';
  END IF;
  IF cardinality(clean_members) < 1 THEN
    RAISE EXCEPTION 'Select at least one team member';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(clean_members) AS selected(user_id)
    WHERE NOT EXISTS (
      SELECT 1 FROM organization_members AS member
      WHERE member.organization_id = selected_chat.organization_id
        AND member.user_id = selected.user_id
        AND member.role IN ('owner', 'admin', 'employee')
    )
  ) THEN
    RAISE EXCEPTION 'A selected user is not an internal organization member';
  END IF;

  UPDATE chat_groups SET name = clean_name, updated_at = now()
  WHERE id = selected_chat.id;
  DELETE FROM chat_group_members WHERE group_id = selected_chat.id;
  INSERT INTO chat_group_members(group_id, user_id, role)
  VALUES (selected_chat.id, auth.uid(), 'admin');
  INSERT INTO chat_group_members(group_id, user_id, role)
  SELECT selected_chat.id, selected.user_id, 'member'
  FROM (SELECT DISTINCT unnest(clean_members) AS user_id) AS selected
  ON CONFLICT (group_id, user_id) DO NOTHING;
  INSERT INTO chat_thread_reads(group_id, user_id, last_read_at)
  SELECT selected_chat.id, member.user_id, now()
  FROM chat_group_members AS member
  WHERE member.group_id = selected_chat.id
  ON CONFLICT (group_id, user_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION archive_chat_team_v1(target_group UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_chat chat_groups%ROWTYPE;
BEGIN
  SELECT * INTO selected_chat FROM chat_groups
  WHERE id = target_group AND kind = 'group' FOR UPDATE;
  IF selected_chat.id IS NULL
    OR NOT can_manage_chat_teams_v1(selected_chat.organization_id) THEN
    RAISE EXCEPTION 'Only an administrator can archive a team';
  END IF;
  UPDATE chat_groups SET archived_at = now(), updated_at = now()
  WHERE id = selected_chat.id;
END;
$$;

CREATE OR REPLACE FUNCTION restore_chat_team_v1(target_group UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_chat chat_groups%ROWTYPE;
BEGIN
  SELECT * INTO selected_chat FROM chat_groups
  WHERE id = target_group AND kind = 'group' FOR UPDATE;
  IF selected_chat.id IS NULL
    OR NOT can_manage_chat_teams_v1(selected_chat.organization_id) THEN
    RAISE EXCEPTION 'Only an administrator can restore a team';
  END IF;
  UPDATE chat_groups SET archived_at = NULL, updated_at = now()
  WHERE id = selected_chat.id;
END;
$$;

CREATE OR REPLACE FUNCTION list_accessible_chat_threads_v2()
RETURNS TABLE(
  thread_id UUID,
  thread_name TEXT,
  thread_kind TEXT,
  organization_id UUID,
  job_id UUID,
  updated_at TIMESTAMPTZ,
  customer_shared BOOLEAN,
  can_manage_customer_access BOOLEAN,
  job_status TEXT,
  customer_name TEXT,
  unread_count BIGINT,
  archived_at TIMESTAMPTZ,
  can_manage BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  INSERT INTO chat_thread_reads(group_id, user_id, last_read_at)
  SELECT chat.id, auth.uid(), now()
  FROM chat_groups AS chat
  WHERE can_access_chat_group_v1(chat.id) AND NOT chat.is_deleted
  ON CONFLICT (group_id, user_id) DO NOTHING;

  RETURN QUERY
  SELECT
    chat.id,
    CASE
      WHEN chat.kind = 'direct' AND chat.organization_id IS NOT NULL
        THEN COALESCE(NULLIF(other_profile.display_name, ''),
          NULLIF(other_profile.nickname, ''), 'Личный диалог')
      ELSE chat.name
    END::TEXT,
    chat.kind,
    chat.organization_id,
    chat.job_id,
    chat.updated_at,
    COALESCE(job.customer_access_status = 'shared', FALSE),
    CASE WHEN chat.job_id IS NULL THEN FALSE
      ELSE can_manage_production_job_customer_access_v1(chat.job_id) END,
    COALESCE(job.status, ''),
    COALESCE(customer.name, job.requested_customer_name, ''),
    COUNT(message.id) FILTER (
      WHERE message.sender_id IS DISTINCT FROM auth.uid()
    ),
    chat.archived_at,
    (chat.kind = 'group'
      AND can_manage_chat_teams_v1(chat.organization_id))
  FROM chat_groups AS chat
  LEFT JOIN production_jobs AS job ON job.id = chat.job_id
  LEFT JOIN organization_customers AS customer ON customer.id = job.customer_id
  LEFT JOIN chat_thread_reads AS read_state
    ON read_state.group_id = chat.id AND read_state.user_id = auth.uid()
  LEFT JOIN chat_messages AS message
    ON message.group_id = chat.id
   AND NOT message.is_deleted
   AND message.created_at > COALESCE(
     read_state.last_read_at, '-infinity'::TIMESTAMPTZ
   )
  LEFT JOIN LATERAL (
    SELECT profile.display_name, profile.nickname
    FROM chat_group_members AS direct_member
    LEFT JOIN user_profiles AS profile ON profile.user_id = direct_member.user_id
    WHERE direct_member.group_id = chat.id
      AND direct_member.user_id <> auth.uid()
    ORDER BY direct_member.joined_at
    LIMIT 1
  ) AS other_profile ON chat.kind = 'direct' AND chat.organization_id IS NOT NULL
  WHERE can_access_chat_group_v1(chat.id) AND NOT chat.is_deleted
  GROUP BY chat.id, job.customer_access_status, job.status,
    job.requested_customer_name, customer.name,
    other_profile.display_name, other_profile.nickname
  ORDER BY chat.updated_at DESC;
END;
$$;

DROP POLICY IF EXISTS chat_messages_insert_v1 ON chat_messages;
CREATE POLICY chat_messages_insert_v1
ON chat_messages
FOR INSERT
TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND can_access_chat_group_v1(group_id)
  AND EXISTS (
    SELECT 1 FROM chat_groups AS chat
    WHERE chat.id = group_id
      AND chat.organization_id IS NOT DISTINCT FROM organization_id
      AND chat.kind <> 'service'
      AND (chat.kind <> 'group' OR chat.archived_at IS NULL)
  )
);

REVOKE ALL ON FUNCTION can_manage_chat_teams_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION can_open_direct_chat_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION search_chat_contacts_v1(TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION open_direct_chat_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_chat_team_members_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION create_chat_team_v1(TEXT, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION update_chat_team_v1(UUID, TEXT, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION archive_chat_team_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION restore_chat_team_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_accessible_chat_threads_v2() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION can_manage_chat_teams_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION can_open_direct_chat_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION search_chat_contacts_v1(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION open_direct_chat_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION list_chat_team_members_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION create_chat_team_v1(TEXT, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION update_chat_team_v1(UUID, TEXT, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION archive_chat_team_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION restore_chat_team_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION list_accessible_chat_threads_v2() TO authenticated;

COMMIT;
