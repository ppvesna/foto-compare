-- Job references are internal production assets. External customers only see
-- files deliberately sent to the customer-facing work chat.

BEGIN;

DROP POLICY IF EXISTS production_job_references_select_v1
ON production_job_references;
CREATE POLICY production_job_references_select_v1
ON production_job_references
FOR SELECT
TO authenticated
USING (is_internal_production_user_v1(job_id));

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
      COALESCE((storage.foldername(name))[5], '') IN (
        'chat-internal',
        'references'
      )
      AND can_view_internal_production_asset_v1(
        (storage.foldername(name))[2], (storage.foldername(name))[4]
      )
    )
    OR
    (
      COALESCE((storage.foldername(name))[5], '') NOT IN (
        'chat-internal',
        'references'
      )
      AND can_view_production_job_asset_v1(
        (storage.foldername(name))[2], (storage.foldername(name))[4]
      )
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

  IF selected_job.id IS NULL OR NOT is_internal_production_user_v1(
    selected_job.id
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

REVOKE ALL ON FUNCTION get_active_job_reference_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION set_active_job_reference_v1(
  UUID, TEXT, TEXT, TEXT, TEXT, JSONB
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_active_job_reference_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION set_active_job_reference_v1(
  UUID, TEXT, TEXT, TEXT, TEXT, JSONB
) TO authenticated;

COMMIT;
