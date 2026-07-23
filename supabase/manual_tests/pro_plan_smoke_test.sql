-- Temporary Pro plan for an organization-owner smoke test.
-- This script deliberately assigns no organization and no organization role.
-- Use a dedicated test user and replace CHANGE_ME@example.com in both blocks.

DO $$
DECLARE
  target_email CONSTANT TEXT := 'CHANGE_ME@example.com';
  affected_rows INTEGER;
BEGIN
  IF target_email = 'CHANGE_ME@example.com' THEN
    RAISE EXCEPTION 'Replace CHANGE_ME@example.com with the test user email';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM auth.users
    WHERE lower(email) = lower(target_email)
      AND COALESCE(raw_app_meta_data, '{}'::jsonb)
          ?| ARRAY['plan', 'subscription_status', 'access_valid_until']
  ) THEN
    RAISE EXCEPTION
      'The user already has plan metadata. Use a dedicated test user.';
  END IF;

  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) ||
      jsonb_build_object(
        'plan', 'pro',
        'subscription_status', 'active',
        'access_valid_until',
          to_char(
            (now() AT TIME ZONE 'UTC') + INTERVAL '7 days',
            'YYYY-MM-DD"T"HH24:MI:SS"Z"'
          )
      )
  WHERE lower(email) = lower(target_email);

  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'Expected one test user, updated %', affected_rows;
  END IF;
END $$;

-- Cleanup after all organization tests. Sign out and sign in after cleanup.
/*
DO $$
DECLARE
  target_email CONSTANT TEXT := 'CHANGE_ME@example.com';
  affected_rows INTEGER;
BEGIN
  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb)
      - 'plan'
      - 'subscription_status'
      - 'access_valid_until'
  WHERE lower(email) = lower(target_email)
    AND raw_app_meta_data ->> 'plan' = 'pro';

  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'Temporary Pro metadata was not found';
  END IF;
END $$;
*/
