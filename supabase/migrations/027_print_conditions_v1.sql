-- Organization-owned print conditions for customer soft-proof previews.
-- Profiles belong to the production organization, never to a customer user.
-- Prerequisites: migrations 010, 012, 013, and 017.

BEGIN;

CREATE TABLE IF NOT EXISTS print_conditions (
  id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id            UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  display_name               TEXT NOT NULL,
  machine_name               TEXT NOT NULL,
  material_name              TEXT NOT NULL,
  ink_set                    TEXT NOT NULL DEFAULT 'CMYK',
  source_method              TEXT NOT NULL,
  status                     TEXT NOT NULL DEFAULT 'draft',
  measurement_condition      TEXT NOT NULL DEFAULT 'D50 · 2° · M1',
  media_white_l              DOUBLE PRECISION,
  media_white_a              DOUBLE PRECISION,
  media_white_b              DOUBLE PRECISION,
  camera_calibration_profile TEXT,
  training_patch_count       INTEGER NOT NULL DEFAULT 0,
  validation_patch_count     INTEGER NOT NULL DEFAULT 0,
  average_delta_e            DOUBLE PRECISION,
  maximum_delta_e            DOUBLE PRECISION,
  icc_file_name              TEXT,
  icc_size_bytes             INTEGER,
  icc_profile_class          TEXT,
  icc_color_space            TEXT,
  icc_connection_space       TEXT,
  icc_version                TEXT,
  icc_storage_path           TEXT,
  customer_visible           BOOLEAN NOT NULL DEFAULT FALSE,
  created_by                 UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  verified_by                UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT print_condition_source_check
    CHECK (source_method IN ('quickCamera', 'iccImport')),
  CONSTRAINT print_condition_status_check
    CHECK (status IN ('draft', 'verified', 'published', 'archived')),
  CONSTRAINT print_condition_name_check
    CHECK (length(trim(display_name)) BETWEEN 2 AND 120),
  CONSTRAINT print_condition_machine_check
    CHECK (length(trim(machine_name)) BETWEEN 1 AND 120),
  CONSTRAINT print_condition_material_check
    CHECK (length(trim(material_name)) BETWEEN 1 AND 120),
  CONSTRAINT print_condition_ink_check
    CHECK (length(trim(ink_set)) BETWEEN 1 AND 80),
  CONSTRAINT print_condition_white_check
    CHECK (
      (media_white_l IS NULL AND media_white_a IS NULL AND media_white_b IS NULL)
      OR
      (
        media_white_l BETWEEN 0 AND 100
        AND media_white_a BETWEEN -128 AND 127
        AND media_white_b BETWEEN -128 AND 127
      )
    )
);

