-- Production workflow and scalable work register.
-- A job advances only when all defect blocks are resolved. Technical blocking
-- is reserved for explicitly assigned inspection specialists.
-- Prerequisites: migrations 012, 017, 018, 022, and 029.

BEGIN;

ALTER TABLE production_jobs
ADD COLUMN IF NOT EXISTS stage_code TEXT NOT NULL DEFAULT 'preparation';

ALTER TABLE production_jobs
ADD COLUMN IF NOT EXISTS flow_state TEXT NOT NULL DEFAULT 'ready';

ALTER TABLE production_jobs
ADD COLUMN IF NOT EXISTS stage_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE production_jobs
DROP CONSTRAINT IF EXISTS production_job_stage_code_check;

ALTER TABLE production_jobs
ADD CONSTRAINT production_job_stage_code_check
CHECK (
  stage_code IN (
    'preparation',
    'prepress',
    'printing',
    'quality_control',
    'completed'
  )
);

ALTER TABLE production_jobs
DROP CONSTRAINT IF EXISTS production_job_flow_state_check;

ALTER TABLE production_jobs
ADD CONSTRAINT production_job_flow_state_check
CHECK (flow_state IN ('ready', 'blocked', 'completed'));

UPDATE production_jobs
SET
  stage_code = 'completed',
  flow_state = 'completed'
WHERE status = 'completed';

