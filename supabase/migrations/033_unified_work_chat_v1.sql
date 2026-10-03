-- One work conversation in the client with protected internal/customer audiences.
-- Customer connection is administrator-only; employees who actually worked on
-- or inspected a job retain access to its internal conversation.
-- Prerequisites: migrations 017, 031, and 032.

BEGIN;

CREATE OR REPLACE FUNCTION can_manage_production_job_customer_access_v1(
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
      AND has_organization_role_v2(job.organization_id, ARRAY['admin'])
  );
$$;

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
          AND (
            EXISTS (
              SELECT 1
              FROM production_job_participants AS participant
              WHERE participant.job_id = job.id
                AND participant.user_id = auth.uid()
                AND participant.participant_type IN ('operator', 'manager')
            )
            OR EXISTS (
              SELECT 1
              FROM production_job_batches AS batch
              WHERE batch.job_id = job.id
                AND auth.uid() IN (batch.employee_user_id, batch.created_by)
            )
            OR EXISTS (
              SELECT 1
              FROM production_units AS unit
              JOIN production_job_batches AS batch ON batch.id = unit.batch_id
              WHERE batch.job_id = job.id
                AND unit.created_by = auth.uid()
            )
            OR EXISTS (
              SELECT 1
              FROM production_inspections AS inspection
              JOIN production_units AS unit ON unit.id = inspection.unit_id
              JOIN production_job_batches AS batch ON batch.id = unit.batch_id
              WHERE batch.job_id = job.id
                AND auth.uid() IN (
                  inspection.started_by,
                  inspection.decided_by
                )
            )
            OR EXISTS (
              SELECT 1
              FROM production_inspection_attempts AS attempt
              JOIN production_inspections AS inspection
                ON inspection.id = attempt.inspection_id
              JOIN production_units AS unit ON unit.id = inspection.unit_id
              JOIN production_job_batches AS batch ON batch.id = unit.batch_id
              WHERE batch.job_id = job.id
                AND attempt.attempted_by = auth.uid()
            )
            OR EXISTS (
              SELECT 1
              FROM production_job_blocks AS block
              WHERE block.job_id = job.id
                AND auth.uid() IN (block.created_by, block.resolved_by)
            )
          )
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION can_manage_production_job_customer_access_v1(UUID)
FROM PUBLIC;
REVOKE ALL ON FUNCTION is_internal_production_user_v1(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION can_manage_production_job_customer_access_v1(UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION is_internal_production_user_v1(UUID)
TO authenticated;

COMMIT;
