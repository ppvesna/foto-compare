-- Let an assigned inspection specialist archive the evidence of a check.
-- External customers keep read-only access to deliberately shared job assets.

BEGIN;

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
        OR (
          has_organization_role_v2(
            job.organization_id,
            ARRAY['employee']
          )
          AND can_view_production_job_v1(job.id)
          AND EXISTS (
            SELECT 1
            FROM organization_member_functions AS member_function
            WHERE member_function.organization_id = job.organization_id
              AND member_function.user_id = auth.uid()
              AND member_function.function_name = 'inspectionSpecialist'
          )
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION can_write_production_job_asset_v1(TEXT, TEXT)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION can_write_production_job_asset_v1(TEXT, TEXT)
TO authenticated;

COMMIT;