CREATE INDEX IF NOT EXISTS production_jobs_register_idx
ON production_jobs(organization_id, status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS production_jobs_flow_idx
ON production_jobs(organization_id, flow_state, updated_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS production_job_controllers (
  job_id       UUID NOT NULL REFERENCES production_jobs(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  can_block    BOOLEAN NOT NULL DEFAULT TRUE,
  can_unblock  BOOLEAN NOT NULL DEFAULT TRUE,
  assigned_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  assigned_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(job_id, user_id),
  CONSTRAINT production_job_controller_capability_check
    CHECK (can_block OR can_unblock)
);

CREATE TABLE IF NOT EXISTS production_job_blocks (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id            UUID NOT NULL REFERENCES production_jobs(id) ON DELETE CASCADE,
  stage_code        TEXT NOT NULL,
  scope_label       TEXT NOT NULL DEFAULT 'Вся работа',
  reason            TEXT NOT NULL,
  customer_visible  BOOLEAN NOT NULL DEFAULT FALSE,
  created_by        UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  resolved_at       TIMESTAMPTZ,
  resolution_note   TEXT NOT NULL DEFAULT '',
  CONSTRAINT production_job_block_stage_check
    CHECK (
      stage_code IN (
        'preparation',
        'prepress',
        'printing',
        'quality_control',
        'completed'
      )
    ),
  CONSTRAINT production_job_block_scope_check
    CHECK (length(trim(scope_label)) BETWEEN 2 AND 160),
  CONSTRAINT production_job_block_reason_check
    CHECK (length(trim(reason)) BETWEEN 3 AND 1000),
  CONSTRAINT production_job_block_resolution_check
    CHECK (
      (resolved_at IS NULL AND resolved_by IS NULL)
      OR (resolved_at IS NOT NULL AND resolved_by IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS production_job_blocks_active_idx
ON production_job_blocks(job_id, created_at DESC)
WHERE resolved_at IS NULL;

CREATE TABLE IF NOT EXISTS production_job_stage_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id      UUID NOT NULL REFERENCES production_jobs(id) ON DELETE CASCADE,
  from_stage  TEXT,
  to_stage    TEXT NOT NULL,
  event_type  TEXT NOT NULL,
  note        TEXT NOT NULL DEFAULT '',
  actor_id    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT production_job_history_stage_check
    CHECK (
      (from_stage IS NULL OR from_stage IN (
        'preparation', 'prepress', 'printing', 'quality_control', 'completed'
      ))
      AND to_stage IN (
        'preparation', 'prepress', 'printing', 'quality_control', 'completed'
      )
    ),
  CONSTRAINT production_job_history_event_check
    CHECK (event_type IN ('created', 'advanced', 'blocked', 'unblocked', 'completed'))
);

CREATE INDEX IF NOT EXISTS production_job_stage_history_job_idx
ON production_job_stage_history(job_id, created_at DESC);

ALTER TABLE production_job_controllers ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_job_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_job_stage_history ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'production_jobs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE production_jobs;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION record_production_job_created_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO production_job_stage_history(
    job_id,
    from_stage,
    to_stage,
    event_type,
    actor_id
  )
  VALUES (
    NEW.id,
    NULL,
    NEW.stage_code,
    'created',
    NEW.created_by
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS production_job_created_history_v1 ON production_jobs;

CREATE TRIGGER production_job_created_history_v1
AFTER INSERT ON production_jobs
FOR EACH ROW
EXECUTE FUNCTION record_production_job_created_v1();

INSERT INTO production_job_stage_history(
  job_id,
  from_stage,
  to_stage,
  event_type,
  actor_id,
  created_at
)
SELECT
  job.id,
  NULL,
  job.stage_code,
  'created',
  job.created_by,
  job.created_at
FROM production_jobs AS job
WHERE NOT EXISTS (
  SELECT 1
  FROM production_job_stage_history AS history
  WHERE history.job_id = job.id
);

CREATE OR REPLACE FUNCTION can_manage_production_job_stage_v1(
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
        has_organization_role_v2(job.organization_id, ARRAY['admin'])
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

CREATE OR REPLACE FUNCTION can_control_production_job_block_v1(
  target_job UUID,
  requested_action TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT requested_action IN ('block', 'unblock')
    AND EXISTS (
      SELECT 1
      FROM production_jobs AS job
      JOIN production_job_controllers AS controller
        ON controller.job_id = job.id
       AND controller.user_id = auth.uid()
      JOIN organization_members AS member
        ON member.organization_id = job.organization_id
       AND member.user_id = controller.user_id
       AND member.role = 'employee'
      WHERE job.id = target_job
        AND (
          (requested_action = 'block' AND controller.can_block)
          OR (requested_action = 'unblock' AND controller.can_unblock)
        )
        AND EXISTS (
          SELECT 1
          FROM organization_member_functions AS function
          WHERE function.organization_id = job.organization_id
            AND function.user_id = controller.user_id
            AND function.function_name = 'inspectionSpecialist'
        )
    );
$$;

CREATE OR REPLACE FUNCTION list_production_works_v1(
  target_organization UUID,
  search_text TEXT DEFAULT '',
  requested_view TEXT DEFAULT 'active',
  cursor_updated_at TIMESTAMPTZ DEFAULT NULL,
  cursor_id UUID DEFAULT NULL,
  page_size INTEGER DEFAULT 50
)
RETURNS TABLE(
  job_id UUID,
  job_number TEXT,
  customer_id UUID,
  customer_name TEXT,
  job_status TEXT,
  stage_code TEXT,
  flow_state TEXT,
  active_block_count BIGINT,
  updated_at TIMESTAMPTZ,
  can_advance BOOLEAN,
  can_assign_controllers BOOLEAN,
  can_block BOOLEAN,
  can_unblock BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  clean_search TEXT := lower(trim(COALESCE(search_text, '')));
  safe_size INTEGER := LEAST(GREATEST(COALESCE(page_size, 50), 1), 100);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF requested_view NOT IN ('active', 'blocked', 'completed', 'archived', 'all') THEN
    RAISE EXCEPTION 'Unknown work view';
  END IF;
  IF NOT has_organization_role_v2(
    target_organization,
    ARRAY['owner', 'admin', 'employee', 'customer']
  ) THEN
    RAISE EXCEPTION 'Organization access required';
  END IF;

  RETURN QUERY
  SELECT
    job.id,
    job.number,
    job.customer_id,
    COALESCE(customer.name, job.requested_customer_name, '')::TEXT,
    job.status,
    job.stage_code,
    job.flow_state,
    COUNT(block.id) FILTER (WHERE block.resolved_at IS NULL),
    job.updated_at,
    can_manage_production_job_stage_v1(job.id),
    can_manage_production_job_stage_v1(job.id),
    can_control_production_job_block_v1(job.id, 'block'),
    can_control_production_job_block_v1(job.id, 'unblock')
  FROM production_jobs AS job
  LEFT JOIN organization_customers AS customer
    ON customer.id = job.customer_id
  LEFT JOIN production_job_blocks AS block
    ON block.job_id = job.id
  WHERE job.organization_id = target_organization
    AND can_view_production_job_v1(job.id)
    AND (
      requested_view = 'all'
      OR (requested_view = 'active' AND job.status = 'active')
      OR (requested_view = 'blocked' AND job.status = 'active' AND job.flow_state = 'blocked')
      OR (requested_view = 'completed' AND job.status = 'completed')
      OR (requested_view = 'archived' AND job.status = 'archived')
    )
    AND (
      clean_search = ''
      OR lower(job.number) LIKE '%' || clean_search || '%'
      OR lower(COALESCE(customer.name, job.requested_customer_name, ''))
        LIKE '%' || clean_search || '%'
    )
    AND (
      cursor_updated_at IS NULL
      OR cursor_id IS NULL
      OR (job.updated_at, job.id) < (cursor_updated_at, cursor_id)
    )
  GROUP BY job.id, customer.name
  ORDER BY job.updated_at DESC, job.id DESC
  LIMIT safe_size;
END;
$$;

CREATE OR REPLACE FUNCTION get_production_work_v1(
  target_job UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
  is_customer BOOLEAN;
BEGIN
  IF NOT can_view_production_job_v1(target_job) THEN
    RAISE EXCEPTION 'Production job access denied';
  END IF;

  SELECT * INTO selected_job
  FROM production_jobs
  WHERE id = target_job;

  SELECT EXISTS (
    SELECT 1
    FROM production_job_participants AS participant
    WHERE participant.job_id = target_job
      AND participant.user_id = auth.uid()
      AND participant.participant_type = 'customer'
  ) INTO is_customer;

  RETURN jsonb_build_object(
    'job_id', selected_job.id,
    'job_number', selected_job.number,
    'customer_id', selected_job.customer_id,
    'customer_name', COALESCE(
      (SELECT customer.name FROM organization_customers AS customer
       WHERE customer.id = selected_job.customer_id),
      selected_job.requested_customer_name,
      ''
    ),
    'job_status', selected_job.status,
    'stage_code', selected_job.stage_code,
    'flow_state', selected_job.flow_state,
    'updated_at', selected_job.updated_at,
    'can_advance', can_manage_production_job_stage_v1(selected_job.id),
    'can_assign_controllers', can_manage_production_job_stage_v1(selected_job.id),
    'can_block', can_control_production_job_block_v1(selected_job.id, 'block'),
    'can_unblock', can_control_production_job_block_v1(selected_job.id, 'unblock'),
    'blocks', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', block.id,
        'stage_code', block.stage_code,
        'scope_label', block.scope_label,
        'reason', block.reason,
        'customer_visible', block.customer_visible,
        'created_by', block.created_by,
        'created_by_name', COALESCE(profile.display_name, profile.nickname, ''),
        'created_at', block.created_at,
        'resolved_by', block.resolved_by,
        'resolved_at', block.resolved_at,
        'resolution_note', block.resolution_note
      ) ORDER BY block.resolved_at NULLS FIRST, block.created_at DESC)
      FROM production_job_blocks AS block
      LEFT JOIN user_profiles AS profile ON profile.user_id = block.created_by
      WHERE block.job_id = selected_job.id
        AND (NOT is_customer OR block.customer_visible)
    ), '[]'::JSONB),
    'history', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', history.id,
        'from_stage', history.from_stage,
        'to_stage', history.to_stage,
        'event_type', history.event_type,
        'note', CASE
          WHEN is_customer AND history.event_type IN ('blocked', 'unblocked')
            THEN ''
          ELSE history.note
        END,
        'actor_id', history.actor_id,
        'actor_name', CASE
          WHEN is_customer THEN ''
          ELSE COALESCE(profile.display_name, profile.nickname, '')
        END,
        'created_at', history.created_at
      ) ORDER BY history.created_at DESC)
      FROM (
        SELECT *
        FROM production_job_stage_history
        WHERE job_id = selected_job.id
        ORDER BY created_at DESC
        LIMIT 50
      ) AS history
      LEFT JOIN user_profiles AS profile ON profile.user_id = history.actor_id
    ), '[]'::JSONB)
  );
END;
$$;

CREATE OR REPLACE FUNCTION list_job_controller_candidates_v1(
  target_job UUID
)
RETURNS TABLE(
  user_id UUID,
  display_name TEXT,
  nickname TEXT,
  can_block BOOLEAN,
  can_unblock BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_organization UUID;
BEGIN
  IF NOT can_manage_production_job_stage_v1(target_job) THEN
    RAISE EXCEPTION 'Controller assignment denied';
  END IF;

  SELECT organization_id INTO target_organization
  FROM production_jobs
  WHERE id = target_job;

  RETURN QUERY
  SELECT
    member.user_id,
    COALESCE(profile.display_name, '')::TEXT,
    COALESCE(profile.nickname, '')::TEXT,
    COALESCE(controller.can_block, FALSE),
    COALESCE(controller.can_unblock, FALSE)
  FROM organization_members AS member
  JOIN organization_member_functions AS function
    ON function.organization_id = member.organization_id
   AND function.user_id = member.user_id
   AND function.function_name = 'inspectionSpecialist'
  LEFT JOIN user_profiles AS profile ON profile.user_id = member.user_id
  LEFT JOIN production_job_controllers AS controller
    ON controller.job_id = target_job
   AND controller.user_id = member.user_id
  WHERE member.organization_id = target_organization
    AND member.role = 'employee'
  ORDER BY lower(COALESCE(NULLIF(profile.display_name, ''), profile.nickname, ''));
END;
$$;

CREATE OR REPLACE FUNCTION set_job_controller_v1(
  target_job UUID,
  target_user UUID,
  requested_can_block BOOLEAN,
  requested_can_unblock BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_organization UUID;
BEGIN
  IF NOT can_manage_production_job_stage_v1(target_job) THEN
    RAISE EXCEPTION 'Controller assignment denied';
  END IF;

  SELECT organization_id INTO target_organization
  FROM production_jobs
  WHERE id = target_job;

  IF NOT EXISTS (
    SELECT 1
    FROM organization_members AS member
    JOIN organization_member_functions AS function
      ON function.organization_id = member.organization_id
     AND function.user_id = member.user_id
     AND function.function_name = 'inspectionSpecialist'
    WHERE member.organization_id = target_organization
      AND member.user_id = target_user
      AND member.role = 'employee'
  ) THEN
    RAISE EXCEPTION 'Only an inspection specialist can control defects';
  END IF;

  IF NOT COALESCE(requested_can_block, FALSE)
    AND NOT COALESCE(requested_can_unblock, FALSE) THEN
    DELETE FROM production_job_controllers
    WHERE job_id = target_job AND user_id = target_user;
    RETURN;
  END IF;

  INSERT INTO production_job_controllers(
    job_id,
    user_id,
    can_block,
    can_unblock,
    assigned_by,
    assigned_at
  )
  VALUES (
    target_job,
    target_user,
    requested_can_block,
    requested_can_unblock,
    auth.uid(),
    now()
  )
  ON CONFLICT (job_id, user_id)
  DO UPDATE SET
    can_block = EXCLUDED.can_block,
    can_unblock = EXCLUDED.can_unblock,
    assigned_by = auth.uid(),
    assigned_at = now();

  INSERT INTO production_job_participants(job_id, user_id, participant_type, added_by)
  VALUES (target_job, target_user, 'operator', auth.uid())
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION block_production_job_v1(
  target_job UUID,
  target_scope_label TEXT,
  target_reason TEXT,
  requested_customer_visible BOOLEAN DEFAULT FALSE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
  new_block UUID;
  clean_scope TEXT := trim(COALESCE(target_scope_label, ''));
  clean_reason TEXT := trim(COALESCE(target_reason, ''));
BEGIN
  IF NOT can_control_production_job_block_v1(target_job, 'block') THEN
    RAISE EXCEPTION 'Defect blocking permission required';
  END IF;
  IF length(clean_scope) NOT BETWEEN 2 AND 160 THEN
    RAISE EXCEPTION 'Block scope must contain 2-160 characters';
  END IF;
  IF length(clean_reason) NOT BETWEEN 3 AND 1000 THEN
    RAISE EXCEPTION 'Block reason must contain 3-1000 characters';
  END IF;

  SELECT * INTO selected_job
  FROM production_jobs
  WHERE id = target_job
  FOR UPDATE;

  IF selected_job.status <> 'active' OR selected_job.flow_state = 'completed' THEN
    RAISE EXCEPTION 'Completed or archived work cannot be blocked';
  END IF;

  INSERT INTO production_job_blocks(
    job_id,
    stage_code,
    scope_label,
    reason,
    customer_visible,
    created_by
  )
  VALUES (
    selected_job.id,
    selected_job.stage_code,
    clean_scope,
    clean_reason,
    COALESCE(requested_customer_visible, FALSE),
    auth.uid()
  )
  RETURNING id INTO new_block;

  UPDATE production_jobs
  SET flow_state = 'blocked', updated_by = auth.uid(), updated_at = now()
  WHERE id = selected_job.id;

  INSERT INTO production_job_stage_history(
    job_id, from_stage, to_stage, event_type, note, actor_id
  )
  VALUES (
    selected_job.id,
    selected_job.stage_code,
    selected_job.stage_code,
    'blocked',
    clean_scope || ': ' || clean_reason,
    auth.uid()
  );

  RETURN new_block;
END;
$$;

CREATE OR REPLACE FUNCTION resolve_production_job_block_v1(
  target_block UUID,
  target_resolution_note TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_block production_job_blocks%ROWTYPE;
  selected_job production_jobs%ROWTYPE;
BEGIN
  SELECT * INTO selected_block
  FROM production_job_blocks
  WHERE id = target_block
  FOR UPDATE;

  IF selected_block.id IS NULL OR selected_block.resolved_at IS NOT NULL THEN
    RAISE EXCEPTION 'Active defect block not found';
  END IF;
  IF NOT can_control_production_job_block_v1(selected_block.job_id, 'unblock') THEN
    RAISE EXCEPTION 'Defect unblock permission required';
  END IF;

  SELECT * INTO selected_job
  FROM production_jobs
  WHERE id = selected_block.job_id
  FOR UPDATE;

  UPDATE production_job_blocks
  SET
    resolved_by = auth.uid(),
    resolved_at = now(),
    resolution_note = trim(COALESCE(target_resolution_note, ''))
  WHERE id = selected_block.id;

  IF NOT EXISTS (
    SELECT 1
    FROM production_job_blocks AS block
    WHERE block.job_id = selected_job.id
      AND block.resolved_at IS NULL
  ) THEN
    UPDATE production_jobs
    SET flow_state = 'ready', updated_by = auth.uid(), updated_at = now()
    WHERE id = selected_job.id;
  ELSE
    UPDATE production_jobs
    SET updated_by = auth.uid(), updated_at = now()
    WHERE id = selected_job.id;
  END IF;

  INSERT INTO production_job_stage_history(
    job_id, from_stage, to_stage, event_type, note, actor_id
  )
  VALUES (
    selected_job.id,
    selected_job.stage_code,
    selected_job.stage_code,
    'unblocked',
    trim(COALESCE(target_resolution_note, '')),
    auth.uid()
  );
END;
$$;

CREATE OR REPLACE FUNCTION advance_production_job_stage_v1(
  target_job UUID,
  target_note TEXT DEFAULT ''
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
  next_stage TEXT;
BEGIN
  IF NOT can_manage_production_job_stage_v1(target_job) THEN
    RAISE EXCEPTION 'Production stage management denied';
  END IF;

  SELECT * INTO selected_job
  FROM production_jobs
  WHERE id = target_job
  FOR UPDATE;

  IF selected_job.status <> 'active' OR selected_job.flow_state = 'completed' THEN
    RAISE EXCEPTION 'Work is not active';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM production_job_blocks AS block
    WHERE block.job_id = selected_job.id
      AND block.resolved_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Resolve all defect blocks before advancing the work';
  END IF;

  next_stage := CASE selected_job.stage_code
    WHEN 'preparation' THEN 'prepress'
    WHEN 'prepress' THEN 'printing'
    WHEN 'printing' THEN 'quality_control'
    WHEN 'quality_control' THEN 'completed'
    ELSE NULL
  END;
  IF next_stage IS NULL THEN
    RAISE EXCEPTION 'Work is already at the final stage';
  END IF;

  UPDATE production_jobs
  SET
    stage_code = next_stage,
    flow_state = CASE WHEN next_stage = 'completed' THEN 'completed' ELSE 'ready' END,
    status = CASE WHEN next_stage = 'completed' THEN 'completed' ELSE status END,
    stage_updated_at = now(),
    updated_by = auth.uid(),
    updated_at = now()
  WHERE id = selected_job.id;

  INSERT INTO production_job_stage_history(
    job_id, from_stage, to_stage, event_type, note, actor_id
  )
  VALUES (
    selected_job.id,
    selected_job.stage_code,
    next_stage,
    CASE WHEN next_stage = 'completed' THEN 'completed' ELSE 'advanced' END,
    trim(COALESCE(target_note, '')),
    auth.uid()
  );

  RETURN next_stage;
END;
$$;

REVOKE ALL ON TABLE production_job_controllers FROM PUBLIC;
REVOKE ALL ON TABLE production_job_controllers FROM authenticated;
REVOKE ALL ON TABLE production_job_blocks FROM PUBLIC;
REVOKE ALL ON TABLE production_job_blocks FROM authenticated;
REVOKE ALL ON TABLE production_job_stage_history FROM PUBLIC;
REVOKE ALL ON TABLE production_job_stage_history FROM authenticated;

REVOKE ALL ON FUNCTION can_manage_production_job_stage_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION can_control_production_job_block_v1(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_production_works_v1(UUID, TEXT, TEXT, TIMESTAMPTZ, UUID, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_production_work_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_job_controller_candidates_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION set_job_controller_v1(UUID, UUID, BOOLEAN, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION block_production_job_v1(UUID, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION resolve_production_job_block_v1(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION advance_production_job_stage_v1(UUID, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION can_manage_production_job_stage_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION can_control_production_job_block_v1(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION list_production_works_v1(UUID, TEXT, TEXT, TIMESTAMPTZ, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_production_work_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION list_job_controller_candidates_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION set_job_controller_v1(UUID, UUID, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION block_production_job_v1(UUID, TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION resolve_production_job_block_v1(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION advance_production_job_stage_v1(UUID, TEXT) TO authenticated;

COMMIT;
