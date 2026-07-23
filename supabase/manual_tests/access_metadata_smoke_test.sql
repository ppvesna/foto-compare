-- Trimatrix: reversible role/plan smoke test without applying migration 005.
-- Run only in Supabase Dashboard -> SQL Editor against a dedicated test user.
-- Replace CHANGE_ME@example.com in BOTH blocks before running them.

-- ---------------------------------------------------------------------------
-- APPLY TEST ACCESS
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  target_email CONSTANT TEXT := 'CHANGE_ME@example.com';
  target_plan CONSTANT TEXT := 'pro';
  target_role CONSTANT TEXT := 'customer';
  test_organization_id CONSTANT TEXT :=
    '00000000-0000-0000-0000-000000001001';
  affected_rows INTEGER;
BEGIN
  IF target_email = 'CHANGE_ME@example.com' THEN
    RAISE EXCEPTION 'Replace CHANGE_ME@example.com with the test user email';
  END IF;

  IF target_plan NOT IN ('free', 'pro', 'enterprise') THEN
    RAISE EXCEPTION 'Unsupported plan: %', target_plan;
  END IF;

  IF target_role NOT IN ('owner', 'admin', 'employee', 'customer') THEN
    RAISE EXCEPTION 'Unsupported role: %', target_role;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM auth.users
    WHERE lower(email) = lower(target_email)
      AND COALESCE(raw_app_meta_data, '{}'::jsonb)
          ?| ARRAY[
            'plan',
            'subscription_status',
            'access_valid_until',
            'organization_id',
            'organization_role'
          ]
  ) THEN
    RAISE EXCEPTION
      'The user already has access metadata. Use a dedicated test user.';
  END IF;

  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) ||
      jsonb_build_object(
        'plan', target_plan,
        'subscription_status', 'active',
        'access_valid_until',
          to_char(
            (now() AT TIME ZONE 'UTC') + INTERVAL '7 days',
            'YYYY-MM-DD"T"HH24:MI:SS"Z"'
          ),
        'organization_id', test_organization_id,
        'organization_role', target_role
      )
  WHERE lower(email) = lower(target_email);

  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'Expected one test user, updated %', affected_rows;
  END IF;
END $$;

SELECT
  id,
  email,
  raw_app_meta_data ->> 'plan' AS plan,
  raw_app_meta_data ->> 'subscription_status' AS subscription_status,
  raw_app_meta_data ->> 'access_valid_until' AS access_valid_until,
  raw_app_meta_data ->> 'organization_id' AS organization_id,
  raw_app_meta_data ->> 'organization_role' AS organization_role
FROM auth.users
WHERE lower(email) = lower('CHANGE_ME@example.com');

-- After running the block above:
-- 1. Disable the local access override in Trimatrix settings.
-- 2. Sign out completely and sign in as the test user again.
-- 3. Open Settings -> Access and verify plan, role, and permission rows.

-- ---------------------------------------------------------------------------
-- CLEANUP TEST ACCESS
-- Run this block only after the smoke test is complete.
-- ---------------------------------------------------------------------------
/*
DO $$
DECLARE
  target_email CONSTANT TEXT := 'CHANGE_ME@example.com';
  test_organization_id CONSTANT TEXT :=
    '00000000-0000-0000-0000-000000001001';
  affected_rows INTEGER;
BEGIN
  IF target_email = 'CHANGE_ME@example.com' THEN
    RAISE EXCEPTION 'Replace CHANGE_ME@example.com with the test user email';
  END IF;

  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb)
      - 'plan'
      - 'subscription_status'
      - 'access_valid_until'
      - 'organization_id'
      - 'organization_role'
  WHERE lower(email) = lower(target_email)
    AND raw_app_meta_data ->> 'organization_id' = test_organization_id;

  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION
      'Test metadata was not found; no user was changed (updated %)', affected_rows;
  END IF;
END $$;
*/
