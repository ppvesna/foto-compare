-- Production batches, physical units, inspection decisions, customer-safe
-- statuses, completed-work archive, and separate internal/customer job chats.
-- Prerequisites: migrations 012, 017, 029, and 030.

BEGIN;

ALTER TABLE production_jobs
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

ALTER TABLE production_jobs
ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS production_job_batches (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id            UUID NOT NULL REFERENCES production_jobs(id) ON DELETE CASCADE,
  sequence_no       INTEGER NOT NULL,
  employee_user_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  creation_reason   TEXT NOT NULL DEFAULT 'Работа создана',
  machine_label     TEXT NOT NULL DEFAULT '',
  material_label    TEXT NOT NULL DEFAULT '',
  format_label      TEXT NOT NULL DEFAULT '',
  inks_label        TEXT NOT NULL DEFAULT '',
  created_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at      TIMESTAMPTZ,
  UNIQUE(job_id, sequence_no),
  CONSTRAINT production_batch_sequence_check CHECK (sequence_no > 0),
  CONSTRAINT production_batch_reason_check
    CHECK (length(trim(creation_reason)) BETWEEN 2 AND 300)
);

CREATE INDEX IF NOT EXISTS production_job_batches_job_idx
ON production_job_batches(job_id, sequence_no);

CREATE TABLE IF NOT EXISTS production_units (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id     UUID NOT NULL REFERENCES production_job_batches(id) ON DELETE CASCADE,
  sequence_no  INTEGER NOT NULL,
  unit_type    TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending',
  created_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(batch_id, sequence_no),
  CONSTRAINT production_unit_sequence_check CHECK (sequence_no > 0),
  CONSTRAINT production_unit_type_check CHECK (unit_type IN ('stack', 'roll')),
  CONSTRAINT production_unit_status_check
    CHECK (status IN ('pending', 'checking', 'approved', 'blocked'))
);

CREATE INDEX IF NOT EXISTS production_units_batch_idx
ON production_units(batch_id, sequence_no);

