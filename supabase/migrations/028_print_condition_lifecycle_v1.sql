-- Archive-first lifecycle for organization print conditions.
-- Specialists manage profiles; administrators audit archive events and may
-- permanently delete only profiles that have never been assigned to a job.
-- Prerequisites: migrations 016, 017, and 027.

BEGIN;

ALTER TABLE print_conditions
ADD COLUMN IF NOT EXISTS archived_from_status TEXT;

ALTER TABLE print_conditions
ADD COLUMN IF NOT EXISTS archived_from_customer_visible BOOLEAN;

ALTER TABLE print_conditions
ADD COLUMN IF NOT EXISTS used_in_jobs BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE print_conditions
DROP CONSTRAINT IF EXISTS print_condition_archived_from_status_check;

ALTER TABLE print_conditions
ADD CONSTRAINT print_condition_archived_from_status_check
CHECK (
  archived_from_status IS NULL
  OR archived_from_status IN ('draft', 'verified', 'published')
);

UPDATE print_conditions AS condition
SET used_in_jobs = TRUE
WHERE EXISTS (
  SELECT 1
  FROM production_job_print_conditions AS assignment
  WHERE assignment.condition_id = condition.id
);

CREATE OR REPLACE FUNCTION mark_print_condition_used_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE print_conditions
  SET used_in_jobs = TRUE
  WHERE id = NEW.condition_id
    AND NOT used_in_jobs;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS production_job_print_condition_used_v1
ON production_job_print_conditions;

CREATE TRIGGER production_job_print_condition_used_v1
AFTER INSERT ON production_job_print_conditions
FOR EACH ROW
EXECUTE FUNCTION mark_print_condition_used_v1();

CREATE OR REPLACE FUNCTION can_manage_print_conditions_v1(
  target_organization UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM organization_members AS member
    WHERE member.organization_id = target_organization
      AND member.user_id = auth.uid()
      AND member.role = 'employee'
      AND EXISTS (
        SELECT 1
        FROM organization_member_functions AS function
        WHERE function.organization_id = member.organization_id
          AND function.user_id = member.user_id
          AND function.function_name = 'inspectionSpecialist'
      )
  );
$$;

