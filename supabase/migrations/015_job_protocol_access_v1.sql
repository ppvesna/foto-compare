-- Job-scoped cloud protocols and preview assets.
-- Prerequisites: migrations 012, 013, and 014.

BEGIN;

ALTER TABLE cloud_check_protocols
ADD COLUMN IF NOT EXISTS preview_object_path TEXT;

UPDATE cloud_check_protocols
SET preview_object_path =
  'users/' || owner_user_id::TEXT || '/' || preview_asset_id
WHERE preview_asset_id IS NOT NULL
  AND preview_object_path IS NULL;

CREATE OR REPLACE FUNCTION can_view_production_job_asset_v1(
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
    SELECT 1
    FROM production_jobs AS job
    WHERE job.organization_id::TEXT = target_organization_text
      AND job.id::TEXT = target_job_text
      AND can_view_production_job_v1(job.id)
  );
$$;

CREATE OR REPLACE FUNCTION can_write_production_job_asset_v1(
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
    SELECT 1
    FROM production_jobs AS job
    WHERE job.organization_id::TEXT = target_organization_text
      AND job.id::TEXT = target_job_text
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
            AND participant.participant_type = 'operator'
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION can_view_production_job_asset_v1(TEXT, TEXT)
FROM PUBLIC;
REVOKE ALL ON FUNCTION can_write_production_job_asset_v1(TEXT, TEXT)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION can_view_production_job_asset_v1(TEXT, TEXT)
TO authenticated;
GRANT EXECUTE ON FUNCTION can_write_production_job_asset_v1(TEXT, TEXT)
TO authenticated;

DROP POLICY IF EXISTS cloud_check_protocols_select_job_v1
ON cloud_check_protocols;
CREATE POLICY cloud_check_protocols_select_job_v1
ON cloud_check_protocols
FOR SELECT
TO authenticated
USING (
  organization_id IS NOT NULL
  AND can_view_production_job_asset_v1(
    organization_id::TEXT,
    job_id
  )
);

DROP POLICY IF EXISTS trimatrix_job_assets_select_v1
ON storage.objects;
CREATE POLICY trimatrix_job_assets_select_v1
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND can_view_production_job_asset_v1(
    (storage.foldername(name))[2],
    (storage.foldername(name))[4]
  )
);

DROP POLICY IF EXISTS trimatrix_job_assets_insert_v1
ON storage.objects;
CREATE POLICY trimatrix_job_assets_insert_v1
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND can_write_production_job_asset_v1(
    (storage.foldername(name))[2],
    (storage.foldername(name))[4]
  )
);

DROP POLICY IF EXISTS trimatrix_job_assets_update_v1
ON storage.objects;
CREATE POLICY trimatrix_job_assets_update_v1
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND can_write_production_job_asset_v1(
    (storage.foldername(name))[2],
    (storage.foldername(name))[4]
  )
)
WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND can_write_production_job_asset_v1(
    (storage.foldername(name))[2],
    (storage.foldername(name))[4]
  )
);

DROP POLICY IF EXISTS trimatrix_job_assets_delete_v1
ON storage.objects;
CREATE POLICY trimatrix_job_assets_delete_v1
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND can_write_production_job_asset_v1(
    (storage.foldername(name))[2],
    (storage.foldername(name))[4]
  )
);

COMMIT;