CREATE TABLE IF NOT EXISTS production_inspections (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id       UUID NOT NULL REFERENCES production_units(id) ON DELETE CASCADE,
  sequence_no   INTEGER NOT NULL,
  status        TEXT NOT NULL DEFAULT 'checking',
  started_by    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_by    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  decided_at    TIMESTAMPTZ,
  decision_note TEXT NOT NULL DEFAULT '',
  UNIQUE(unit_id, sequence_no),
  CONSTRAINT production_inspection_sequence_check CHECK (sequence_no > 0),
  CONSTRAINT production_inspection_status_check
    CHECK (status IN ('checking', 'approved', 'blocked')),
  CONSTRAINT production_inspection_decision_check CHECK (
    (status = 'checking' AND decided_by IS NULL AND decided_at IS NULL)
    OR
    (status <> 'checking' AND decided_by IS NOT NULL AND decided_at IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS production_inspections_unit_idx
ON production_inspections(unit_id, sequence_no DESC);

CREATE TABLE IF NOT EXISTS production_inspection_attempts (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id          UUID NOT NULL REFERENCES production_inspections(id) ON DELETE CASCADE,
  sequence_no            INTEGER NOT NULL,
  protocol_owner_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  protocol_id            TEXT NOT NULL,
  score                  NUMERIC(6, 2) NOT NULL,
  attempted_by           UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  attempted_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(inspection_id, sequence_no),
  UNIQUE(protocol_owner_user_id, protocol_id),
  CONSTRAINT production_attempt_sequence_check CHECK (sequence_no > 0),
  CONSTRAINT production_attempt_protocol_check
    CHECK (length(trim(protocol_id)) BETWEEN 1 AND 160),
  CONSTRAINT production_attempt_score_check CHECK (score BETWEEN 0 AND 100)
);

CREATE INDEX IF NOT EXISTS production_inspection_attempts_inspection_idx
ON production_inspection_attempts(inspection_id, sequence_no);

ALTER TABLE production_job_blocks
ADD COLUMN IF NOT EXISTS batch_id UUID
REFERENCES production_job_batches(id) ON DELETE CASCADE;

ALTER TABLE production_job_blocks
ADD COLUMN IF NOT EXISTS unit_id UUID
REFERENCES production_units(id) ON DELETE CASCADE;

ALTER TABLE production_job_blocks
ADD COLUMN IF NOT EXISTS inspection_id UUID
REFERENCES production_inspections(id) ON DELETE SET NULL;

ALTER TABLE production_job_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_inspections ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_inspection_attempts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION is_internal_production_user_v1(target_job UUID)
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
        OR (
          has_organization_role_v2(job.organization_id, ARRAY['employee'])
          AND EXISTS (
            SELECT 1
            FROM production_job_participants AS participant
            WHERE participant.job_id = job.id
              AND participant.user_id = auth.uid()
              AND participant.participant_type IN ('operator', 'manager')
          )
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION is_production_admin_v1(target_job UUID)
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
      AND has_organization_role_v2(job.organization_id, ARRAY['admin'])
  );
$$;

CREATE OR REPLACE FUNCTION can_complete_production_work_v1(target_job UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT is_production_admin_v1(target_job)
    OR EXISTS (
      SELECT 1
      FROM production_job_participants AS participant
      JOIN production_jobs AS job ON job.id = participant.job_id
      WHERE participant.job_id = target_job
        AND participant.user_id = auth.uid()
        AND participant.participant_type = 'manager'
        AND has_organization_role_v2(job.organization_id, ARRAY['employee'])
    );
$$;

CREATE OR REPLACE FUNCTION ensure_initial_production_batch_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO production_job_batches(
    job_id, sequence_no, employee_user_id, creation_reason, created_by
  )
  VALUES (NEW.id, 1, NEW.created_by, 'Работа создана', NEW.created_by)
  ON CONFLICT (job_id, sequence_no) DO NOTHING;

  INSERT INTO chat_groups(
    organization_id, job_id, name, kind, created_by, scope_key
  )
  VALUES (
    NEW.organization_id,
    NEW.id,
    'Работа № ' || NEW.number || ' · производство',
    'job_internal',
    NEW.created_by,
    'job-internal:' || NEW.id::TEXT
  )
  ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS production_job_initial_batch_v1 ON production_jobs;
CREATE TRIGGER production_job_initial_batch_v1
AFTER INSERT ON production_jobs
FOR EACH ROW EXECUTE FUNCTION ensure_initial_production_batch_v1();

INSERT INTO production_job_batches(
  job_id, sequence_no, employee_user_id, creation_reason, created_by, created_at
)
SELECT job.id, 1, job.created_by, 'Исходная партия', job.created_by, job.created_at
FROM production_jobs AS job
ON CONFLICT (job_id, sequence_no) DO NOTHING;

ALTER TABLE chat_groups DROP CONSTRAINT IF EXISTS chat_groups_kind_check;
ALTER TABLE chat_groups ADD CONSTRAINT chat_groups_kind_check
CHECK (kind IN ('organization', 'group', 'direct', 'job', 'job_internal', 'service'));

INSERT INTO chat_groups(
  organization_id, job_id, name, kind, created_by, scope_key, created_at, updated_at
)
SELECT
  job.organization_id,
  job.id,
  'Работа № ' || job.number || ' · производство',
  'job_internal',
  job.created_by,
  'job-internal:' || job.id::TEXT,
  job.created_at,
  job.updated_at
FROM production_jobs AS job
ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL DO NOTHING;

CREATE OR REPLACE FUNCTION can_access_chat_group_v1(target_group UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM chat_groups AS chat
    WHERE chat.id = target_group
      AND NOT chat.is_deleted
      AND (
        (chat.kind = 'job_internal' AND chat.job_id IS NOT NULL
          AND is_internal_production_user_v1(chat.job_id))
        OR (chat.kind = 'job' AND chat.job_id IS NOT NULL
          AND can_view_production_job_v1(chat.job_id))
        OR (
          chat.job_id IS NULL
          AND chat.kind = 'organization'
          AND chat.organization_id IS NOT NULL
          AND has_organization_role_v2(
            chat.organization_id, ARRAY['owner', 'admin', 'employee']
          )
        )
        OR (
          chat.job_id IS NULL
          AND chat.kind <> 'organization'
          AND (
            chat.created_by = auth.uid()
            OR EXISTS (
              SELECT 1 FROM chat_group_members AS member
              WHERE member.group_id = chat.id AND member.user_id = auth.uid()
            )
          )
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION can_view_internal_production_asset_v1(
  target_organization_text TEXT,
  target_job_text TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM production_jobs AS job
    WHERE job.organization_id::TEXT = target_organization_text
      AND job.id::TEXT = target_job_text
      AND is_internal_production_user_v1(job.id)
  );
$$;

DROP POLICY IF EXISTS trimatrix_job_assets_select_v1 ON storage.objects;
CREATE POLICY trimatrix_job_assets_select_v1
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND (
    (
      (storage.foldername(name))[5] = 'chat-internal'
      AND can_view_internal_production_asset_v1(
        (storage.foldername(name))[2], (storage.foldername(name))[4]
      )
    )
    OR
    (
      COALESCE((storage.foldername(name))[5], '') <> 'chat-internal'
      AND can_view_production_job_asset_v1(
        (storage.foldername(name))[2], (storage.foldername(name))[4]
      )
    )
  )
);

DROP POLICY IF EXISTS trimatrix_job_internal_chat_insert_v1 ON storage.objects;
CREATE POLICY trimatrix_job_internal_chat_insert_v1
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND (storage.foldername(name))[5] = 'chat-internal'
  AND can_view_internal_production_asset_v1(
    (storage.foldername(name))[2], (storage.foldername(name))[4]
  )
);

DROP POLICY IF EXISTS trimatrix_job_internal_chat_update_v1 ON storage.objects;
CREATE POLICY trimatrix_job_internal_chat_update_v1
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'trimatrix-assets' AND owner_id = auth.uid()::TEXT
  AND (storage.foldername(name))[5] = 'chat-internal'
  AND can_view_internal_production_asset_v1(
    (storage.foldername(name))[2], (storage.foldername(name))[4]
  )
)
WITH CHECK (
  bucket_id = 'trimatrix-assets' AND owner_id = auth.uid()::TEXT
  AND (storage.foldername(name))[5] = 'chat-internal'
  AND can_view_internal_production_asset_v1(
    (storage.foldername(name))[2], (storage.foldername(name))[4]
  )
);

DROP POLICY IF EXISTS trimatrix_job_internal_chat_delete_v1 ON storage.objects;
CREATE POLICY trimatrix_job_internal_chat_delete_v1
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'trimatrix-assets' AND owner_id = auth.uid()::TEXT
  AND (storage.foldername(name))[5] = 'chat-internal'
  AND can_view_internal_production_asset_v1(
    (storage.foldername(name))[2], (storage.foldername(name))[4]
  )
);

CREATE OR REPLACE FUNCTION list_production_workers_v1(target_job UUID)
RETURNS TABLE(user_id UUID, display_name TEXT, nickname TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_organization UUID;
BEGIN
  IF NOT is_internal_production_user_v1(target_job) THEN
    RAISE EXCEPTION 'Internal production access required';
  END IF;
  SELECT organization_id INTO target_organization
  FROM production_jobs WHERE id = target_job;

  RETURN QUERY
  SELECT member.user_id,
    COALESCE(profile.display_name, '')::TEXT,
    COALESCE(profile.nickname, '')::TEXT
  FROM organization_members AS member
  LEFT JOIN user_profiles AS profile ON profile.user_id = member.user_id
  WHERE member.organization_id = target_organization
    AND member.role IN ('admin', 'employee')
  ORDER BY lower(COALESCE(NULLIF(profile.display_name, ''), profile.nickname, ''));
END;
$$;

CREATE OR REPLACE FUNCTION create_production_batch_v1(
  target_job UUID,
  target_employee UUID DEFAULT NULL,
  target_reason TEXT DEFAULT 'Новая партия',
  target_machine TEXT DEFAULT '',
  target_material TEXT DEFAULT '',
  target_format TEXT DEFAULT '',
  target_inks TEXT DEFAULT ''
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
  new_id UUID;
  next_no INTEGER;
  clean_reason TEXT := trim(COALESCE(target_reason, ''));
BEGIN
  IF NOT is_internal_production_user_v1(target_job) THEN
    RAISE EXCEPTION 'Internal production access required';
  END IF;
  SELECT * INTO selected_job FROM production_jobs WHERE id = target_job FOR UPDATE;
  IF selected_job.status <> 'active' THEN
    RAISE EXCEPTION 'Only an active work can receive a new batch';
  END IF;
  IF length(clean_reason) NOT BETWEEN 2 AND 300 THEN
    RAISE EXCEPTION 'Batch reason must contain 2-300 characters';
  END IF;
  IF target_employee IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM organization_members AS member
    WHERE member.organization_id = selected_job.organization_id
      AND member.user_id = target_employee
      AND member.role IN ('admin', 'employee')
  ) THEN
    RAISE EXCEPTION 'Selected employee is not available';
  END IF;

  SELECT COALESCE(MAX(sequence_no), 0) + 1 INTO next_no
  FROM production_job_batches WHERE job_id = target_job;

  UPDATE production_job_batches
  SET completed_at = COALESCE(completed_at, now())
  WHERE job_id = target_job AND completed_at IS NULL;

  INSERT INTO production_job_batches(
    job_id, sequence_no, employee_user_id, creation_reason,
    machine_label, material_label, format_label, inks_label, created_by
  ) VALUES (
    target_job, next_no, COALESCE(target_employee, auth.uid()), clean_reason,
    trim(COALESCE(target_machine, '')),
    trim(COALESCE(target_material, '')),
    trim(COALESCE(target_format, '')),
    trim(COALESCE(target_inks, '')),
    auth.uid()
  ) RETURNING id INTO new_id;

  UPDATE production_jobs SET updated_by = auth.uid(), updated_at = now()
  WHERE id = target_job;
  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION create_production_unit_v1(
  target_batch UUID,
  target_unit_type TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_batch production_job_batches%ROWTYPE;
  target_job UUID;
  next_no INTEGER;
  new_id UUID;
BEGIN
  SELECT * INTO selected_batch
  FROM production_job_batches WHERE id = target_batch FOR UPDATE;
  target_job := selected_batch.job_id;
  IF target_job IS NULL OR NOT is_internal_production_user_v1(target_job) THEN
    RAISE EXCEPTION 'Internal production access required';
  END IF;
  IF selected_batch.completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Only the current batch can receive a physical unit';
  END IF;
  IF target_unit_type NOT IN ('stack', 'roll') THEN
    RAISE EXCEPTION 'Unknown physical unit type';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM production_jobs WHERE id = target_job AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Work is not active';
  END IF;

  SELECT COALESCE(MAX(sequence_no), 0) + 1 INTO next_no
  FROM production_units WHERE batch_id = target_batch;
  INSERT INTO production_units(
    batch_id, sequence_no, unit_type, created_by
  ) VALUES (target_batch, next_no, target_unit_type, auth.uid())
  RETURNING id INTO new_id;
  UPDATE production_jobs SET updated_by = auth.uid(), updated_at = now()
  WHERE id = target_job;
  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION record_production_inspection_attempt_v1(
  target_unit UUID,
  target_protocol_id TEXT,
  target_score NUMERIC
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_job UUID;
  current_inspection UUID;
  next_inspection_no INTEGER;
  next_attempt_no INTEGER;
BEGIN
  SELECT batch.job_id INTO target_job
  FROM production_units AS unit
  JOIN production_job_batches AS batch ON batch.id = unit.batch_id
  WHERE unit.id = target_unit;
  IF target_job IS NULL OR NOT is_internal_production_user_v1(target_job) THEN
    RAISE EXCEPTION 'Internal production access required';
  END IF;
  IF length(trim(COALESCE(target_protocol_id, ''))) NOT BETWEEN 1 AND 160
    OR target_score NOT BETWEEN 0 AND 100 THEN
    RAISE EXCEPTION 'Invalid inspection result';
  END IF;

  SELECT id INTO current_inspection
  FROM production_inspections
  WHERE unit_id = target_unit AND status = 'checking'
  ORDER BY sequence_no DESC LIMIT 1;

  IF current_inspection IS NULL THEN
    SELECT COALESCE(MAX(sequence_no), 0) + 1 INTO next_inspection_no
    FROM production_inspections WHERE unit_id = target_unit;
    INSERT INTO production_inspections(unit_id, sequence_no, started_by)
    VALUES (target_unit, next_inspection_no, auth.uid())
    RETURNING id INTO current_inspection;
  END IF;

  SELECT COALESCE(MAX(sequence_no), 0) + 1 INTO next_attempt_no
  FROM production_inspection_attempts WHERE inspection_id = current_inspection;
  INSERT INTO production_inspection_attempts(
    inspection_id, sequence_no, protocol_owner_user_id,
    protocol_id, score, attempted_by
  ) VALUES (
    current_inspection, next_attempt_no, auth.uid(),
    trim(target_protocol_id), target_score, auth.uid()
  )
  ON CONFLICT (protocol_owner_user_id, protocol_id)
  DO UPDATE SET score = EXCLUDED.score, attempted_at = now();

  UPDATE production_units SET
    status = CASE WHEN status = 'blocked' THEN status ELSE 'checking' END,
    updated_at = now()
  WHERE id = target_unit;
  UPDATE production_jobs SET updated_by = auth.uid(), updated_at = now()
  WHERE id = target_job;
  RETURN current_inspection;
END;
$$;

CREATE OR REPLACE FUNCTION decide_production_inspection_v1(
  target_unit UUID,
  requested_decision TEXT,
  target_note TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_unit production_units%ROWTYPE;
  selected_batch production_job_batches%ROWTYPE;
  selected_job production_jobs%ROWTYPE;
  current_inspection production_inspections%ROWTYPE;
  scope_name TEXT;
BEGIN
  SELECT * INTO selected_unit FROM production_units WHERE id = target_unit FOR UPDATE;
  SELECT * INTO selected_batch FROM production_job_batches
  WHERE id = selected_unit.batch_id;
  SELECT * INTO selected_job FROM production_jobs
  WHERE id = selected_batch.job_id FOR UPDATE;
  IF selected_job.id IS NULL OR NOT is_internal_production_user_v1(selected_job.id) THEN
    RAISE EXCEPTION 'Internal production access required';
  END IF;
  IF requested_decision NOT IN ('approved', 'blocked') THEN
    RAISE EXCEPTION 'Unknown inspection decision';
  END IF;
  SELECT * INTO current_inspection FROM production_inspections
  WHERE unit_id = target_unit AND status = 'checking'
  ORDER BY sequence_no DESC LIMIT 1 FOR UPDATE;
  IF current_inspection.id IS NULL OR NOT EXISTS (
    SELECT 1 FROM production_inspection_attempts
    WHERE inspection_id = current_inspection.id
  ) THEN
    RAISE EXCEPTION 'Run at least one comparison before the decision';
  END IF;
  IF requested_decision = 'approved' AND EXISTS (
    SELECT 1 FROM production_job_blocks
    WHERE unit_id = target_unit AND resolved_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Only an administrator can remove an active block';
  END IF;

  UPDATE production_inspections SET
    status = requested_decision,
    decided_by = auth.uid(),
    decided_at = now(),
    decision_note = trim(COALESCE(target_note, ''))
  WHERE id = current_inspection.id;

  UPDATE production_units SET status = requested_decision, updated_at = now()
  WHERE id = target_unit;

  IF requested_decision = 'blocked' THEN
    scope_name := 'Партия №' || selected_batch.sequence_no || ' · ' ||
      CASE selected_unit.unit_type WHEN 'roll' THEN 'Рулон' ELSE 'Стопа' END ||
      ' №' || selected_unit.sequence_no;
    IF NOT EXISTS (
      SELECT 1 FROM production_job_blocks
      WHERE unit_id = target_unit AND resolved_at IS NULL
    ) THEN
      INSERT INTO production_job_blocks(
        job_id, stage_code, scope_label, reason, customer_visible,
        created_by, batch_id, unit_id, inspection_id
      ) VALUES (
        selected_job.id, selected_job.stage_code, scope_name,
        COALESCE(NULLIF(trim(target_note), ''), 'Не пройдена проверка'),
        FALSE, auth.uid(), selected_batch.id, target_unit, current_inspection.id
      );
    END IF;
    UPDATE production_jobs SET flow_state = 'blocked' WHERE id = selected_job.id;
  END IF;
  UPDATE production_jobs SET updated_by = auth.uid(), updated_at = now()
  WHERE id = selected_job.id;
END;
$$;

CREATE OR REPLACE FUNCTION block_production_unit_v1(
  target_unit UUID,
  target_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_unit production_units%ROWTYPE;
  selected_batch production_job_batches%ROWTYPE;
  selected_job production_jobs%ROWTYPE;
  new_block UUID;
  clean_reason TEXT := trim(COALESCE(target_reason, ''));
  scope_name TEXT;
BEGIN
  SELECT * INTO selected_unit FROM production_units WHERE id = target_unit FOR UPDATE;
  SELECT * INTO selected_batch FROM production_job_batches WHERE id = selected_unit.batch_id;
  SELECT * INTO selected_job FROM production_jobs WHERE id = selected_batch.job_id FOR UPDATE;
  IF selected_job.id IS NULL OR NOT is_internal_production_user_v1(selected_job.id) THEN
    RAISE EXCEPTION 'Internal production access required';
  END IF;
  IF length(clean_reason) NOT BETWEEN 3 AND 1000 THEN
    RAISE EXCEPTION 'Block reason must contain 3-1000 characters';
  END IF;
  IF EXISTS (
    SELECT 1 FROM production_job_blocks
    WHERE unit_id = target_unit AND resolved_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Physical unit is already blocked';
  END IF;
  scope_name := 'Партия №' || selected_batch.sequence_no || ' · ' ||
    CASE selected_unit.unit_type WHEN 'roll' THEN 'Рулон' ELSE 'Стопа' END ||
    ' №' || selected_unit.sequence_no;
  INSERT INTO production_job_blocks(
    job_id, stage_code, scope_label, reason, customer_visible,
    created_by, batch_id, unit_id
  ) VALUES (
    selected_job.id, selected_job.stage_code, scope_name, clean_reason,
    FALSE, auth.uid(), selected_batch.id, target_unit
  ) RETURNING id INTO new_block;
  UPDATE production_units SET status = 'blocked', updated_at = now()
  WHERE id = target_unit;
  UPDATE production_jobs SET flow_state = 'blocked', updated_by = auth.uid(), updated_at = now()
  WHERE id = selected_job.id;
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
  SELECT * INTO selected_block FROM production_job_blocks
  WHERE id = target_block FOR UPDATE;
  IF selected_block.id IS NULL OR selected_block.resolved_at IS NOT NULL THEN
    RAISE EXCEPTION 'Active defect block not found';
  END IF;
  IF NOT is_production_admin_v1(selected_block.job_id) THEN
    RAISE EXCEPTION 'Only an administrator can remove a block';
  END IF;
  SELECT * INTO selected_job FROM production_jobs
  WHERE id = selected_block.job_id FOR UPDATE;
  UPDATE production_job_blocks SET
    resolved_by = auth.uid(), resolved_at = now(),
    resolution_note = trim(COALESCE(target_resolution_note, ''))
  WHERE id = selected_block.id;
  IF selected_block.unit_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM production_job_blocks
    WHERE unit_id = selected_block.unit_id AND resolved_at IS NULL
  ) THEN
    UPDATE production_units SET status = 'approved', updated_at = now()
    WHERE id = selected_block.unit_id;
  END IF;
  UPDATE production_jobs SET
    flow_state = CASE WHEN EXISTS (
      SELECT 1 FROM production_job_blocks
      WHERE job_id = selected_job.id AND resolved_at IS NULL
    ) THEN 'blocked' ELSE 'ready' END,
    updated_by = auth.uid(), updated_at = now()
  WHERE id = selected_job.id;
  INSERT INTO production_job_stage_history(
    job_id, from_stage, to_stage, event_type, note, actor_id
  ) VALUES (
    selected_job.id, selected_job.stage_code, selected_job.stage_code,
    'unblocked', trim(COALESCE(target_resolution_note, '')), auth.uid()
  );
END;
$$;

CREATE OR REPLACE FUNCTION complete_production_work_v1(target_job UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
BEGIN
  IF NOT can_complete_production_work_v1(target_job) THEN
    RAISE EXCEPTION 'Work completion permission required';
  END IF;
  SELECT * INTO selected_job FROM production_jobs WHERE id = target_job FOR UPDATE;
  IF selected_job.status <> 'active' THEN RAISE EXCEPTION 'Work is not active'; END IF;
  IF EXISTS (
    SELECT 1 FROM production_job_blocks
    WHERE job_id = target_job AND resolved_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Resolve all blocks before completing the work';
  END IF;
  UPDATE production_jobs SET
    status = 'completed', stage_code = 'completed', flow_state = 'completed',
    completed_at = now(), archived_at = now(), stage_updated_at = now(),
    updated_by = auth.uid(), updated_at = now()
  WHERE id = target_job;
  UPDATE production_job_batches SET completed_at = COALESCE(completed_at, now())
  WHERE job_id = target_job;
  INSERT INTO production_job_stage_history(
    job_id, from_stage, to_stage, event_type, note, actor_id
  ) VALUES (
    target_job, selected_job.stage_code, 'completed', 'completed', '', auth.uid()
  );
END;
$$;

ALTER TABLE production_job_stage_history
DROP CONSTRAINT IF EXISTS production_job_history_event_check;
ALTER TABLE production_job_stage_history
ADD CONSTRAINT production_job_history_event_check
CHECK (event_type IN ('created', 'advanced', 'blocked', 'unblocked', 'completed', 'restored'));

CREATE OR REPLACE FUNCTION restore_production_work_v1(target_job UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
  restored_stage TEXT;
BEGIN
  IF NOT is_production_admin_v1(target_job) THEN
    RAISE EXCEPTION 'Only an administrator can restore a work';
  END IF;
  SELECT * INTO selected_job FROM production_jobs WHERE id = target_job FOR UPDATE;
  IF selected_job.status NOT IN ('completed', 'archived') THEN
    RAISE EXCEPTION 'Work is not archived';
  END IF;
  SELECT COALESCE(from_stage, 'quality_control') INTO restored_stage
  FROM production_job_stage_history
  WHERE job_id = target_job AND event_type = 'completed'
  ORDER BY created_at DESC LIMIT 1;
  IF restored_stage = 'completed' OR restored_stage IS NULL THEN
    restored_stage := 'quality_control';
  END IF;
  UPDATE production_jobs SET
    status = 'active', stage_code = restored_stage, flow_state = 'ready',
    completed_at = NULL, archived_at = NULL, stage_updated_at = now(),
    updated_by = auth.uid(), updated_at = now()
  WHERE id = target_job;
  INSERT INTO production_job_stage_history(
    job_id, from_stage, to_stage, event_type, note, actor_id
  ) VALUES (target_job, 'completed', restored_stage, 'restored', '', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION list_production_works_v2(
  target_organization UUID,
  search_text TEXT DEFAULT '',
  requested_view TEXT DEFAULT 'active',
  cursor_updated_at TIMESTAMPTZ DEFAULT NULL,
  cursor_id UUID DEFAULT NULL,
  page_size INTEGER DEFAULT 50
)
RETURNS TABLE(
  job_id UUID, job_number TEXT, customer_id UUID, customer_name TEXT,
  job_status TEXT, stage_code TEXT, flow_state TEXT,
  active_block_count BIGINT, updated_at TIMESTAMPTZ,
  can_advance BOOLEAN, can_assign_controllers BOOLEAN,
  can_block BOOLEAN, can_unblock BOOLEAN, is_customer BOOLEAN,
  can_create_batch BOOLEAN, can_complete BOOLEAN, can_restore BOOLEAN
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
  IF requested_view NOT IN ('active', 'archived') THEN
    RAISE EXCEPTION 'Unknown work view';
  END IF;
  IF NOT has_organization_role_v2(
    target_organization, ARRAY['owner', 'admin', 'employee', 'customer']
  ) THEN RAISE EXCEPTION 'Organization access required'; END IF;

  RETURN QUERY
  SELECT job.id, job.number, job.customer_id,
    COALESCE(customer.name, job.requested_customer_name, '')::TEXT,
    job.status,
    CASE WHEN member.role = 'customer' THEN
      CASE WHEN job.status IN ('completed', 'archived') THEN 'completed' ELSE 'preparation' END
      ELSE job.stage_code END,
    CASE WHEN member.role = 'customer' THEN
      CASE WHEN job.status IN ('completed', 'archived') THEN 'completed' ELSE 'ready' END
      ELSE job.flow_state END,
    CASE WHEN member.role = 'customer' THEN 0::BIGINT
      ELSE COUNT(block.id) FILTER (WHERE block.resolved_at IS NULL) END,
    job.updated_at,
    CASE WHEN member.role = 'customer' THEN FALSE ELSE can_manage_production_job_stage_v1(job.id) END,
    FALSE,
    CASE WHEN member.role = 'customer' THEN FALSE ELSE is_internal_production_user_v1(job.id) END,
    CASE WHEN member.role = 'customer' THEN FALSE ELSE is_production_admin_v1(job.id) END,
    member.role = 'customer',
    CASE WHEN member.role = 'customer' THEN FALSE ELSE is_internal_production_user_v1(job.id) END,
    CASE WHEN member.role = 'customer' THEN FALSE ELSE can_complete_production_work_v1(job.id) END,
    CASE WHEN member.role = 'customer' THEN FALSE ELSE is_production_admin_v1(job.id) END
  FROM production_jobs AS job
  LEFT JOIN organization_customers AS customer ON customer.id = job.customer_id
  LEFT JOIN organization_members AS member
    ON member.organization_id = job.organization_id AND member.user_id = auth.uid()
  LEFT JOIN production_job_blocks AS block ON block.job_id = job.id
  WHERE job.organization_id = target_organization
    AND can_view_production_job_v1(job.id)
    AND ((requested_view = 'active' AND job.status = 'active')
      OR (requested_view = 'archived' AND job.status IN ('completed', 'archived')))
    AND (clean_search = '' OR lower(job.number) LIKE '%' || clean_search || '%'
      OR lower(COALESCE(customer.name, job.requested_customer_name, ''))
        LIKE '%' || clean_search || '%')
    AND (cursor_updated_at IS NULL OR cursor_id IS NULL
      OR (job.updated_at, job.id) < (cursor_updated_at, cursor_id))
  GROUP BY job.id, customer.name, member.role
  ORDER BY job.updated_at DESC, job.id DESC
  LIMIT safe_size;
END;
$$;

CREATE OR REPLACE FUNCTION get_production_work_v2(target_job UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
  customer_mode BOOLEAN;
BEGIN
  IF NOT can_view_production_job_v1(target_job) THEN
    RAISE EXCEPTION 'Production job access denied';
  END IF;
  SELECT * INTO selected_job FROM production_jobs WHERE id = target_job;
  SELECT EXISTS (
    SELECT 1 FROM production_job_participants
    WHERE job_id = target_job AND user_id = auth.uid() AND participant_type = 'customer'
  ) INTO customer_mode;

  RETURN jsonb_build_object(
    'job_id', selected_job.id,
    'job_number', selected_job.number,
    'customer_id', selected_job.customer_id,
    'customer_name', COALESCE((SELECT name FROM organization_customers
      WHERE id = selected_job.customer_id), selected_job.requested_customer_name, ''),
    'job_status', selected_job.status,
    'stage_code', CASE WHEN customer_mode THEN
      CASE WHEN selected_job.status IN ('completed', 'archived') THEN 'completed' ELSE 'preparation' END
      ELSE selected_job.stage_code END,
    'flow_state', CASE WHEN customer_mode THEN
      CASE WHEN selected_job.status IN ('completed', 'archived') THEN 'completed' ELSE 'ready' END
      ELSE selected_job.flow_state END,
    'updated_at', selected_job.updated_at,
    'is_customer', customer_mode,
    'can_advance', NOT customer_mode AND can_manage_production_job_stage_v1(selected_job.id),
    'can_assign_controllers', FALSE,
    'can_block', NOT customer_mode AND is_internal_production_user_v1(selected_job.id),
    'can_unblock', NOT customer_mode AND is_production_admin_v1(selected_job.id),
    'can_create_batch', NOT customer_mode AND is_internal_production_user_v1(selected_job.id),
    'can_complete', NOT customer_mode AND can_complete_production_work_v1(selected_job.id),
    'can_restore', NOT customer_mode AND is_production_admin_v1(selected_job.id),
    'blocks', CASE WHEN customer_mode THEN '[]'::JSONB ELSE COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', block.id, 'stage_code', block.stage_code,
        'scope_label', block.scope_label, 'reason', block.reason,
        'customer_visible', FALSE,
        'created_by_name', COALESCE(profile.display_name, profile.nickname, ''),
        'created_at', block.created_at, 'resolved_at', block.resolved_at,
        'resolution_note', block.resolution_note
      ) ORDER BY block.resolved_at NULLS FIRST, block.created_at DESC)
      FROM production_job_blocks AS block
      LEFT JOIN user_profiles AS profile ON profile.user_id = block.created_by
      WHERE block.job_id = selected_job.id
    ), '[]'::JSONB) END,
    'history', CASE WHEN customer_mode THEN '[]'::JSONB ELSE COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', history.id, 'from_stage', history.from_stage,
        'to_stage', history.to_stage, 'event_type', history.event_type,
        'note', history.note,
        'actor_name', COALESCE(profile.display_name, profile.nickname, ''),
        'created_at', history.created_at
      ) ORDER BY history.created_at DESC)
      FROM (SELECT * FROM production_job_stage_history
        WHERE job_id = selected_job.id ORDER BY created_at DESC LIMIT 50) AS history
      LEFT JOIN user_profiles AS profile ON profile.user_id = history.actor_id
    ), '[]'::JSONB) END,
    'batches', CASE WHEN customer_mode THEN '[]'::JSONB ELSE COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', batch.id, 'sequence_no', batch.sequence_no,
        'employee_name', COALESCE(profile.display_name, profile.nickname, ''),
        'creation_reason', batch.creation_reason,
        'machine_label', batch.machine_label, 'material_label', batch.material_label,
        'format_label', batch.format_label, 'inks_label', batch.inks_label,
        'created_at', batch.created_at,
        'units', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', unit.id, 'batch_id', batch.id, 'batch_number', batch.sequence_no,
            'sequence_no', unit.sequence_no, 'unit_type', unit.unit_type,
            'status', unit.status, 'created_at', unit.created_at,
            'inspection_count', (SELECT COUNT(*) FROM production_inspections
              WHERE unit_id = unit.id),
            'attempt_count', (SELECT COUNT(*) FROM production_inspection_attempts AS attempt
              JOIN production_inspections AS inspection ON inspection.id = attempt.inspection_id
              WHERE inspection.unit_id = unit.id),
            'latest_score', (SELECT attempt.score FROM production_inspection_attempts AS attempt
              JOIN production_inspections AS inspection ON inspection.id = attempt.inspection_id
              WHERE inspection.unit_id = unit.id
              ORDER BY attempt.attempted_at DESC LIMIT 1)
          ) ORDER BY unit.sequence_no)
          FROM production_units AS unit WHERE unit.batch_id = batch.id
        ), '[]'::JSONB)
      ) ORDER BY batch.sequence_no DESC)
      FROM production_job_batches AS batch
      LEFT JOIN user_profiles AS profile ON profile.user_id = batch.employee_user_id
      WHERE batch.job_id = selected_job.id
    ), '[]'::JSONB) END
  );
