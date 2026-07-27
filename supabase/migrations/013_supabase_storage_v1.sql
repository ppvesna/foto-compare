-- Trimatrix private user asset storage.
-- This stage prepares personal cloud objects only. Organization/job sharing
-- will use separate paths and policies after job-scoped access is connected.

BEGIN;

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit
)
VALUES (
  'trimatrix-assets',
  'trimatrix-assets',
  FALSE,
  104857600
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

DROP POLICY IF EXISTS trimatrix_user_assets_select ON storage.objects;
DROP POLICY IF EXISTS trimatrix_user_assets_insert ON storage.objects;
DROP POLICY IF EXISTS trimatrix_user_assets_update ON storage.objects;
DROP POLICY IF EXISTS trimatrix_user_assets_delete ON storage.objects;

CREATE POLICY trimatrix_user_assets_select
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'users'
  AND (storage.foldername(name))[2] = auth.uid()::TEXT
);

CREATE POLICY trimatrix_user_assets_insert
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'users'
  AND (storage.foldername(name))[2] = auth.uid()::TEXT
);

CREATE POLICY trimatrix_user_assets_update
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'users'
  AND (storage.foldername(name))[2] = auth.uid()::TEXT
)
WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'users'
  AND (storage.foldername(name))[2] = auth.uid()::TEXT
);

CREATE POLICY trimatrix_user_assets_delete
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'users'
  AND (storage.foldername(name))[2] = auth.uid()::TEXT
);

COMMIT;
