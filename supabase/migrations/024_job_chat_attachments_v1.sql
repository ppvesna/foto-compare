-- Private ordinary attachments in production-job chats.
-- Prerequisites: migrations 013, 015, 016, and 017.

BEGIN;

-- Team members already write job assets through migration 015. These
-- additional policies let an assigned customer representative add and manage
-- only objects below the dedicated /chat/ path of a job they can view.
DROP POLICY IF EXISTS trimatrix_job_chat_attachments_insert_v1
ON storage.objects;
CREATE POLICY trimatrix_job_chat_attachments_insert_v1
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND (storage.foldername(name))[5] = 'chat'
  AND can_view_production_job_asset_v1(
    (storage.foldername(name))[2],
    (storage.foldername(name))[4]
  )
);

DROP POLICY IF EXISTS trimatrix_job_chat_attachments_update_v1
ON storage.objects;
CREATE POLICY trimatrix_job_chat_attachments_update_v1
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND owner_id = auth.uid()::TEXT
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND (storage.foldername(name))[5] = 'chat'
  AND can_view_production_job_asset_v1(
    (storage.foldername(name))[2],
    (storage.foldername(name))[4]
  )
)
WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND owner_id = auth.uid()::TEXT
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND (storage.foldername(name))[5] = 'chat'
  AND can_view_production_job_asset_v1(
    (storage.foldername(name))[2],
    (storage.foldername(name))[4]
  )
);

DROP POLICY IF EXISTS trimatrix_job_chat_attachments_delete_v1
ON storage.objects;
CREATE POLICY trimatrix_job_chat_attachments_delete_v1
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND owner_id = auth.uid()::TEXT
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'jobs'
  AND (storage.foldername(name))[5] = 'chat'
  AND can_view_production_job_asset_v1(
    (storage.foldername(name))[2],
    (storage.foldername(name))[4]
  )
);

COMMIT;
