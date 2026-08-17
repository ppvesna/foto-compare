-- Manager-controlled customer access to a production job and its chat.
-- Prerequisites: migrations 012 and 016.

BEGIN;

-- Job chats are created only by the controlled share operation below.
REVOKE ALL ON FUNCTION ensure_job_chat_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION ensure_job_chat_v1(UUID) FROM authenticated;

ALTER TABLE production_jobs
ADD COLUMN IF NOT EXISTS customer_access_status TEXT
NOT NULL DEFAULT 'internal';

ALTER TABLE production_jobs
ADD COLUMN IF NOT EXISTS customer_shared_at TIMESTAMPTZ;

ALTER TABLE production_jobs
ADD COLUMN IF NOT EXISTS customer_shared_by UUID
REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE production_jobs
DROP CONSTRAINT IF EXISTS production_job_customer_access_check;

ALTER TABLE production_jobs
ADD CONSTRAINT production_job_customer_access_check
CHECK (customer_access_status IN ('internal', 'shared'));

CREATE OR REPLACE FUNCTION can_manage_production_job_customer_access_v1(
  target_job UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM production_jobs AS job
    WHERE job.id = target_job
      AND (
        has_organization_role_v2(
          job.organization_id,
          ARRAY['owner', 'admin']
        )
        OR EXISTS (
          SELECT 1
          FROM production_job_participants AS participant
          WHERE participant.job_id = job.id
            AND participant.user_id = auth.uid()
            AND participant.participant_type = 'manager'
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION can_view_production_job_v1(
  target_job UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM production_jobs AS job
    WHERE job.id = target_job
      AND (
        has_organization_role_v2(
          job.organization_id,
          ARRAY['owner', 'admin']
        )
        OR EXISTS (
          SELECT 1
          FROM production_job_participants AS participant
          WHERE participant.job_id = job.id
            AND participant.user_id = auth.uid()
            AND (
              participant.participant_type <> 'customer'
              OR job.customer_access_status = 'shared'
            )
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION list_customer_share_candidates_v1()
RETURNS TABLE(
  job_id UUID,
  job_number TEXT,
  customer_name TEXT,
  customer_shared BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  RETURN QUERY
  SELECT
    job.id,
    job.number,
    COALESCE(customer.name, ''),
    job.customer_access_status = 'shared'
  FROM production_jobs AS job
  LEFT JOIN organization_customers AS customer
    ON customer.id = job.customer_id
  WHERE job.status = 'active'
    AND job.customer_confirmed
    AND EXISTS (
      SELECT 1
      FROM production_job_participants AS participant
      WHERE participant.job_id = job.id
        AND participant.participant_type = 'customer'
    )
    AND can_manage_production_job_customer_access_v1(job.id)
  ORDER BY job.updated_at DESC
  LIMIT 100;
END;
$$;

CREATE OR REPLACE FUNCTION set_production_job_customer_access_v1(
  target_job UUID,
  requested_shared BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
  selected_group_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF requested_shared IS NULL THEN
    RAISE EXCEPTION 'Customer access state is required';
  END IF;

  IF NOT can_manage_production_job_customer_access_v1(target_job) THEN
    RAISE EXCEPTION 'Customer access management denied';
  END IF;

  SELECT * INTO selected_job
  FROM production_jobs
  WHERE id = target_job
  FOR UPDATE;

  IF requested_shared AND NOT selected_job.customer_confirmed THEN
    RAISE EXCEPTION 'A confirmed customer is required';
  END IF;
  IF requested_shared AND NOT EXISTS (
    SELECT 1
    FROM production_job_participants AS participant
    WHERE participant.job_id = selected_job.id
      AND participant.participant_type = 'customer'
  ) THEN
    RAISE EXCEPTION 'An assigned customer account is required';
  END IF;

  UPDATE production_jobs
  SET
    customer_access_status = CASE
      WHEN requested_shared THEN 'shared'
      ELSE 'internal'
    END,
    customer_shared_at = CASE
      WHEN requested_shared THEN now()
      ELSE NULL
    END,
    customer_shared_by = CASE
      WHEN requested_shared THEN auth.uid()
      ELSE NULL
    END,
    updated_by = auth.uid(),
    updated_at = now()
  WHERE id = target_job;

  IF requested_shared THEN
    INSERT INTO chat_groups(
      organization_id,
      job_id,
      name,
      kind,
      created_by,
      scope_key
    )
    VALUES (
      selected_job.organization_id,
      selected_job.id,
      'Работа № ' || selected_job.number,
      'job',
      auth.uid(),
      'job:' || selected_job.id::TEXT
    )
    ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
    DO UPDATE SET
      name = EXCLUDED.name,
      is_deleted = FALSE,
      updated_at = now()
    RETURNING id INTO selected_group_id;
  ELSE
    SELECT id INTO selected_group_id
    FROM chat_groups
    WHERE scope_key = 'job:' || selected_job.id::TEXT
    LIMIT 1;
  END IF;

  RETURN selected_group_id;
END;
$$;

CREATE OR REPLACE FUNCTION list_accessible_chat_threads_v1()
RETURNS TABLE(
  thread_id UUID,
  thread_name TEXT,
  thread_kind TEXT,
  organization_id UUID,
  job_id UUID,
  updated_at TIMESTAMPTZ,
  customer_shared BOOLEAN,
  can_manage_customer_access BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  RETURN QUERY
  SELECT
    chat.id,
    chat.name,
    chat.kind,
    chat.organization_id,
    chat.job_id,
    chat.updated_at,
    COALESCE(job.customer_access_status = 'shared', FALSE),
    CASE
      WHEN chat.job_id IS NULL THEN FALSE
      ELSE can_manage_production_job_customer_access_v1(chat.job_id)
    END
  FROM chat_groups AS chat
  LEFT JOIN production_jobs AS job
    ON job.id = chat.job_id
  WHERE can_access_chat_group_v1(chat.id)
  ORDER BY chat.updated_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION can_manage_production_job_customer_access_v1(UUID)
FROM PUBLIC;
REVOKE ALL ON FUNCTION can_manage_production_job_customer_access_v1(UUID)
FROM authenticated;
REVOKE ALL ON FUNCTION list_customer_share_candidates_v1()
FROM PUBLIC;
REVOKE ALL ON FUNCTION set_production_job_customer_access_v1(UUID, BOOLEAN)
FROM PUBLIC;
REVOKE ALL ON FUNCTION list_accessible_chat_threads_v1()
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION list_customer_share_candidates_v1()
TO authenticated;
GRANT EXECUTE ON FUNCTION set_production_job_customer_access_v1(UUID, BOOLEAN)
TO authenticated;
GRANT EXECUTE ON FUNCTION list_accessible_chat_threads_v1()
TO authenticated;

COMMIT;