END;
$$;

REVOKE ALL ON TABLE production_job_batches FROM PUBLIC, authenticated;
REVOKE ALL ON TABLE production_units FROM PUBLIC, authenticated;
REVOKE ALL ON TABLE production_inspections FROM PUBLIC, authenticated;
REVOKE ALL ON TABLE production_inspection_attempts FROM PUBLIC, authenticated;

REVOKE ALL ON FUNCTION is_internal_production_user_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION is_production_admin_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION can_complete_production_work_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_production_workers_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION create_production_batch_v1(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION create_production_unit_v1(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION record_production_inspection_attempt_v1(UUID, TEXT, NUMERIC) FROM PUBLIC;
REVOKE ALL ON FUNCTION decide_production_inspection_v1(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION block_production_unit_v1(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION complete_production_work_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION restore_production_work_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_production_works_v2(UUID, TEXT, TEXT, TIMESTAMPTZ, UUID, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_production_work_v2(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION can_view_internal_production_asset_v1(TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION is_internal_production_user_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION is_production_admin_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION can_complete_production_work_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION list_production_workers_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION create_production_batch_v1(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION create_production_unit_v1(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION record_production_inspection_attempt_v1(UUID, TEXT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION decide_production_inspection_v1(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION block_production_unit_v1(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION complete_production_work_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION restore_production_work_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION list_production_works_v2(UUID, TEXT, TEXT, TIMESTAMPTZ, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_production_work_v2(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION can_view_internal_production_asset_v1(TEXT, TEXT) TO authenticated;

COMMIT;
