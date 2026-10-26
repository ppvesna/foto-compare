-- Recover a working reference for existing jobs from the most recent cloud
-- protocol that already archived its exact source reference.

BEGIN;

WITH latest_reference AS (
  SELECT DISTINCT ON (job.id)
    job.id AS job_id,
    protocol.owner_user_id,
    COALESCE(
      NULLIF(trim(protocol.protocol_data ->> 'referenceId'), ''),
      'legacy-' || md5(protocol.reference_object_path)
    ) AS reference_key,
    COALESCE(
      NULLIF(trim(protocol.protocol_data ->> 'referenceLabel'), ''),
      'Эталон'
    ) AS label,
    protocol.reference_asset_id AS asset_id,
    protocol.reference_object_path AS object_path,
    protocol.protocol_created_at
  FROM production_jobs AS job
  JOIN cloud_check_protocols AS protocol
    ON protocol.organization_id = job.organization_id
   AND protocol.job_id = job.id::TEXT
  WHERE job.active_reference_id IS NULL
    AND protocol.reference_asset_id IS NOT NULL
    AND length(trim(protocol.reference_asset_id)) > 0
    AND protocol.reference_object_path IS NOT NULL
    AND length(trim(protocol.reference_object_path)) > 0
  ORDER BY job.id, protocol.protocol_created_at DESC
), inserted_reference AS (
  INSERT INTO production_job_references(
    job_id,
    reference_key,
    label,
    asset_id,
    object_path,
    created_by,
    updated_by,
    created_at,
    updated_at
  )
  SELECT
    latest.job_id,
    left(latest.reference_key, 120),
    left(latest.label, 160),
    left(latest.asset_id, 180),
    latest.object_path,
    latest.owner_user_id,
    latest.owner_user_id,
    latest.protocol_created_at,
    latest.protocol_created_at
  FROM latest_reference AS latest
  ON CONFLICT (job_id, reference_key)
  DO UPDATE SET
    label = EXCLUDED.label,
    asset_id = EXCLUDED.asset_id,
    object_path = EXCLUDED.object_path,
    updated_by = EXCLUDED.updated_by,
    updated_at = EXCLUDED.updated_at
  RETURNING id, job_id
)
UPDATE production_jobs AS job
SET active_reference_id = inserted.id
FROM inserted_reference AS inserted
WHERE job.id = inserted.job_id
  AND job.active_reference_id IS NULL;

COMMIT;
