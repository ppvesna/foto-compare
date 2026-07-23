-- Trimatrix authoritative entitlement snapshot.
-- Keeps paid access independent from stale JWT app_metadata.

BEGIN;

CREATE OR REPLACE FUNCTION current_entitlement_v2()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  metadata JSONB;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT COALESCE(raw_app_meta_data, '{}'::JSONB)
  INTO metadata
  FROM auth.users
  WHERE id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Authenticated user was not found';
  END IF;

  RETURN jsonb_build_object(
    'plan', COALESCE(metadata ->> 'plan', 'free'),
    'subscription_status',
      COALESCE(metadata ->> 'subscription_status', ''),
    'access_valid_until', metadata ->> 'access_valid_until',
    'entitlements', metadata -> 'entitlements',
    'limits', metadata -> 'limits'
  );
END;
$$;

REVOKE ALL ON FUNCTION current_entitlement_v2() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION current_entitlement_v2() TO authenticated;

COMMIT;
