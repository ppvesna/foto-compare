-- Reactivate a server-side test subscription without changing organization roles.
-- Run in Supabase Dashboard -> SQL Editor only for a test account.

DO $$
DECLARE
  target_email CONSTANT TEXT := 'CHANGE_ME@example.com';
  target_plan CONSTANT TEXT := 'pro';
  access_days CONSTANT INTEGER := 90;
  affected_rows INTEGER;
  new_valid_until TEXT;
BEGIN
  IF target_email = 'CHANGE_ME@example.com' THEN
    RAISE EXCEPTION 'Replace CHANGE_ME@example.com with the owner email';
  END IF;
  IF target_plan NOT IN ('pro', 'enterprise') THEN
    RAISE EXCEPTION 'Test plan must be pro or enterprise';
  END IF;

  UPDATE auth.users
  SET raw_app_meta_data =
        (COALESCE(raw_app_meta_data, '{}'::jsonb) - 'entitlements' - 'limits')
        || jsonb_build_object(
          'plan', target_plan,
          'subscription_status', 'active',
          'access_valid_until',
            to_char(
              (now() AT TIME ZONE 'UTC') + make_interval(days => access_days),
              'YYYY-MM-DD"T"HH24:MI:SS"Z"'
            )
        )
  WHERE lower(email) = lower(target_email);

  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows <> 1 THEN
    RAISE EXCEPTION 'Expected one user, updated %', affected_rows;
  END IF;
  SELECT raw_app_meta_data ->> 'access_valid_until'
  INTO new_valid_until
  FROM auth.users
  WHERE lower(email) = lower(target_email);
  RAISE NOTICE 'Plan % is active for % until %',
    target_plan, target_email, new_valid_until;
END $$;
