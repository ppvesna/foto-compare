-- Let an organization owner create the first work and act as its responsible
-- participant before an administrator or employee has been invited.

BEGIN;

CREATE OR REPLACE FUNCTION open_production_job_v2(
  target_organization UUID,
  target_number TEXT,
  target_customer UUID DEFAULT NULL,
  target_requested_customer_name TEXT DEFAULT NULL,
  target_responsible_user UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSONB;
  selected_job UUID;
  selected_responsible UUID := COALESCE(target_responsible_user, auth.uid());
BEGIN
  IF NOT can_create_production_job_v1(target_organization) THEN
    RAISE EXCEPTION 'Only an owner, administrator or manager can create a work';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM organization_members AS member
    WHERE member.organization_id = target_organization
      AND member.user_id = selected_responsible
      AND member.role IN ('owner', 'admin', 'employee')
  ) THEN
    RAISE EXCEPTION 'Responsible organization member is not available';
  END IF;

  result := open_production_job_v1(
    target_organization,
    target_number,
    target_customer,
    target_requested_customer_name
  );
  selected_job := (result->>'job_id')::UUID;

  INSERT INTO production_job_participants(
    job_id, user_id, participant_type, added_by
  )
  VALUES (selected_job, selected_responsible, 'operator', auth.uid())
  ON CONFLICT DO NOTHING;

  UPDATE production_job_batches
  SET employee_user_id = selected_responsible
  WHERE job_id = selected_job
    AND sequence_no = 1
    AND NOT EXISTS (
      SELECT 1
      FROM production_units AS unit
      WHERE unit.batch_id = production_job_batches.id
    );

  RETURN result || jsonb_build_object(
    'responsible_user_id', selected_responsible
  );
END;
$$;

CREATE OR REPLACE FUNCTION list_organization_production_workers_v1(
  target_organization UUID
)
RETURNS TABLE(user_id UUID, display_name TEXT, nickname TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT has_organization_role_v2(
    target_organization, ARRAY['owner', 'admin', 'employee']
  ) THEN
    RAISE EXCEPTION 'Production access required';
  END IF;

  RETURN QUERY
  SELECT
    member.user_id,
    COALESCE(profile.display_name, '')::TEXT,
    COALESCE(profile.nickname, '')::TEXT
  FROM organization_members AS member
  LEFT JOIN user_profiles AS profile ON profile.user_id = member.user_id
  WHERE member.organization_id = target_organization
    AND member.role IN ('owner', 'admin', 'employee')
  ORDER BY lower(
    COALESCE(NULLIF(profile.display_name, ''), profile.nickname, '')
  );
END;
$$;

REVOKE ALL ON FUNCTION open_production_job_v2(
  UUID, TEXT, UUID, TEXT, UUID
) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_organization_production_workers_v1(UUID)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION open_production_job_v2(
  UUID, TEXT, UUID, TEXT, UUID
) TO authenticated;
GRANT EXECUTE ON FUNCTION list_organization_production_workers_v1(UUID)
  TO authenticated;

COMMIT;
