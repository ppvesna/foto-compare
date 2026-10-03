-- Keep the owner's work permissions consistent with the app and guarantee
-- that every internal organization member has a writable service chat.

BEGIN;

CREATE OR REPLACE FUNCTION can_create_production_job_v1(
  target_organization UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT has_organization_role_v2(
    target_organization, ARRAY['owner', 'admin']
  )
    OR (
      has_organization_role_v2(target_organization, ARRAY['employee'])
      AND EXISTS (
        SELECT 1
        FROM organization_member_functions AS member_function
        WHERE member_function.organization_id = target_organization
          AND member_function.user_id = auth.uid()
          AND member_function.function_name = 'manager'
      )
    );
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
  service_group_id UUID;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  INSERT INTO chat_groups(
    organization_id, name, kind, created_by, scope_key
  )
  VALUES (
    NULL, 'Личные заметки', 'direct', current_user_id,
    'personal:' || current_user_id::TEXT
  )
  ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
  DO UPDATE SET updated_at = chat_groups.updated_at
  RETURNING id INTO personal_group_id;

  INSERT INTO chat_group_members(group_id, user_id, role)
  VALUES (personal_group_id, current_user_id, 'admin')
  ON CONFLICT DO NOTHING;

  SELECT member.* INTO membership
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

  IF membership.organization_id IS NULL THEN RETURN; END IF;

  SELECT name INTO organization_name
  FROM organizations
  WHERE id = membership.organization_id;

  INSERT INTO chat_groups(
    organization_id, name, kind, created_by, scope_key
  )
  VALUES (
    membership.organization_id,
    COALESCE(organization_name, 'Организация') || ' · команда',
    'organization', current_user_id,
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

  INSERT INTO chat_groups(
    organization_id, name, kind, created_by, scope_key
  )
  VALUES (
    membership.organization_id, 'Служебные', 'service', NULL,
    'organization:' || membership.organization_id::TEXT || ':service'
  )
  ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
  DO UPDATE SET
    name = EXCLUDED.name,
    kind = 'service',
    is_deleted = FALSE,
    archived_at = NULL
  RETURNING id INTO service_group_id;
END;
$$;

REVOKE ALL ON FUNCTION can_create_production_job_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION ensure_default_chat_threads_v1() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION can_create_production_job_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION ensure_default_chat_threads_v1() TO authenticated;

COMMIT;