CREATE INDEX IF NOT EXISTS print_conditions_org_status_idx
ON print_conditions(organization_id, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS production_job_print_conditions (
  job_id          UUID NOT NULL REFERENCES production_jobs(id) ON DELETE CASCADE,
  condition_id    UUID NOT NULL REFERENCES print_conditions(id) ON DELETE CASCADE,
  is_default      BOOLEAN NOT NULL DEFAULT FALSE,
  customer_visible BOOLEAN NOT NULL DEFAULT TRUE,
  assigned_by     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  assigned_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(job_id, condition_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS one_default_print_condition_per_job
ON production_job_print_conditions(job_id)
WHERE is_default;

ALTER TABLE print_conditions ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_job_print_conditions ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION can_manage_print_conditions_v1(
  target_organization UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM organization_members AS member
    WHERE member.organization_id = target_organization
      AND member.user_id = auth.uid()
      AND (
        member.role = 'owner'
        OR (
          member.role = 'employee'
          AND EXISTS (
            SELECT 1
            FROM organization_member_functions AS function
            WHERE function.organization_id = member.organization_id
              AND function.user_id = member.user_id
              AND function.function_name = 'inspectionSpecialist'
          )
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION list_print_conditions_v1(
  target_organization UUID,
  include_archived BOOLEAN DEFAULT FALSE
)
RETURNS SETOF print_conditions
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
    RAISE EXCEPTION 'Internal organization access required';
  END IF;

  RETURN QUERY
  SELECT condition.*
  FROM print_conditions AS condition
  WHERE condition.organization_id = target_organization
    AND (include_archived OR condition.status <> 'archived')
  ORDER BY condition.status = 'published' DESC,
           condition.updated_at DESC,
           lower(condition.display_name);
END;
$$;

CREATE OR REPLACE FUNCTION create_print_condition_draft_v1(
  target_organization UUID,
  target_display_name TEXT,
  target_machine_name TEXT,
  target_material_name TEXT,
  target_ink_set TEXT,
  target_source_method TEXT,
  target_measurement_condition TEXT DEFAULT 'D50 · 2° · M1'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  created_id UUID;
BEGIN
  IF NOT can_manage_print_conditions_v1(target_organization) THEN
    RAISE EXCEPTION 'Print condition specialist access required';
  END IF;
  IF target_source_method NOT IN ('quickCamera', 'iccImport') THEN
    RAISE EXCEPTION 'Unsupported print condition source';
  END IF;

  INSERT INTO print_conditions(
    organization_id,
    display_name,
    machine_name,
    material_name,
    ink_set,
    source_method,
    measurement_condition,
    created_by
  )
  VALUES (
    target_organization,
    trim(target_display_name),
    trim(target_machine_name),
    trim(target_material_name),
    trim(target_ink_set),
    target_source_method,
    trim(target_measurement_condition),
    auth.uid()
  )
  RETURNING id INTO created_id;

  RETURN created_id;
END;
$$;

CREATE OR REPLACE FUNCTION attach_print_condition_icc_v1(
  target_condition UUID,
  target_file_name TEXT,
  target_size_bytes INTEGER,
  target_profile_class TEXT,
  target_color_space TEXT,
  target_connection_space TEXT,
  target_version TEXT,
  target_storage_path TEXT,
  target_white_l DOUBLE PRECISION DEFAULT NULL,
  target_white_a DOUBLE PRECISION DEFAULT NULL,
  target_white_b DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected print_conditions%ROWTYPE;
BEGIN
  SELECT * INTO selected FROM print_conditions WHERE id = target_condition;
  IF NOT FOUND OR NOT can_manage_print_conditions_v1(selected.organization_id) THEN
    RAISE EXCEPTION 'Print condition specialist access required';
  END IF;
  IF selected.source_method <> 'iccImport' THEN
    RAISE EXCEPTION 'The condition is not an ICC import';
  END IF;
  IF target_profile_class <> 'prtr'
    OR target_color_space <> 'CMYK'
    OR target_connection_space NOT IN ('Lab ', 'XYZ ') THEN
    RAISE EXCEPTION 'Unsupported print ICC profile';
  END IF;

  UPDATE print_conditions
  SET
    icc_file_name = trim(target_file_name),
    icc_size_bytes = target_size_bytes,
    icc_profile_class = target_profile_class,
    icc_color_space = target_color_space,
    icc_connection_space = target_connection_space,
    icc_version = target_version,
    icc_storage_path = target_storage_path,
    media_white_l = target_white_l,
    media_white_a = target_white_a,
    media_white_b = target_white_b,
    updated_at = now()
  WHERE id = target_condition;
END;
$$;

CREATE OR REPLACE FUNCTION save_quick_print_condition_evidence_v1(
  target_condition UUID,
  target_camera_profile TEXT,
  target_training_patches INTEGER,
  target_validation_patches INTEGER,
  target_average_delta_e DOUBLE PRECISION,
  target_maximum_delta_e DOUBLE PRECISION,
  target_white_l DOUBLE PRECISION,
  target_white_a DOUBLE PRECISION,
  target_white_b DOUBLE PRECISION
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected print_conditions%ROWTYPE;
BEGIN
  SELECT * INTO selected FROM print_conditions WHERE id = target_condition;
  IF NOT FOUND OR NOT can_manage_print_conditions_v1(selected.organization_id) THEN
    RAISE EXCEPTION 'Print condition specialist access required';
  END IF;
  IF selected.source_method <> 'quickCamera' THEN
    RAISE EXCEPTION 'The condition is not a quick camera profile';
  END IF;
  IF length(trim(target_camera_profile)) = 0
    OR target_training_patches < 4
    OR target_validation_patches < 1
    OR target_average_delta_e < 0
    OR target_maximum_delta_e < target_average_delta_e THEN
    RAISE EXCEPTION 'Incomplete quick profile validation';
  END IF;

  UPDATE print_conditions
  SET
    camera_calibration_profile = trim(target_camera_profile),
    training_patch_count = target_training_patches,
    validation_patch_count = target_validation_patches,
    average_delta_e = target_average_delta_e,
    maximum_delta_e = target_maximum_delta_e,
    media_white_l = target_white_l,
    media_white_a = target_white_a,
    media_white_b = target_white_b,
    updated_at = now()
  WHERE id = target_condition;
END;
$$;

CREATE OR REPLACE FUNCTION set_print_condition_state_v1(
  target_condition UUID,
  target_status TEXT,
  requested_customer_visible BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected print_conditions%ROWTYPE;
  ready BOOLEAN;
BEGIN
  SELECT * INTO selected FROM print_conditions WHERE id = target_condition;
  IF NOT FOUND OR NOT can_manage_print_conditions_v1(selected.organization_id) THEN
    RAISE EXCEPTION 'Print condition specialist access required';
  END IF;
  IF target_status NOT IN ('draft', 'verified', 'published', 'archived') THEN
    RAISE EXCEPTION 'Unsupported print condition status';
  END IF;

  ready := CASE selected.source_method
    WHEN 'iccImport' THEN
      selected.icc_storage_path IS NOT NULL
      AND selected.icc_profile_class = 'prtr'
      AND selected.icc_color_space = 'CMYK'
      AND selected.icc_connection_space IN ('Lab ', 'XYZ ')
    ELSE
      selected.camera_calibration_profile IS NOT NULL
      AND selected.training_patch_count >= 4
      AND selected.validation_patch_count >= 1
      AND selected.average_delta_e IS NOT NULL
      AND selected.maximum_delta_e IS NOT NULL
      AND selected.media_white_l IS NOT NULL
  END;

  IF target_status IN ('verified', 'published') AND NOT ready THEN
    RAISE EXCEPTION 'The print condition does not have verified evidence';
  END IF;

  UPDATE print_conditions
  SET
    status = target_status,
    customer_visible = target_status = 'published' AND requested_customer_visible,
    verified_by = CASE
      WHEN target_status IN ('verified', 'published') THEN auth.uid()
      ELSE verified_by
    END,
    updated_at = now()
  WHERE id = target_condition;
END;
$$;

CREATE OR REPLACE FUNCTION assign_print_condition_to_job_v1(
  target_job UUID,
  target_condition UUID,
  requested_default BOOLEAN DEFAULT FALSE,
  requested_customer_visible BOOLEAN DEFAULT TRUE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
  selected_condition print_conditions%ROWTYPE;
BEGIN
  SELECT * INTO selected_job FROM production_jobs WHERE id = target_job;
  SELECT * INTO selected_condition FROM print_conditions WHERE id = target_condition;
  IF NOT FOUND
    OR selected_job.organization_id IS DISTINCT FROM selected_condition.organization_id
    OR NOT can_manage_print_conditions_v1(selected_job.organization_id) THEN
    RAISE EXCEPTION 'Print condition assignment denied';
  END IF;
  IF selected_condition.status <> 'published' THEN
    RAISE EXCEPTION 'Only a published print condition can be assigned';
  END IF;

  IF requested_default THEN
    UPDATE production_job_print_conditions
    SET is_default = FALSE
    WHERE job_id = target_job;
  END IF;

  INSERT INTO production_job_print_conditions(
    job_id,
    condition_id,
    is_default,
    customer_visible,
    assigned_by
  )
  VALUES (
    target_job,
    target_condition,
    requested_default,
    requested_customer_visible,
    auth.uid()
  )
  ON CONFLICT(job_id, condition_id) DO UPDATE SET
    is_default = EXCLUDED.is_default,
    customer_visible = EXCLUDED.customer_visible,
    assigned_by = auth.uid(),
    assigned_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION list_job_print_conditions_v1(target_job UUID)
RETURNS TABLE(
  condition_id UUID,
  display_name TEXT,
  machine_name TEXT,
  material_name TEXT,
  source_method TEXT,
  measurement_condition TEXT,
  media_white_l DOUBLE PRECISION,
  media_white_a DOUBLE PRECISION,
  media_white_b DOUBLE PRECISION,
  average_delta_e DOUBLE PRECISION,
  maximum_delta_e DOUBLE PRECISION,
  is_default BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor_role TEXT;
BEGIN
  IF NOT can_view_production_job_v1(target_job) THEN
    RAISE EXCEPTION 'Job access required';
  END IF;

  SELECT member.role INTO actor_role
  FROM production_jobs AS job
  JOIN organization_members AS member
    ON member.organization_id = job.organization_id
   AND member.user_id = auth.uid()
  WHERE job.id = target_job;

  RETURN QUERY
  SELECT
    condition.id,
    condition.display_name,
    condition.machine_name,
    condition.material_name,
    condition.source_method,
    condition.measurement_condition,
    condition.media_white_l,
    condition.media_white_a,
    condition.media_white_b,
    condition.average_delta_e,
    condition.maximum_delta_e,
    assignment.is_default
  FROM production_job_print_conditions AS assignment
  JOIN print_conditions AS condition ON condition.id = assignment.condition_id
  WHERE assignment.job_id = target_job
    AND condition.status = 'published'
    AND (
      actor_role <> 'customer'
      OR (assignment.customer_visible AND condition.customer_visible)
    )
  ORDER BY assignment.is_default DESC, lower(condition.display_name);
END;
$$;

DROP POLICY IF EXISTS print_conditions_internal_read_v1 ON print_conditions;
CREATE POLICY print_conditions_internal_read_v1
ON print_conditions
FOR SELECT TO authenticated
USING (
  has_organization_role_v2(
    organization_id,
    ARRAY['owner', 'admin', 'employee']
  )
);

DROP POLICY IF EXISTS print_condition_assignments_internal_read_v1
ON production_job_print_conditions;
CREATE POLICY print_condition_assignments_internal_read_v1
ON production_job_print_conditions
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM production_jobs AS job
    WHERE job.id = production_job_print_conditions.job_id
      AND has_organization_role_v2(
        job.organization_id,
        ARRAY['owner', 'admin', 'employee']
      )
  )
);

DROP POLICY IF EXISTS trimatrix_print_profile_objects_select_v1 ON storage.objects;
CREATE POLICY trimatrix_print_profile_objects_select_v1
ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'print-profiles'
  AND can_manage_print_conditions_v1((storage.foldername(name))[2]::UUID)
);

DROP POLICY IF EXISTS trimatrix_print_profile_objects_insert_v1 ON storage.objects;
CREATE POLICY trimatrix_print_profile_objects_insert_v1
ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'print-profiles'
  AND can_manage_print_conditions_v1((storage.foldername(name))[2]::UUID)
);

DROP POLICY IF EXISTS trimatrix_print_profile_objects_update_v1 ON storage.objects;
CREATE POLICY trimatrix_print_profile_objects_update_v1
ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'print-profiles'
  AND can_manage_print_conditions_v1((storage.foldername(name))[2]::UUID)
)
WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'print-profiles'
  AND can_manage_print_conditions_v1((storage.foldername(name))[2]::UUID)
);

DROP POLICY IF EXISTS trimatrix_print_profile_objects_delete_v1 ON storage.objects;
CREATE POLICY trimatrix_print_profile_objects_delete_v1
ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'print-profiles'
  AND can_manage_print_conditions_v1((storage.foldername(name))[2]::UUID)
);

REVOKE ALL ON TABLE print_conditions FROM PUBLIC;
REVOKE ALL ON TABLE production_job_print_conditions FROM PUBLIC;
REVOKE ALL ON FUNCTION can_manage_print_conditions_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_print_conditions_v1(UUID, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION create_print_condition_draft_v1(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION attach_print_condition_icc_v1(UUID, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
REVOKE ALL ON FUNCTION save_quick_print_condition_evidence_v1(UUID, TEXT, INTEGER, INTEGER, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
REVOKE ALL ON FUNCTION set_print_condition_state_v1(UUID, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION assign_print_condition_to_job_v1(UUID, UUID, BOOLEAN, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_job_print_conditions_v1(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION list_print_conditions_v1(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION can_manage_print_conditions_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION create_print_condition_draft_v1(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION attach_print_condition_icc_v1(UUID, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
GRANT EXECUTE ON FUNCTION save_quick_print_condition_evidence_v1(UUID, TEXT, INTEGER, INTEGER, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
GRANT EXECUTE ON FUNCTION set_print_condition_state_v1(UUID, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION assign_print_condition_to_job_v1(UUID, UUID, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION list_job_print_conditions_v1(UUID) TO authenticated;

COMMIT;
