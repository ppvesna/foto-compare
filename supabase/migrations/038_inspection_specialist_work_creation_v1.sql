-- Keep the application focused on sample inspection: a new work is entered by
-- an employee who has the inspection-specialist function. Owners and
-- administrators supervise the organization but do not enter inspection data.

BEGIN;

CREATE OR REPLACE FUNCTION can_create_production_job_v1(
  target_organization UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT has_organization_role_v2(target_organization, ARRAY['employee'])
    AND EXISTS (
      SELECT 1
      FROM organization_member_functions AS member_function
      WHERE member_function.organization_id = target_organization
        AND member_function.user_id = auth.uid()
        AND member_function.function_name = 'inspectionSpecialist'
    );
$$;

REVOKE ALL ON FUNCTION can_create_production_job_v1(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION can_create_production_job_v1(UUID) TO authenticated;

COMMIT;
