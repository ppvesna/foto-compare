-- Server-owned daily completed-check usage.
-- Prerequisites: migrations 006, 012, and 019.

BEGIN;

CREATE TABLE IF NOT EXISTS daily_check_usage_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usage_scope     TEXT NOT NULL CHECK (usage_scope IN ('personal', 'organization')),
  subject_id      UUID NOT NULL,
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  job_id          UUID REFERENCES production_jobs(id) ON DELETE SET NULL,
  check_id        TEXT NOT NULL CHECK (length(trim(check_id)) BETWEEN 1 AND 200),
  actor_user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  usage_date      DATE NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (usage_scope, subject_id, check_id),
  CHECK (
    (usage_scope = 'personal' AND organization_id IS NULL)
    OR
    (usage_scope = 'organization' AND organization_id = subject_id)
  )
);

CREATE INDEX IF NOT EXISTS daily_check_usage_subject_date_idx
ON daily_check_usage_events(usage_scope, subject_id, usage_date);

ALTER TABLE daily_check_usage_events ENABLE ROW LEVEL SECURITY;

-- Preserve already uploaded checks when this counter is introduced. Purely
-- local legacy checks cannot be reconstructed on the server.
INSERT INTO daily_check_usage_events(
  usage_scope,
  subject_id,
  organization_id,
  job_id,
  check_id,
  actor_user_id,
  usage_date,
  created_at
)
SELECT
  CASE
    WHEN protocol.organization_id IS NULL THEN 'personal'
    ELSE 'organization'
  END,
  COALESCE(protocol.organization_id, protocol.owner_user_id),
  protocol.organization_id,
  CASE
    WHEN protocol.job_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      THEN protocol.job_id::UUID
    ELSE NULL
  END,
  protocol.protocol_id,
  protocol.owner_user_id,
  (protocol.protocol_created_at AT TIME ZONE 'UTC')::DATE,
  protocol.created_at
FROM cloud_check_protocols AS protocol
ON CONFLICT (usage_scope, subject_id, check_id) DO NOTHING;

CREATE OR REPLACE FUNCTION current_check_usage_v1()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  entitlement JSONB;
  usage_scope_value TEXT;
  subject_id_value UUID;
  organization_id_value UUID;
  usage_date_value DATE := (now() AT TIME ZONE 'UTC')::DATE;
  daily_limit INTEGER;
  used_count INTEGER;
  configured_plan TEXT;
  subscription_status TEXT;
  valid_until TIMESTAMPTZ;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  entitlement := current_entitlement_v4();
  usage_scope_value := COALESCE(entitlement ->> 'entitlement_scope', 'personal');
  organization_id_value := NULLIF(entitlement ->> 'organization_id', '')::UUID;
  subject_id_value := CASE
    WHEN usage_scope_value = 'organization' THEN organization_id_value
    ELSE current_user_id
  END;
  IF subject_id_value IS NULL THEN
    RAISE EXCEPTION 'Unable to resolve check usage subject';
  END IF;

  configured_plan := COALESCE(entitlement ->> 'plan', 'free');
  subscription_status := lower(COALESCE(entitlement ->> 'subscription_status', ''));
  valid_until := NULLIF(entitlement ->> 'access_valid_until', '')::TIMESTAMPTZ;

  IF configured_plan <> 'free'
     AND (
       subscription_status NOT IN ('active', 'trialing', 'grace')
       OR (valid_until IS NOT NULL AND valid_until <= now())
     ) THEN
    daily_limit := 10;
  ELSIF entitlement #> '{limits,checksPerDay}' IS NULL
        OR entitlement #> '{limits,checksPerDay}' = 'null'::JSONB THEN
    daily_limit := NULL;
  ELSE
    daily_limit := (entitlement #>> '{limits,checksPerDay}')::INTEGER;
  END IF;

  SELECT count(*)::INTEGER
  INTO used_count
  FROM daily_check_usage_events AS event
  WHERE event.usage_scope = usage_scope_value
    AND event.subject_id = subject_id_value
    AND event.usage_date = usage_date_value;

  RETURN jsonb_build_object(
    'usage_date', usage_date_value,
    'scope', usage_scope_value,
    'subject_id', subject_id_value,
    'used', used_count,
    'limit', daily_limit,
    'remaining', CASE
      WHEN daily_limit IS NULL THEN NULL
      ELSE greatest(daily_limit - used_count, 0)
    END
  );
END;
$$;

CREATE OR REPLACE FUNCTION record_completed_check_v1(
  target_check_id TEXT,
  target_job_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  usage_snapshot JSONB;
  usage_scope_value TEXT;
  subject_id_value UUID;
  organization_id_value UUID;
  usage_date_value DATE;
  daily_limit INTEGER;
  used_count INTEGER;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  target_check_id := trim(COALESCE(target_check_id, ''));
  IF length(target_check_id) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Invalid check id';
  END IF;

  usage_snapshot := current_check_usage_v1();
  usage_scope_value := usage_snapshot ->> 'scope';
  subject_id_value := (usage_snapshot ->> 'subject_id')::UUID;
  organization_id_value := CASE
    WHEN usage_scope_value = 'organization' THEN subject_id_value
    ELSE NULL
  END;

  IF usage_scope_value = 'organization' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM organization_members AS member
      WHERE member.organization_id = organization_id_value
        AND member.user_id = current_user_id
        AND member.role IN ('owner', 'admin', 'employee')
    ) THEN
      RAISE EXCEPTION 'Organization role cannot record checks';
    END IF;
    IF target_job_id IS NULL OR NOT EXISTS (
      SELECT 1
      FROM production_jobs AS job
      WHERE job.id = target_job_id
        AND job.organization_id = organization_id_value
        AND can_view_production_job_v1(job.id)
    ) THEN
      RAISE EXCEPTION 'Accessible organization job is required';
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      usage_scope_value || ':' || subject_id_value::TEXT,
      0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM daily_check_usage_events AS event
    WHERE event.usage_scope = usage_scope_value
      AND event.subject_id = subject_id_value
      AND event.check_id = target_check_id
  ) THEN
    RETURN current_check_usage_v1();
  END IF;

  usage_snapshot := current_check_usage_v1();
  usage_date_value := (usage_snapshot ->> 'usage_date')::DATE;
  used_count := (usage_snapshot ->> 'used')::INTEGER;
  daily_limit := NULLIF(usage_snapshot ->> 'limit', '')::INTEGER;
  IF daily_limit IS NOT NULL AND used_count >= daily_limit THEN
    RAISE EXCEPTION 'daily_check_limit_reached';
  END IF;

  INSERT INTO daily_check_usage_events(
    usage_scope,
    subject_id,
    organization_id,
    job_id,
    check_id,
    actor_user_id,
    usage_date
  )
  VALUES (
    usage_scope_value,
    subject_id_value,
    organization_id_value,
    target_job_id,
    target_check_id,
    current_user_id,
    usage_date_value
  );

  RETURN current_check_usage_v1();
END;
$$;

REVOKE ALL ON TABLE daily_check_usage_events FROM PUBLIC;
REVOKE ALL ON FUNCTION current_check_usage_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION record_completed_check_v1(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION current_check_usage_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION record_completed_check_v1(TEXT, UUID)
TO authenticated;

COMMIT;