CREATE OR REPLACE FUNCTION can_administer_print_conditions_v1(
  target_organization UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT has_organization_role_v2(
    target_organization,
    ARRAY['admin']
  );
$$;

ALTER TABLE chat_groups
DROP CONSTRAINT IF EXISTS chat_groups_kind_check;

ALTER TABLE chat_groups
ADD CONSTRAINT chat_groups_kind_check
CHECK (kind IN ('organization', 'group', 'direct', 'job', 'service'));

CREATE OR REPLACE FUNCTION can_access_chat_group_v1(
  target_group UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM chat_groups AS chat
    WHERE chat.id = target_group
      AND NOT chat.is_deleted
      AND (
        (
          chat.job_id IS NOT NULL
          AND can_view_production_job_v1(chat.job_id)
        )
        OR (
          chat.job_id IS NULL
          AND chat.kind = 'organization'
          AND chat.organization_id IS NOT NULL
          AND has_organization_role_v2(
            chat.organization_id,
            ARRAY['owner', 'admin', 'employee']
          )
        )
        OR (
          chat.job_id IS NULL
          AND chat.kind = 'service'
          AND chat.organization_id IS NOT NULL
          AND has_organization_role_v2(
            chat.organization_id,
            ARRAY['admin']
          )
        )
        OR (
          chat.job_id IS NULL
          AND chat.kind NOT IN ('organization', 'service')
          AND (
            chat.created_by = auth.uid()
            OR EXISTS (
              SELECT 1
              FROM chat_group_members AS member
              WHERE member.group_id = chat.id
                AND member.user_id = auth.uid()
            )
          )
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION notify_print_condition_admins_v1(
  target_organization UUID,
  target_condition UUID,
  target_display_name TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  service_group_id UUID;
BEGIN
  INSERT INTO chat_groups(
    organization_id,
    name,
    kind,
    created_by,
    scope_key
  )
  VALUES (
    target_organization,
    'Служебные уведомления',
    'service',
    NULL,
    'organization:' || target_organization::TEXT || ':administrators'
  )
  ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
  DO UPDATE SET
    name = EXCLUDED.name,
    kind = EXCLUDED.kind,
    organization_id = EXCLUDED.organization_id,
    is_deleted = FALSE
  RETURNING id INTO service_group_id;

  INSERT INTO chat_messages(
    organization_id,
    group_id,
    sender_id,
    message_type,
    text,
    metadata
  )
  VALUES (
    target_organization,
    service_group_id,
    auth.uid(),
    'system',
    'Профиль «' || target_display_name || '» перемещён в архив специалистом.',
    jsonb_build_object(
      'event', 'print_condition_archived',
      'condition_id', target_condition,
      'display_name', target_display_name
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION archive_print_condition_v1(
  target_condition UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected print_conditions%ROWTYPE;
BEGIN
  SELECT * INTO selected
  FROM print_conditions
  WHERE id = target_condition
  FOR UPDATE;

  IF NOT FOUND OR NOT can_manage_print_conditions_v1(selected.organization_id) THEN
    RAISE EXCEPTION 'Print condition specialist access required';
  END IF;
  IF selected.status = 'archived' THEN
    RAISE EXCEPTION 'Print condition is already archived';
  END IF;

  UPDATE print_conditions
  SET
    archived_from_status = selected.status,
    archived_from_customer_visible = selected.customer_visible,
    status = 'archived',
    customer_visible = FALSE,
    updated_at = now()
  WHERE id = target_condition;

  PERFORM notify_print_condition_admins_v1(
    selected.organization_id,
    selected.id,
    selected.display_name
  );
END;
$$;

CREATE OR REPLACE FUNCTION restore_print_condition_v1(
  target_condition UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected print_conditions%ROWTYPE;
  restored_status TEXT;
BEGIN
  SELECT * INTO selected
  FROM print_conditions
  WHERE id = target_condition
  FOR UPDATE;

  IF NOT FOUND OR NOT can_manage_print_conditions_v1(selected.organization_id) THEN
    RAISE EXCEPTION 'Print condition specialist access required';
  END IF;
  IF selected.status <> 'archived' THEN
    RAISE EXCEPTION 'Only an archived print condition can be restored';
  END IF;

  restored_status := COALESCE(selected.archived_from_status, 'draft');
  UPDATE print_conditions
  SET
    status = restored_status,
    customer_visible = restored_status = 'published'
      AND COALESCE(selected.archived_from_customer_visible, FALSE),
    archived_from_status = NULL,
    archived_from_customer_visible = NULL,
    updated_at = now()
  WHERE id = target_condition;
END;
$$;

CREATE OR REPLACE FUNCTION delete_print_condition_permanently_v1(
  target_condition UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected print_conditions%ROWTYPE;
BEGIN
  SELECT * INTO selected
  FROM print_conditions
  WHERE id = target_condition
  FOR UPDATE;

  IF NOT FOUND
    OR NOT can_administer_print_conditions_v1(selected.organization_id) THEN
    RAISE EXCEPTION 'Print condition administrator access required';
  END IF;
  IF selected.status <> 'archived' THEN
    RAISE EXCEPTION 'Only an archived print condition can be permanently deleted';
  END IF;
  IF selected.used_in_jobs OR EXISTS (
    SELECT 1
    FROM production_job_print_conditions AS assignment
    WHERE assignment.condition_id = target_condition
  ) THEN
    RAISE EXCEPTION 'A used print condition must remain in history';
  END IF;

  DELETE FROM print_conditions
  WHERE id = target_condition;
END;
$$;

CREATE OR REPLACE FUNCTION prepare_print_condition_permanent_delete_v1(
  target_condition UUID
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected print_conditions%ROWTYPE;
BEGIN
  SELECT * INTO selected
  FROM print_conditions
  WHERE id = target_condition;

  IF NOT FOUND
    OR NOT can_administer_print_conditions_v1(selected.organization_id) THEN
    RAISE EXCEPTION 'Print condition administrator access required';
  END IF;
  IF selected.status <> 'archived' THEN
    RAISE EXCEPTION 'Only an archived print condition can be permanently deleted';
  END IF;
  IF selected.used_in_jobs OR EXISTS (
    SELECT 1
    FROM production_job_print_conditions AS assignment
    WHERE assignment.condition_id = target_condition
  ) THEN
    RAISE EXCEPTION 'A used print condition must remain in history';
  END IF;

  RETURN selected.icc_storage_path;
END;
$$;

DROP POLICY IF EXISTS trimatrix_print_profile_objects_delete_v1 ON storage.objects;
CREATE POLICY trimatrix_print_profile_objects_delete_v1
ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'print-profiles'
  AND (
    can_manage_print_conditions_v1((storage.foldername(name))[2]::UUID)
    OR can_administer_print_conditions_v1((storage.foldername(name))[2]::UUID)
  )
);

REVOKE ALL ON FUNCTION mark_print_condition_used_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION notify_print_condition_admins_v1(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION notify_print_condition_admins_v1(UUID, UUID, TEXT) FROM authenticated;
REVOKE ALL ON FUNCTION can_administer_print_conditions_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION archive_print_condition_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION restore_print_condition_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION prepare_print_condition_permanent_delete_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION delete_print_condition_permanently_v1(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION can_administer_print_conditions_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION archive_print_condition_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION restore_print_condition_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION prepare_print_condition_permanent_delete_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_print_condition_permanently_v1(UUID) TO authenticated;

COMMIT;
