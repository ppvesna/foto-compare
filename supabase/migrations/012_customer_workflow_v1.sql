-- Trimatrix customer directory and lightweight production work workflow.
-- Prerequisites: migrations 006, 009, 010, and 011.

BEGIN;

CREATE TABLE IF NOT EXISTS organization_customers (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id          UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  code                     TEXT NOT NULL,
  code_key                 TEXT NOT NULL,
  name                     TEXT NOT NULL,
  primary_manager_user_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  active                   BOOLEAN NOT NULL DEFAULT TRUE,
  created_by               UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by               UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT organization_customer_code_check
    CHECK (length(trim(code)) BETWEEN 1 AND 32),
  CONSTRAINT organization_customer_name_check
    CHECK (length(trim(name)) BETWEEN 2 AND 160),
  CONSTRAINT organization_customer_code_key_check
    CHECK (code_key = lower(trim(code)))
);

CREATE UNIQUE INDEX IF NOT EXISTS organization_customers_code_key
ON organization_customers(organization_id, code_key);

CREATE INDEX IF NOT EXISTS organization_customers_active_name_idx
ON organization_customers(organization_id, active, name);

CREATE TABLE IF NOT EXISTS organization_customer_users (
  customer_id      UUID NOT NULL REFERENCES organization_customers(id) ON DELETE CASCADE,
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  linked_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  linked_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_id, user_id)
);

CREATE TABLE IF NOT EXISTS organization_customer_requests (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  requested_name        TEXT NOT NULL,
  work_number           TEXT NOT NULL DEFAULT '',
  status                TEXT NOT NULL DEFAULT 'pending',
  requested_by          UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  resolved_customer_id  UUID REFERENCES organization_customers(id) ON DELETE SET NULL,
  resolved_by           UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  resolved_at           TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT organization_customer_request_name_check
    CHECK (length(trim(requested_name)) BETWEEN 2 AND 160),
  CONSTRAINT organization_customer_request_status_check
    CHECK (status IN ('pending', 'resolved', 'dismissed'))
);

CREATE INDEX IF NOT EXISTS organization_customer_requests_status_idx
ON organization_customer_requests(organization_id, status, created_at);

