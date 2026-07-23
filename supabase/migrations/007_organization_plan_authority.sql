-- Trimatrix organization plan authority.
-- Reads server-managed auth metadata directly so organization creation does
-- not depend on a potentially stale JWT after a subscription change.

BEGIN;

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
  current_plan TEXT;
  current_status TEXT;
  current_valid_until TIMESTAMPTZ;
  new_organization_id UUID;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT
    COALESCE(raw_app_meta_data ->> 'plan', 'free'),
    COALESCE(raw_app_meta_data ->> 'subscription_status', ''),
    CASE
      WHEN COALESCE(raw_app_meta_data ->> 'access_valid_until', '') = ''
        THEN NULL
      ELSE (raw_app_meta_data ->> 'access_valid_until')::TIMESTAMPTZ
    END
  INTO current_plan, current_status, current_valid_until
  FROM auth.users
  WHERE id = current_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Authenticated user was not found';
  END IF;

  IF current_plan NOT IN ('pro', 'enterprise') THEN
    RAISE EXCEPTION 'An organization requires Pro or Enterprise access';
  END IF;

  IF current_status NOT IN ('active', 'trialing', 'grace') THEN
    RAISE EXCEPTION 'The subscription is not active';
  END IF;

  IF current_valid_until IS NOT NULL AND current_valid_until <= now() THEN
    RAISE EXCEPTION 'The subscription has expired';
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

COMMIT;
