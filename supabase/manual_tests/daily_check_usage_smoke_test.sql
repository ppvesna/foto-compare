-- Transactional smoke test for migration 025. It uses the latest job-scoped
-- cloud protocol as an authenticated actor and rolls every change back.

BEGIN;

DO $$
DECLARE
  selected_user_id UUID;
  selected_job_id UUID;
  before_used INTEGER;
  first_used INTEGER;
  second_used INTEGER;
  smoke_check_id TEXT := 'trimatrix-daily-usage-transaction-smoke';
BEGIN
  SELECT
    protocol.owner_user_id,
    protocol.job_id::UUID
  INTO selected_user_id, selected_job_id
  FROM cloud_check_protocols AS protocol
  WHERE protocol.organization_id IS NOT NULL
    AND protocol.job_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ORDER BY protocol.created_at DESC
  LIMIT 1;

  IF selected_user_id IS NULL OR selected_job_id IS NULL THEN
    RAISE EXCEPTION 'A job-scoped cloud protocol is required for this smoke test';
  END IF;

  PERFORM set_config(
    'request.jwt.claim.sub',
    selected_user_id::TEXT,
    TRUE
  );

  before_used := (current_check_usage_v1() ->> 'used')::INTEGER;
  first_used := (
    record_completed_check_v1(smoke_check_id, selected_job_id) ->> 'used'
  )::INTEGER;
  second_used := (
    record_completed_check_v1(smoke_check_id, selected_job_id) ->> 'used'
  )::INTEGER;

  IF first_used <> before_used + 1 THEN
    RAISE EXCEPTION 'Expected one increment: before %, after %',
      before_used,
      first_used;
  END IF;
  IF second_used <> first_used THEN
    RAISE EXCEPTION 'Repeated protocol id was counted twice: % then %',
      first_used,
      second_used;
  END IF;
END;
$$;

ROLLBACK;