CREATE TABLE IF NOT EXISTS production_jobs (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id          UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  number                   TEXT NOT NULL,
  number_key               TEXT NOT NULL,
  customer_id              UUID REFERENCES organization_customers(id) ON DELETE SET NULL,
  customer_request_id      UUID REFERENCES organization_customer_requests(id) ON DELETE SET NULL,
  requested_customer_name  TEXT NOT NULL DEFAULT '',
  customer_confirmed       BOOLEAN NOT NULL DEFAULT FALSE,
  status                   TEXT NOT NULL DEFAULT 'active',
  created_by               UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by               UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT production_job_number_check
    CHECK (length(trim(number)) BETWEEN 1 AND 80),
  CONSTRAINT production_job_number_key_check
    CHECK (number_key = lower(trim(number))),
  CONSTRAINT production_job_status_check
    CHECK (status IN ('active', 'completed', 'archived')),
  CONSTRAINT production_job_customer_state_check
    CHECK (
      (customer_confirmed AND customer_id IS NOT NULL)
      OR
      (
        NOT customer_confirmed
        AND customer_id IS NULL
        AND length(trim(requested_customer_name)) >= 2
      )
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS production_jobs_number_key
ON production_jobs(organization_id, number_key);

CREATE INDEX IF NOT EXISTS production_jobs_customer_idx
ON production_jobs(organization_id, customer_id, updated_at);

CREATE TABLE IF NOT EXISTS production_job_participants (
  job_id             UUID NOT NULL REFERENCES production_jobs(id) ON DELETE CASCADE,
  user_id            UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  participant_type   TEXT NOT NULL,
  added_by            UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  added_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (job_id, user_id, participant_type),
  CONSTRAINT production_job_participant_type_check
    CHECK (participant_type IN ('operator', 'manager', 'customer'))
);

ALTER TABLE organization_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_customer_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_customer_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_job_participants ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION list_organization_customers_v1(
  target_organization UUID,
  include_archived BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(
  customer_id UUID,
  code TEXT,
  name TEXT,
  active BOOLEAN,
  primary_manager_user_id UUID,
  primary_manager_nickname TEXT,
  customer_user_id UUID,
  customer_user_nickname TEXT,
  created_by_user_id UUID,
  created_by_nickname TEXT,
  updated_by_user_id UUID,
  updated_by_nickname TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT has_organization_role_v2(
    target_organization,
    ARRAY['owner', 'admin', 'employee']
  ) THEN
    RAISE EXCEPTION 'Customer directory access required';
  END IF;

  RETURN QUERY
  SELECT
    customer.id,
    customer.code,
    customer.name,
    customer.active,
    customer.primary_manager_user_id,
    COALESCE(manager_profile.nickname, '')::TEXT,
    customer_link.user_id,
    COALESCE(customer_profile.nickname, '')::TEXT,
    customer.created_by,
    COALESCE(creator_profile.nickname, '')::TEXT,
    customer.updated_by,
    COALESCE(updater_profile.nickname, '')::TEXT,
    customer.created_at,
    customer.updated_at
  FROM organization_customers AS customer
  LEFT JOIN user_profiles AS manager_profile
    ON manager_profile.user_id = customer.primary_manager_user_id
  LEFT JOIN LATERAL (
    SELECT link.user_id
    FROM organization_customer_users AS link
    WHERE link.customer_id = customer.id
    ORDER BY link.linked_at
    LIMIT 1
  ) AS customer_link ON TRUE
  LEFT JOIN user_profiles AS customer_profile
    ON customer_profile.user_id = customer_link.user_id
  LEFT JOIN user_profiles AS creator_profile
    ON creator_profile.user_id = customer.created_by
  LEFT JOIN user_profiles AS updater_profile
    ON updater_profile.user_id = customer.updated_by
  WHERE customer.organization_id = target_organization
    AND (include_archived OR customer.active)
  ORDER BY customer.active DESC, lower(customer.name), lower(customer.code);
END;
$$;

CREATE OR REPLACE FUNCTION save_organization_customer_v1(
  target_organization UUID,
  target_code TEXT,
  target_name TEXT,
  target_manager_user UUID DEFAULT NULL,
  target_customer_user UUID DEFAULT NULL,
  target_customer UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor_role TEXT;
  clean_code TEXT := trim(COALESCE(target_code, ''));
  clean_name TEXT := trim(COALESCE(target_name, ''));
  selected_customer UUID;
BEGIN
  SELECT role INTO actor_role
  FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = auth.uid();

  IF actor_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'Customer administration access required';
  END IF;
  IF length(clean_code) NOT BETWEEN 1 AND 32 THEN
    RAISE EXCEPTION 'Customer code must contain 1-32 characters';
  END IF;
  IF length(clean_name) NOT BETWEEN 2 AND 160 THEN
    RAISE EXCEPTION 'Customer name must contain 2-160 characters';
  END IF;

  IF target_manager_user IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM organization_members
    WHERE organization_id = target_organization
      AND user_id = target_manager_user
      AND role IN ('owner', 'admin', 'employee')
  ) THEN
    RAISE EXCEPTION 'Selected manager is not an organization employee';
  END IF;

  IF target_customer_user IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM organization_members
    WHERE organization_id = target_organization
      AND user_id = target_customer_user
      AND role = 'customer'
  ) THEN
    RAISE EXCEPTION 'Selected customer user does not have the customer role';
  END IF;

  IF target_customer IS NULL THEN
    INSERT INTO organization_customers(
      organization_id,
      code,
      code_key,
      name,
      primary_manager_user_id,
      created_by,
      updated_by
    )
    VALUES (
      target_organization,
      clean_code,
      lower(clean_code),
      clean_name,
      target_manager_user,
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO selected_customer;
  ELSE
    UPDATE organization_customers
    SET
      code = clean_code,
      code_key = lower(clean_code),
      name = clean_name,
      primary_manager_user_id = target_manager_user,
      active = TRUE,
      updated_by = auth.uid(),
      updated_at = now()
    WHERE id = target_customer
      AND organization_id = target_organization
    RETURNING id INTO selected_customer;

    IF selected_customer IS NULL THEN
      RAISE EXCEPTION 'Customer not found in this organization';
    END IF;
  END IF;

  DELETE FROM organization_customer_users
  WHERE customer_id = selected_customer;

  IF target_customer_user IS NOT NULL THEN
    INSERT INTO organization_customer_users(
      customer_id,
      user_id,
      linked_by
    )
    VALUES (
      selected_customer,
      target_customer_user,
      auth.uid()
    )
    ON CONFLICT (customer_id, user_id)
    DO UPDATE SET linked_by = auth.uid(), linked_at = now();
  END IF;

  RETURN selected_customer;
END;
$$;

CREATE OR REPLACE FUNCTION archive_organization_customer_v1(
  target_customer UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_organization UUID;
BEGIN
  SELECT organization_id INTO target_organization
  FROM organization_customers
  WHERE id = target_customer;

  IF target_organization IS NULL OR NOT has_organization_role_v2(
    target_organization,
    ARRAY['owner', 'admin']
  ) THEN
    RAISE EXCEPTION 'Customer administration access required';
  END IF;

  UPDATE organization_customers
  SET
    active = FALSE,
    updated_by = auth.uid(),
    updated_at = now()
  WHERE id = target_customer;
END;
$$;

CREATE OR REPLACE FUNCTION submit_customer_request_v1(
  target_organization UUID,
  target_requested_name TEXT,
  target_work_number TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  clean_name TEXT := trim(COALESCE(target_requested_name, ''));
  clean_work_number TEXT := trim(COALESCE(target_work_number, ''));
  selected_request UUID;
BEGIN
  IF NOT has_organization_role_v2(
    target_organization,
    ARRAY['owner', 'admin', 'employee']
  ) THEN
    RAISE EXCEPTION 'Customer request access required';
  END IF;
  IF length(clean_name) NOT BETWEEN 2 AND 160 THEN
    RAISE EXCEPTION 'Requested customer name must contain 2-160 characters';
  END IF;

  SELECT request.id INTO selected_request
  FROM organization_customer_requests AS request
  WHERE request.organization_id = target_organization
    AND request.status = 'pending'
    AND lower(request.requested_name) = lower(clean_name)
    AND lower(request.work_number) = lower(clean_work_number)
  ORDER BY request.created_at DESC
  LIMIT 1;

  IF selected_request IS NULL THEN
    INSERT INTO organization_customer_requests(
      organization_id,
      requested_name,
      work_number,
      requested_by
    )
    VALUES (
      target_organization,
      clean_name,
      clean_work_number,
      auth.uid()
    )
    RETURNING id INTO selected_request;
  END IF;

  RETURN selected_request;
END;
$$;

CREATE OR REPLACE FUNCTION list_customer_requests_v1(
  target_organization UUID
)
RETURNS TABLE(
  request_id UUID,
  requested_name TEXT,
  work_number TEXT,
  requested_by_user_id UUID,
  requested_by_nickname TEXT,
  created_at TIMESTAMPTZ
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
    RAISE EXCEPTION 'Customer administration access required';
  END IF;

  RETURN QUERY
  SELECT
    request.id,
    request.requested_name,
    request.work_number,
    request.requested_by,
    COALESCE(profile.nickname, '')::TEXT,
    request.created_at
  FROM organization_customer_requests AS request
  LEFT JOIN user_profiles AS profile ON profile.user_id = request.requested_by
  WHERE request.organization_id = target_organization
    AND request.status = 'pending'
  ORDER BY request.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION open_production_job_v1(
  target_organization UUID,
  target_number TEXT,
  target_customer UUID DEFAULT NULL,
  target_requested_customer_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  clean_number TEXT := trim(COALESCE(target_number, ''));
  clean_requested_name TEXT := trim(COALESCE(target_requested_customer_name, ''));
  selected_customer organization_customers%ROWTYPE;
  selected_request UUID;
  selected_job UUID;
BEGIN
  IF NOT has_organization_role_v2(
    target_organization,
    ARRAY['owner', 'admin', 'employee']
  ) THEN
    RAISE EXCEPTION 'Production job access required';
  END IF;
  IF length(clean_number) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'Work number must contain 1-80 characters';
  END IF;

  IF target_customer IS NOT NULL THEN
    SELECT * INTO selected_customer
    FROM organization_customers
    WHERE id = target_customer
      AND organization_id = target_organization
      AND active;
    IF selected_customer.id IS NULL THEN
      RAISE EXCEPTION 'Selected customer is not available';
    END IF;
  ELSIF length(clean_requested_name) >= 2 THEN
    selected_request := submit_customer_request_v1(
      target_organization,
      clean_requested_name,
      clean_number
    );
  ELSE
    RAISE EXCEPTION 'Select a customer or enter its name from the technical specification';
  END IF;

  INSERT INTO production_jobs(
    organization_id,
    number,
    number_key,
    customer_id,
    customer_request_id,
    requested_customer_name,
    customer_confirmed,
    created_by,
    updated_by
  )
  VALUES (
    target_organization,
    clean_number,
    lower(clean_number),
    selected_customer.id,
    selected_request,
    CASE WHEN selected_customer.id IS NULL THEN clean_requested_name ELSE '' END,
    selected_customer.id IS NOT NULL,
    auth.uid(),
    auth.uid()
  )
  ON CONFLICT (organization_id, number_key)
  DO UPDATE SET
    number = EXCLUDED.number,
    customer_id = EXCLUDED.customer_id,
    customer_request_id = EXCLUDED.customer_request_id,
    requested_customer_name = EXCLUDED.requested_customer_name,
    customer_confirmed = EXCLUDED.customer_confirmed,
    updated_by = auth.uid(),
    updated_at = now()
  RETURNING id INTO selected_job;

  INSERT INTO production_job_participants(
    job_id,
    user_id,
    participant_type,
    added_by
  )
  VALUES (selected_job, auth.uid(), 'operator', auth.uid())
  ON CONFLICT DO NOTHING;

  DELETE FROM production_job_participants
  WHERE job_id = selected_job
    AND participant_type IN ('manager', 'customer');

  IF selected_customer.id IS NOT NULL THEN
    IF selected_customer.primary_manager_user_id IS NOT NULL THEN
      INSERT INTO production_job_participants(
        job_id,
        user_id,
        participant_type,
        added_by
      )
      VALUES (
        selected_job,
        selected_customer.primary_manager_user_id,
        'manager',
        auth.uid()
      )
      ON CONFLICT DO NOTHING;
    END IF;

    INSERT INTO production_job_participants(
      job_id,
      user_id,
      participant_type,
      added_by
    )
    SELECT
      selected_job,
      customer_user.user_id,
      'customer',
      auth.uid()
    FROM organization_customer_users AS customer_user
    WHERE customer_user.customer_id = selected_customer.id
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'job_id', selected_job,
    'job_number', clean_number,
    'customer_id', selected_customer.id,
    'customer_name', COALESCE(selected_customer.name, clean_requested_name),
    'customer_confirmed', selected_customer.id IS NOT NULL,
    'customer_request_id', selected_request
  );
END;
$$;

CREATE OR REPLACE FUNCTION resolve_customer_request_v1(
  target_request UUID,
  target_customer UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_request organization_customer_requests%ROWTYPE;
  selected_customer organization_customers%ROWTYPE;
  selected_job RECORD;
BEGIN
  SELECT * INTO selected_request
  FROM organization_customer_requests
  WHERE id = target_request
    AND status = 'pending';

  IF selected_request.id IS NULL OR NOT has_organization_role_v2(
    selected_request.organization_id,
    ARRAY['owner', 'admin']
  ) THEN
    RAISE EXCEPTION 'Customer administration access required';
  END IF;

  SELECT * INTO selected_customer
  FROM organization_customers
  WHERE id = target_customer
    AND organization_id = selected_request.organization_id
    AND active;
  IF selected_customer.id IS NULL THEN
    RAISE EXCEPTION 'Selected customer is not available';
  END IF;

  UPDATE organization_customer_requests
  SET
    status = 'resolved',
    resolved_customer_id = selected_customer.id,
    resolved_by = auth.uid(),
    resolved_at = now(),
    updated_at = now()
  WHERE id = selected_request.id;

  FOR selected_job IN
    SELECT id
    FROM production_jobs
    WHERE customer_request_id = selected_request.id
  LOOP
    UPDATE production_jobs
    SET
      customer_id = selected_customer.id,
      customer_request_id = NULL,
      requested_customer_name = '',
      customer_confirmed = TRUE,
      updated_by = auth.uid(),
      updated_at = now()
    WHERE id = selected_job.id;

    DELETE FROM production_job_participants
    WHERE job_id = selected_job.id
      AND participant_type IN ('manager', 'customer');

    IF selected_customer.primary_manager_user_id IS NOT NULL THEN
      INSERT INTO production_job_participants(
        job_id,
        user_id,
        participant_type,
        added_by
      )
      VALUES (
        selected_job.id,
        selected_customer.primary_manager_user_id,
        'manager',
        auth.uid()
      )
      ON CONFLICT DO NOTHING;
    END IF;

    INSERT INTO production_job_participants(
      job_id,
      user_id,
      participant_type,
      added_by
    )
    SELECT
      selected_job.id,
      customer_user.user_id,
      'customer',
      auth.uid()
    FROM organization_customer_users AS customer_user
    WHERE customer_user.customer_id = selected_customer.id
    ON CONFLICT DO NOTHING;
  END LOOP;
END;
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
        )
      )
  );
$$;

DROP POLICY IF EXISTS "organization_customer_directory_read_v1"
ON organization_customers;
CREATE POLICY "organization_customer_directory_read_v1"
ON organization_customers
FOR SELECT
TO authenticated
USING (
  has_organization_role_v2(
    organization_id,
    ARRAY['owner', 'admin']
  )
  OR (
    active
    AND has_organization_role_v2(
      organization_id,
      ARRAY['employee']
    )
  )
);

DROP POLICY IF EXISTS "organization_customer_users_read_v1"
ON organization_customer_users;
CREATE POLICY "organization_customer_users_read_v1"
ON organization_customer_users
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM organization_customers AS customer
    WHERE customer.id = customer_id
      AND has_organization_role_v2(
        customer.organization_id,
        ARRAY['owner', 'admin']
      )
  )
  OR user_id = auth.uid()
);

DROP POLICY IF EXISTS "organization_customer_requests_read_v1"
ON organization_customer_requests;
CREATE POLICY "organization_customer_requests_read_v1"
ON organization_customer_requests
FOR SELECT
TO authenticated
USING (
  requested_by = auth.uid()
  OR has_organization_role_v2(
    organization_id,
    ARRAY['owner', 'admin']
  )
);

DROP POLICY IF EXISTS "production_jobs_read_v1"
ON production_jobs;
CREATE POLICY "production_jobs_read_v1"
ON production_jobs
FOR SELECT
TO authenticated
USING (
  can_view_production_job_v1(id)
);

DROP POLICY IF EXISTS "production_job_participants_read_v1"
ON production_job_participants;
CREATE POLICY "production_job_participants_read_v1"
ON production_job_participants
FOR SELECT
TO authenticated
USING (
  can_view_production_job_v1(job_id)
);

REVOKE ALL ON FUNCTION list_organization_customers_v1(UUID, BOOLEAN)
FROM PUBLIC;
REVOKE ALL ON FUNCTION save_organization_customer_v1(
  UUID, TEXT, TEXT, UUID, UUID, UUID
) FROM PUBLIC;
REVOKE ALL ON FUNCTION archive_organization_customer_v1(UUID)
FROM PUBLIC;
REVOKE ALL ON FUNCTION submit_customer_request_v1(UUID, TEXT, TEXT)
FROM PUBLIC;
REVOKE ALL ON FUNCTION list_customer_requests_v1(UUID)
FROM PUBLIC;
REVOKE ALL ON FUNCTION open_production_job_v1(UUID, TEXT, UUID, TEXT)
FROM PUBLIC;
REVOKE ALL ON FUNCTION resolve_customer_request_v1(UUID, UUID)
FROM PUBLIC;
REVOKE ALL ON FUNCTION can_view_production_job_v1(UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION list_organization_customers_v1(UUID, BOOLEAN)
TO authenticated;
GRANT EXECUTE ON FUNCTION save_organization_customer_v1(
  UUID, TEXT, TEXT, UUID, UUID, UUID
) TO authenticated;
GRANT EXECUTE ON FUNCTION archive_organization_customer_v1(UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION submit_customer_request_v1(UUID, TEXT, TEXT)
TO authenticated;
GRANT EXECUTE ON FUNCTION list_customer_requests_v1(UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION open_production_job_v1(UUID, TEXT, UUID, TEXT)
TO authenticated;
GRANT EXECUTE ON FUNCTION resolve_customer_request_v1(UUID, UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION can_view_production_job_v1(UUID)
TO authenticated;

GRANT SELECT ON organization_customers TO authenticated;
GRANT SELECT ON organization_customer_users TO authenticated;
GRANT SELECT ON organization_customer_requests TO authenticated;
GRANT SELECT ON production_jobs TO authenticated;
GRANT SELECT ON production_job_participants TO authenticated;

COMMIT;
