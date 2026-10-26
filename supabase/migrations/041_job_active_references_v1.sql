-- Keep one explicit working reference per production job. A replacement only
-- becomes active after its binary and metadata have both been saved.

BEGIN;

CREATE TABLE IF NOT EXISTS production_job_references (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id          UUID NOT NULL REFERENCES production_jobs(id) ON DELETE CASCADE,
  reference_key   TEXT NOT NULL,
  label           TEXT NOT NULL,
  asset_id        TEXT NOT NULL,
  object_path     TEXT NOT NULL,
  layout_profile  JSONB,
  created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT production_job_reference_key_check
    CHECK (length(trim(reference_key)) BETWEEN 1 AND 120),
  CONSTRAINT production_job_reference_label_check
    CHECK (length(trim(label)) BETWEEN 1 AND 160),
  CONSTRAINT production_job_reference_asset_check
    CHECK (length(trim(asset_id)) BETWEEN 1 AND 180)
);

CREATE UNIQUE INDEX IF NOT EXISTS production_job_references_job_key
ON production_job_references(job_id, reference_key);

CREATE INDEX IF NOT EXISTS production_job_references_job_updated
ON production_job_references(job_id, updated_at DESC);

ALTER TABLE production_jobs
ADD COLUMN IF NOT EXISTS active_reference_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'production_jobs_active_reference_fk'
  ) THEN
    ALTER TABLE production_jobs
    ADD CONSTRAINT production_jobs_active_reference_fk
    FOREIGN KEY (active_reference_id)
    REFERENCES production_job_references(id)
    ON DELETE SET NULL;
  END IF;
END;
$$;

ALTER TABLE production_job_references ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS production_job_references_select_v1
ON production_job_references;
CREATE POLICY production_job_references_select_v1
ON production_job_references
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM production_jobs AS job
    WHERE job.id = production_job_references.job_id
      AND can_view_production_job_asset_v1(
        job.organization_id::TEXT,
        job.id::TEXT
      )
  )
);

CREATE OR REPLACE FUNCTION get_active_job_reference_v1(target_job UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
  selected_reference production_job_references%ROWTYPE;
BEGIN
  SELECT * INTO selected_job
  FROM production_jobs
  WHERE id = target_job;

  IF selected_job.id IS NULL OR NOT can_view_production_job_asset_v1(
    selected_job.organization_id::TEXT,
    selected_job.id::TEXT
  ) THEN
    RAISE EXCEPTION 'Production job is not available';
  END IF;

  IF selected_job.active_reference_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO selected_reference
  FROM production_job_references
  WHERE id = selected_job.active_reference_id
    AND job_id = selected_job.id;

  IF selected_reference.id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'reference_key', selected_reference.reference_key,
    'label', selected_reference.label,
    'asset_id', selected_reference.asset_id,
    'object_path', selected_reference.object_path,
    'layout_profile', selected_reference.layout_profile,
    'created_at', selected_reference.created_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION set_active_job_reference_v1(
  target_job UUID,
  target_reference_key TEXT,
  target_label TEXT,
  target_asset_id TEXT,
  target_object_path TEXT,
  target_layout_profile JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_job production_jobs%ROWTYPE;
  selected_reference production_job_references%ROWTYPE;
  expected_prefix TEXT;
BEGIN
  SELECT * INTO selected_job
  FROM production_jobs
  WHERE id = target_job
  FOR UPDATE;

  IF selected_job.id IS NULL OR NOT can_write_production_job_asset_v1(
    selected_job.organization_id::TEXT,
    selected_job.id::TEXT
  ) THEN
    RAISE EXCEPTION 'Production job is not writable';
  END IF;

  IF length(trim(target_reference_key)) NOT BETWEEN 1 AND 120 THEN
    RAISE EXCEPTION 'Reference key must contain 1-120 characters';
  END IF;
  IF length(trim(target_label)) NOT BETWEEN 1 AND 160 THEN
    RAISE EXCEPTION 'Reference label must contain 1-160 characters';
  END IF;
  IF length(trim(target_asset_id)) NOT BETWEEN 1 AND 180 THEN
    RAISE EXCEPTION 'Reference asset id must contain 1-180 characters';
  END IF;

  expected_prefix := 'organizations/' || selected_job.organization_id::TEXT ||
    '/jobs/' || selected_job.id::TEXT || '/';
  IF left(target_object_path, length(expected_prefix)) <> expected_prefix THEN
    RAISE EXCEPTION 'Reference object path does not belong to the job';
  END IF;

  INSERT INTO production_job_references(
    job_id,
    reference_key,
    label,
    asset_id,
    object_path,
    layout_profile,
    created_by,
    updated_by
  )
  VALUES (
    selected_job.id,
    trim(target_reference_key),
    trim(target_label),
    trim(target_asset_id),
    trim(target_object_path),
    target_layout_profile,
    auth.uid(),
    auth.uid()
  )
  ON CONFLICT (job_id, reference_key)
  DO UPDATE SET
    label = EXCLUDED.label,
    asset_id = EXCLUDED.asset_id,
    object_path = EXCLUDED.object_path,
    layout_profile = EXCLUDED.layout_profile,
    updated_by = auth.uid(),
    updated_at = now()
  RETURNING * INTO selected_reference;

  UPDATE production_jobs
  SET
    active_reference_id = selected_reference.id,
    updated_by = auth.uid(),
    updated_at = now()
  WHERE id = selected_job.id;

  RETURN jsonb_build_object(
    'reference_key', selected_reference.reference_key,
    'label', selected_reference.label,
    'asset_id', selected_reference.asset_id,
    'object_path', selected_reference.object_path,
    'layout_profile', selected_reference.layout_profile,
    'created_at', selected_reference.created_at
  );
END;
$$;

REVOKE ALL ON production_job_references FROM anon;
GRANT SELECT ON production_job_references TO authenticated;
GRANT EXECUTE ON FUNCTION get_active_job_reference_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION set_active_job_reference_v1(
  UUID, TEXT, TEXT, TEXT, TEXT, JSONB
) TO authenticated;

COMMIT;
