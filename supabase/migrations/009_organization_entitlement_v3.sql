-- Trimatrix organization-aware entitlement snapshot.
-- Personal users use their own protected auth metadata. Organization members
-- use the owner's active plan as the effective workspace plan while retaining
-- their own personal plan in the response.

BEGIN;

CREATE OR REPLACE FUNCTION current_entitlement_v3()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  selected_organization_id UUID;
  personal_metadata JSONB;
  effective_metadata JSONB;
  entitlement_scope TEXT := 'personal';
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT COALESCE(raw_app_meta_data, '{}'::JSONB)
  INTO personal_metadata
  FROM auth.users
  WHERE id = current_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Authenticated user was not found';
  END IF;

  effective_metadata := personal_metadata;

  SELECT membership.organization_id
  INTO selected_organization_id
  FROM organization_members AS membership
  WHERE membership.user_id = current_user_id
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

  IF selected_organization_id IS NOT NULL THEN
    SELECT COALESCE(owner_user.raw_app_meta_data, '{}'::JSONB)
    INTO effective_metadata
    FROM organization_members AS owner_membership
    JOIN auth.users AS owner_user
      ON owner_user.id = owner_membership.user_id
    WHERE owner_membership.organization_id = selected_organization_id
      AND owner_membership.role = 'owner'
    LIMIT 1;

    IF FOUND THEN
      entitlement_scope := 'organization';
    ELSE
      effective_metadata := personal_metadata;
      selected_organization_id := NULL;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'plan', COALESCE(effective_metadata ->> 'plan', 'free'),
    'personal_plan', COALESCE(personal_metadata ->> 'plan', 'free'),
    'entitlement_scope', entitlement_scope,
    'organization_id', selected_organization_id,
    'subscription_status',
      COALESCE(effective_metadata ->> 'subscription_status', ''),
    'access_valid_until', effective_metadata ->> 'access_valid_until',
    'entitlements', effective_metadata -> 'entitlements',
    'limits', effective_metadata -> 'limits'
  );
END;
$$;

REVOKE ALL ON FUNCTION current_entitlement_v3() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION current_entitlement_v3() TO authenticated;

COMMIT;
