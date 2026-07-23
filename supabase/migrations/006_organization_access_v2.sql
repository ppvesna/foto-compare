-- Trimatrix organization access v2.
-- Prerequisite: migration 002 (user_profiles).
-- Validate on staging before production. This migration does not secure chat yet.

BEGIN;

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
  user_id          UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role             TEXT NOT NULL DEFAULT 'employee',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, user_id)
);

ALTER TABLE organization_members
DROP CONSTRAINT IF EXISTS organization_members_role_check;

UPDATE organization_members
SET role = CASE role
  WHEN 'technologist' THEN 'employee'
  WHEN 'operator' THEN 'employee'
  WHEN 'member' THEN 'employee'
  WHEN 'viewer' THEN 'customer'
  ELSE role
END;

ALTER TABLE organization_members
ADD CONSTRAINT organization_members_role_check
CHECK (role IN ('owner', 'admin', 'employee', 'customer'));

CREATE UNIQUE INDEX IF NOT EXISTS one_owner_per_organization
ON organization_members(organization_id)
WHERE role = 'owner';

CREATE INDEX IF NOT EXISTS organization_members_user_idx
ON organization_members(user_id);

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION is_organization_member_v2(
  target_organization UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM organization_members
    WHERE organization_id = target_organization
      AND user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION has_organization_role_v2(
  target_organization UUID,
  allowed_roles TEXT[]
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM organization_members
    WHERE organization_id = target_organization
      AND user_id = auth.uid()
      AND role = ANY(allowed_roles)
  );
$$;

REVOKE ALL ON FUNCTION is_organization_member_v2(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION has_organization_role_v2(UUID, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION is_organization_member_v2(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION has_organization_role_v2(UUID, TEXT[]) TO authenticated;

CREATE OR REPLACE FUNCTION current_organization_access_v2()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_membership organization_members%ROWTYPE;
  selected_name TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT membership.*
    INTO selected_membership
  FROM organization_members AS membership
  WHERE membership.user_id = auth.uid()
  ORDER BY
    CASE membership.role
      WHEN 'owner' THEN 1
      WHEN 'admin' THEN 2
      WHEN 'employee' THEN 3
      WHEN 'customer' THEN 4
      ELSE 5
    END,
    membership.created_at
  LIMIT 1;

  IF selected_membership.organization_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT name INTO selected_name
  FROM organizations
  WHERE id = selected_membership.organization_id;

  RETURN jsonb_build_object(
    'organization_id', selected_membership.organization_id,
    'organization_name', selected_name,
    'organization_role', selected_membership.role
  );
END;
$$;

REVOKE ALL ON FUNCTION current_organization_access_v2() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION current_organization_access_v2() TO authenticated;

CREATE OR REPLACE FUNCTION create_organization_v2(
  requested_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  current_plan TEXT := COALESCE(
    auth.jwt() -> 'app_metadata' ->> 'plan',
    'free'
  );
  new_organization_id UUID;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF current_plan NOT IN ('pro', 'enterprise') THEN
    RAISE EXCEPTION 'An organization requires Pro or Enterprise access';
  END IF;

  IF length(trim(requested_name)) < 2 THEN
    RAISE EXCEPTION 'Organization name is required';
  END IF;

  IF EXISTS (
    SELECT 1 FROM organization_members WHERE user_id = current_user_id
  ) THEN
    RAISE EXCEPTION 'The current user already belongs to an organization';
  END IF;

  INSERT INTO organizations(name, created_by)
  VALUES (trim(requested_name), current_user_id)
  RETURNING id INTO new_organization_id;

  INSERT INTO organization_members(organization_id, user_id, role)
  VALUES (new_organization_id, current_user_id, 'owner');

  UPDATE user_profiles
  SET organization_name = trim(requested_name), updated_at = now()
  WHERE user_id = current_user_id;

  RETURN new_organization_id;
END;
$$;

REVOKE ALL ON FUNCTION create_organization_v2(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_organization_v2(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION find_user_profile_by_nickname_v2(
  target_nickname TEXT
)
RETURNS TABLE(
  user_id UUID,
  nickname TEXT,
  display_name TEXT,
  organization_name TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM organization_members
    WHERE organization_members.user_id = auth.uid()
      AND organization_members.role IN ('owner', 'admin')
  ) THEN
    RAISE EXCEPTION 'Organization administration access required';
  END IF;

  RETURN QUERY
  SELECT
    profile.user_id,
    profile.nickname,
    COALESCE(profile.display_name, ''),
    COALESCE(profile.organization_name, '')
  FROM user_profiles AS profile
  WHERE lower(profile.nickname) = lower(trim(target_nickname))
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION find_user_profile_by_nickname_v2(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION find_user_profile_by_nickname_v2(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION list_organization_members_v2(
  target_organization UUID
)
RETURNS TABLE(
  user_id UUID,
  nickname TEXT,
  display_name TEXT,
  role TEXT,
  joined_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT has_organization_role_v2(
    target_organization,
    ARRAY['owner', 'admin']
  ) THEN
    RAISE EXCEPTION 'Organization administration access required';
  END IF;

  RETURN QUERY
  SELECT
    member.user_id,
    COALESCE(profile.nickname, ''),
    COALESCE(profile.display_name, ''),
    member.role,
    member.created_at
  FROM organization_members AS member
  LEFT JOIN user_profiles AS profile ON profile.user_id = member.user_id
  WHERE member.organization_id = target_organization
  ORDER BY
    CASE member.role
      WHEN 'owner' THEN 1
      WHEN 'admin' THEN 2
      WHEN 'employee' THEN 3
      WHEN 'customer' THEN 4
      ELSE 5
    END,
    member.created_at;
END;
$$;

REVOKE ALL ON FUNCTION list_organization_members_v2(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION list_organization_members_v2(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION assign_organization_member_v2(
  target_organization UUID,
  target_user UUID,
  target_role TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor_role TEXT;
  existing_target_role TEXT;
BEGIN
  SELECT role INTO actor_role
  FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = auth.uid();

  IF actor_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'Organization administration access required';
  END IF;

  IF target_role NOT IN ('admin', 'employee', 'customer') THEN
    RAISE EXCEPTION 'Unsupported assignable role: %', target_role;
  END IF;

  IF actor_role = 'admin' AND target_role = 'admin' THEN
    RAISE EXCEPTION 'Only the owner may appoint an administrator';
  END IF;

  SELECT role INTO existing_target_role
  FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = target_user;

  IF existing_target_role = 'owner' THEN
    RAISE EXCEPTION 'Owner role requires the ownership transfer workflow';
  END IF;

  IF actor_role = 'admin' AND existing_target_role = 'admin' THEN
    RAISE EXCEPTION 'An administrator cannot modify another administrator';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM user_profiles WHERE user_id = target_user) THEN
    RAISE EXCEPTION 'The target user must complete profile registration first';
  END IF;

  IF existing_target_role IS NULL AND EXISTS (
    SELECT 1
    FROM organization_members
    WHERE user_id = target_user
      AND organization_id <> target_organization
  ) THEN
    RAISE EXCEPTION
      'Organization switching is not implemented for this user yet';
  END IF;

  INSERT INTO organization_members(organization_id, user_id, role)
  VALUES (target_organization, target_user, target_role)
  ON CONFLICT (organization_id, user_id)
  DO UPDATE SET role = EXCLUDED.role;
END;
$$;

REVOKE ALL ON FUNCTION assign_organization_member_v2(UUID, UUID, TEXT)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION assign_organization_member_v2(UUID, UUID, TEXT)
TO authenticated;

DROP POLICY IF EXISTS "auth_read_organizations" ON organizations;
DROP POLICY IF EXISTS "auth_write_organizations" ON organizations;
DROP POLICY IF EXISTS "auth_read_org_members" ON organization_members;
DROP POLICY IF EXISTS "auth_write_org_members" ON organization_members;
DROP POLICY IF EXISTS "read_member_organizations_v2" ON organizations;
DROP POLICY IF EXISTS "update_managed_organizations_v2" ON organizations;
DROP POLICY IF EXISTS "delete_owned_organizations_v2" ON organizations;
DROP POLICY IF EXISTS "read_own_or_managed_memberships_v2"
ON organization_members;

CREATE POLICY "read_member_organizations_v2" ON organizations
FOR SELECT TO authenticated
USING (is_organization_member_v2(id));

CREATE POLICY "update_managed_organizations_v2" ON organizations
FOR UPDATE TO authenticated
USING (has_organization_role_v2(id, ARRAY['owner', 'admin']))
WITH CHECK (has_organization_role_v2(id, ARRAY['owner', 'admin']));

CREATE POLICY "delete_owned_organizations_v2" ON organizations
FOR DELETE TO authenticated
USING (has_organization_role_v2(id, ARRAY['owner']));

CREATE POLICY "read_own_or_managed_memberships_v2" ON organization_members
FOR SELECT TO authenticated
USING (
  user_id = auth.uid()
  OR has_organization_role_v2(organization_id, ARRAY['owner', 'admin'])
);

COMMIT;
