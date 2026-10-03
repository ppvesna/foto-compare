-- Work hub, organization service conversation, contextual chat metadata,
-- and immutable batch-oriented continuation helpers.
-- Prerequisites: migrations 020, 028, 031, 032, and 033.

BEGIN;

CREATE OR REPLACE FUNCTION current_organization_access_v2()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_membership organization_members%ROWTYPE;
  selected_name TEXT;
  selected_functions TEXT[];
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT membership.* INTO selected_membership
  FROM organization_members AS membership
  WHERE membership.user_id = auth.uid()
  ORDER BY
    CASE membership.role
      WHEN 'owner' THEN 1 WHEN 'admin' THEN 2 WHEN 'employee' THEN 3
      WHEN 'customer' THEN 4 ELSE 5
    END,
    membership.created_at
  LIMIT 1;

  IF selected_membership.organization_id IS NULL THEN RETURN NULL; END IF;

  SELECT name INTO selected_name
  FROM organizations WHERE id = selected_membership.organization_id;

  SELECT COALESCE(array_agg(function_name ORDER BY function_name), '{}'::TEXT[])
  INTO selected_functions
  FROM organization_member_functions
  WHERE organization_id = selected_membership.organization_id
    AND user_id = auth.uid();

  RETURN jsonb_build_object(
    'organization_id', selected_membership.organization_id,
    'organization_name', selected_name,
    'organization_role', selected_membership.role,
    'employee_functions', COALESCE(selected_functions, '{}'::TEXT[])
  );
END;
$$;

CREATE OR REPLACE FUNCTION can_access_chat_group_v1(target_group UUID)
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
        (chat.kind = 'job_internal' AND chat.job_id IS NOT NULL
          AND is_internal_production_user_v1(chat.job_id))
        OR (chat.kind = 'job' AND chat.job_id IS NOT NULL
          AND can_view_production_job_v1(chat.job_id))
        OR (
          chat.job_id IS NULL
          AND chat.kind IN ('organization', 'service')
          AND chat.organization_id IS NOT NULL
          AND has_organization_role_v2(
            chat.organization_id, ARRAY['owner', 'admin', 'employee']
          )
        )
        OR (
          chat.job_id IS NULL
          AND chat.kind NOT IN ('organization', 'service')
          AND (
            chat.created_by = auth.uid()
            OR EXISTS (
              SELECT 1 FROM chat_group_members AS member
              WHERE member.group_id = chat.id AND member.user_id = auth.uid()
            )
          )
        )
      )
  );
$$;

INSERT INTO chat_groups(
  organization_id, name, kind, created_by, scope_key
)
SELECT organization.id, 'Служебные', 'service', NULL,
  'organization:' || organization.id::TEXT || ':service'
FROM organizations AS organization
WHERE NOT EXISTS (
  SELECT 1 FROM chat_groups AS existing
  WHERE existing.organization_id = organization.id
    AND existing.kind = 'service'
    AND NOT existing.is_deleted
)
ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
DO UPDATE SET name = EXCLUDED.name, kind = 'service', is_deleted = FALSE;

WITH canonical AS (
  SELECT organization_id, id
  FROM chat_groups
  WHERE kind = 'service'
    AND scope_key = 'organization:' || organization_id::TEXT || ':service'
)
UPDATE chat_messages AS message
SET group_id = canonical.id, organization_id = canonical.organization_id
FROM chat_groups AS old_group
JOIN canonical ON canonical.organization_id = old_group.organization_id
WHERE message.group_id = old_group.id
  AND old_group.kind = 'service'
  AND old_group.id <> canonical.id;

UPDATE chat_groups
SET is_deleted = TRUE, updated_at = now()
WHERE kind = 'service'
  AND organization_id IS NOT NULL
  AND scope_key IS DISTINCT FROM
    'organization:' || organization_id::TEXT || ':service';

DROP POLICY IF EXISTS chat_messages_insert_v1 ON chat_messages;
CREATE POLICY chat_messages_insert_v1
ON chat_messages
FOR INSERT
TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND can_access_chat_group_v1(group_id)
  AND EXISTS (
    SELECT 1 FROM chat_groups AS chat
    WHERE chat.id = group_id
      AND chat.organization_id IS NOT DISTINCT FROM organization_id
      AND (chat.kind <> 'group' OR chat.archived_at IS NULL)
  )
);

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
    organization_id, name, kind, created_by, scope_key
  ) VALUES (
    target_organization, 'Служебные', 'service', NULL,
    'organization:' || target_organization::TEXT || ':service'
  )
  ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
  DO UPDATE SET name = EXCLUDED.name, kind = 'service', is_deleted = FALSE
  RETURNING id INTO service_group_id;

  INSERT INTO chat_messages(
    organization_id, group_id, sender_id, message_type, text, metadata
  ) VALUES (
    target_organization, service_group_id, auth.uid(), 'system',
    'Профиль «' || target_display_name || '» перемещён в архив специалистом.',
    jsonb_build_object(
      'event', 'print_condition_archived',
      'condition_id', target_condition,
      'display_name', target_display_name
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION list_accessible_chat_threads_v3()
RETURNS TABLE(
  thread_id UUID, thread_name TEXT, thread_kind TEXT,
  organization_id UUID, job_id UUID, updated_at TIMESTAMPTZ,
  customer_shared BOOLEAN, can_manage_customer_access BOOLEAN,
  job_status TEXT, job_stage TEXT, job_flow_state TEXT,
  customer_name TEXT, unread_count BIGINT, archived_at TIMESTAMPTZ,
  can_manage BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  INSERT INTO chat_thread_reads(group_id, user_id, last_read_at)
  SELECT chat.id, auth.uid(), now()
  FROM chat_groups AS chat
  WHERE can_access_chat_group_v1(chat.id) AND NOT chat.is_deleted
  ON CONFLICT (group_id, user_id) DO NOTHING;

  RETURN QUERY
  SELECT
    chat.id,
    CASE
      WHEN chat.kind = 'direct' AND chat.organization_id IS NOT NULL
        THEN COALESCE(NULLIF(other_profile.display_name, ''),
          NULLIF(other_profile.nickname, ''), 'Личный диалог')
      ELSE chat.name
    END::TEXT,
    chat.kind, chat.organization_id, chat.job_id, chat.updated_at,
    COALESCE(job.customer_access_status = 'shared', FALSE),
    CASE WHEN chat.job_id IS NULL THEN FALSE
      ELSE can_manage_production_job_customer_access_v1(chat.job_id) END,
    COALESCE(job.status, ''),
    COALESCE(job.stage_code, ''),
    COALESCE(job.flow_state, ''),
    COALESCE(customer.name, job.requested_customer_name, ''),
    COUNT(message.id) FILTER (WHERE message.sender_id IS DISTINCT FROM auth.uid()),
    chat.archived_at,
    (chat.kind = 'group' AND can_manage_chat_teams_v1(chat.organization_id))
  FROM chat_groups AS chat
  LEFT JOIN production_jobs AS job ON job.id = chat.job_id
  LEFT JOIN organization_customers AS customer ON customer.id = job.customer_id
  LEFT JOIN chat_thread_reads AS read_state
    ON read_state.group_id = chat.id AND read_state.user_id = auth.uid()
  LEFT JOIN chat_messages AS message
    ON message.group_id = chat.id AND NOT message.is_deleted
   AND message.created_at > COALESCE(read_state.last_read_at, '-infinity'::TIMESTAMPTZ)
  LEFT JOIN LATERAL (
    SELECT profile.display_name, profile.nickname
    FROM chat_group_members AS direct_member
    LEFT JOIN user_profiles AS profile ON profile.user_id = direct_member.user_id
    WHERE direct_member.group_id = chat.id AND direct_member.user_id <> auth.uid()
    ORDER BY direct_member.joined_at LIMIT 1
  ) AS other_profile ON chat.kind = 'direct' AND chat.organization_id IS NOT NULL
  WHERE can_access_chat_group_v1(chat.id) AND NOT chat.is_deleted
  GROUP BY chat.id, job.customer_access_status, job.status, job.stage_code,
    job.flow_state, job.requested_customer_name, customer.name,
    other_profile.display_name, other_profile.nickname
  ORDER BY chat.updated_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION can_create_production_job_v1(target_organization UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT has_organization_role_v2(target_organization, ARRAY['admin'])
    OR (
      has_organization_role_v2(target_organization, ARRAY['employee'])
      AND EXISTS (
        SELECT 1 FROM organization_member_functions AS member_function
        WHERE member_function.organization_id = target_organization
          AND member_function.user_id = auth.uid()
          AND member_function.function_name = 'manager'
      )
    );
$$;

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
    RAISE EXCEPTION 'Only an administrator or manager can create a work';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM organization_members AS member
    WHERE member.organization_id = target_organization
      AND member.user_id = selected_responsible
      AND member.role IN ('admin', 'employee')
  ) THEN
    RAISE EXCEPTION 'Responsible employee is not available';
  END IF;

  result := open_production_job_v1(
    target_organization, target_number, target_customer,
    target_requested_customer_name
  );
  selected_job := (result->>'job_id')::UUID;

  INSERT INTO production_job_participants(job_id, user_id, participant_type, added_by)
  VALUES (selected_job, selected_responsible, 'operator', auth.uid())
  ON CONFLICT DO NOTHING;

  UPDATE production_job_batches
  SET employee_user_id = selected_responsible
  WHERE job_id = selected_job AND sequence_no = 1
    AND NOT EXISTS (
      SELECT 1 FROM production_units AS unit
      WHERE unit.batch_id = production_job_batches.id
    );

  RETURN result || jsonb_build_object('responsible_user_id', selected_responsible);
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
    target_organization, ARRAY['admin', 'employee']
  ) THEN RAISE EXCEPTION 'Production access required'; END IF;
  RETURN QUERY
  SELECT member.user_id, COALESCE(profile.display_name, '')::TEXT,
    COALESCE(profile.nickname, '')::TEXT
  FROM organization_members AS member
  LEFT JOIN user_profiles AS profile ON profile.user_id = member.user_id
  WHERE member.organization_id = target_organization
    AND member.role IN ('admin', 'employee')
  ORDER BY lower(COALESCE(NULLIF(profile.display_name, ''), profile.nickname, ''));
END;
$$;

CREATE OR REPLACE FUNCTION get_production_work_v3(target_job UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSONB;
  enriched_batches JSONB;
BEGIN
  result := get_production_work_v2(target_job);
  IF jsonb_typeof(result->'batches') <> 'array' THEN RETURN result; END IF;

  SELECT COALESCE(jsonb_agg(
    batch_json || jsonb_build_object(
      'employee_user_id', batch.employee_user_id
    ) ORDER BY (batch_json->>'sequence_no')::INTEGER DESC
  ), '[]'::JSONB)
  INTO enriched_batches
  FROM jsonb_array_elements(result->'batches') AS element(batch_json)
  LEFT JOIN production_job_batches AS batch
    ON batch.id = (batch_json->>'id')::UUID;

  RETURN jsonb_set(result, '{batches}', enriched_batches, TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION create_production_unit_v1(
  target_batch UUID,
  target_unit_type TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_batch production_job_batches%ROWTYPE;
  selected_job production_jobs%ROWTYPE;
  next_no INTEGER;
  new_id UUID;
  caller_is_admin BOOLEAN;
BEGIN
  SELECT * INTO selected_batch
  FROM production_job_batches WHERE id = target_batch FOR UPDATE;
  SELECT * INTO selected_job
  FROM production_jobs WHERE id = selected_batch.job_id;
  IF selected_job.id IS NULL OR NOT is_internal_production_user_v1(selected_job.id) THEN
    RAISE EXCEPTION 'Internal production access required';
  END IF;
  caller_is_admin := has_organization_role_v2(
    selected_job.organization_id, ARRAY['admin']
  );
  IF NOT caller_is_admin
     AND selected_batch.employee_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Employee changed: create a new batch before continuing';
  END IF;
  IF selected_batch.completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Only the current batch can receive a physical unit';
  END IF;
  IF target_unit_type NOT IN ('stack', 'roll') THEN
    RAISE EXCEPTION 'Unknown physical unit type';
  END IF;
  IF selected_job.status <> 'active' THEN
    RAISE EXCEPTION 'Work is not active';
  END IF;

  SELECT COALESCE(MAX(sequence_no), 0) + 1 INTO next_no
  FROM production_units WHERE batch_id = target_batch;
  INSERT INTO production_units(
    batch_id, sequence_no, unit_type, created_by
  ) VALUES (target_batch, next_no, target_unit_type, auth.uid())
  RETURNING id INTO new_id;
  UPDATE production_jobs SET updated_by = auth.uid(), updated_at = now()
  WHERE id = selected_job.id;
  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION save_organization_customer_v2(
  target_organization UUID, target_code TEXT, target_name TEXT,
  target_manager_user UUID DEFAULT NULL, target_customer_user UUID DEFAULT NULL,
  target_customer UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  clean_code TEXT := trim(COALESCE(target_code, ''));
  clean_name TEXT := trim(COALESCE(target_name, ''));
  selected_customer UUID;
  can_create BOOLEAN := can_create_production_job_v1(target_organization);
BEGIN
  IF target_customer IS NULL AND NOT can_create THEN
    RAISE EXCEPTION 'Customer creation requires administrator or manager access';
  END IF;
  IF target_customer IS NOT NULL AND NOT has_organization_role_v2(
    target_organization, ARRAY['owner', 'admin']
  ) THEN RAISE EXCEPTION 'Customer administration access required'; END IF;
  IF length(clean_name) NOT BETWEEN 2 AND 160 THEN
    RAISE EXCEPTION 'Customer name must contain 2-160 characters';
  END IF;
  IF target_manager_user IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE organization_id = target_organization
      AND user_id = target_manager_user AND role IN ('admin', 'employee')
  ) THEN RAISE EXCEPTION 'Selected employee is not an organization member'; END IF;

  IF target_customer IS NULL AND clean_code = '' THEN
    UPDATE organizations SET next_customer_number = next_customer_number + 1
    WHERE id = target_organization
    RETURNING 'C-' || lpad((next_customer_number - 1)::TEXT, 4, '0') INTO clean_code;
  ELSIF target_customer IS NOT NULL AND clean_code = '' THEN
    SELECT code INTO clean_code FROM organization_customers
    WHERE id = target_customer AND organization_id = target_organization;
  END IF;

  IF target_customer IS NULL THEN
    INSERT INTO organization_customers(
      organization_id, code, code_key, name, primary_manager_user_id,
      created_by, updated_by
    ) VALUES (
      target_organization, clean_code, lower(clean_code), clean_name,
      target_manager_user, auth.uid(), auth.uid()
    ) RETURNING id INTO selected_customer;
  ELSE
    UPDATE organization_customers SET code = clean_code, code_key = lower(clean_code),
      name = clean_name, primary_manager_user_id = target_manager_user,
      active = TRUE, updated_by = auth.uid(), updated_at = now()
    WHERE id = target_customer AND organization_id = target_organization
    RETURNING id INTO selected_customer;
  END IF;
  IF selected_customer IS NULL THEN RAISE EXCEPTION 'Customer not found'; END IF;

  DELETE FROM organization_customer_users WHERE customer_id = selected_customer;
  IF target_customer_user IS NOT NULL THEN
    INSERT INTO organization_customer_users(customer_id, user_id, linked_by)
    VALUES (selected_customer, target_customer_user, auth.uid())
    ON CONFLICT (customer_id, user_id)
    DO UPDATE SET linked_by = auth.uid(), linked_at = now();
  END IF;
  RETURN selected_customer;
END;
$$;

CREATE OR REPLACE FUNCTION list_production_inspection_history_v1(
  target_organization UUID,
  search_text TEXT DEFAULT '',
  result_limit INTEGER DEFAULT 100
)
RETURNS TABLE(
  attempt_id UUID, job_id UUID, job_number TEXT, customer_name TEXT,
  batch_no INTEGER, unit_no INTEGER, unit_type TEXT,
  inspection_no INTEGER, attempt_no INTEGER,
  protocol_owner_user_id UUID, protocol_id TEXT, score NUMERIC,
  attempted_by_user_id UUID, attempted_by_name TEXT, attempted_at TIMESTAMPTZ,
  decision_status TEXT, decision_note TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  clean_search TEXT := lower(trim(COALESCE(search_text, '')));
  safe_limit INTEGER := LEAST(GREATEST(COALESCE(result_limit, 100), 1), 300);
BEGIN
  IF NOT has_organization_role_v2(
    target_organization, ARRAY['owner', 'admin', 'employee']
  ) THEN RAISE EXCEPTION 'Inspection history access required'; END IF;

  RETURN QUERY
  SELECT attempt.id, job.id, job.number,
    COALESCE(customer.name, job.requested_customer_name, '')::TEXT,
    batch.sequence_no, unit.sequence_no, unit.unit_type,
    inspection.sequence_no, attempt.sequence_no,
    attempt.protocol_owner_user_id, attempt.protocol_id, attempt.score,
    attempt.attempted_by,
    COALESCE(NULLIF(profile.display_name, ''), NULLIF(profile.nickname, ''), 'Сотрудник')::TEXT,
    attempt.attempted_at, inspection.status, inspection.decision_note
  FROM production_inspection_attempts AS attempt
  JOIN production_inspections AS inspection ON inspection.id = attempt.inspection_id
  JOIN production_units AS unit ON unit.id = inspection.unit_id
  JOIN production_job_batches AS batch ON batch.id = unit.batch_id
  JOIN production_jobs AS job ON job.id = batch.job_id
  LEFT JOIN organization_customers AS customer ON customer.id = job.customer_id
  LEFT JOIN user_profiles AS profile ON profile.user_id = attempt.attempted_by
  WHERE job.organization_id = target_organization
    AND can_view_production_job_v1(job.id)
    AND (
      clean_search = '' OR lower(job.number) LIKE '%' || clean_search || '%'
      OR lower(COALESCE(customer.name, job.requested_customer_name, ''))
        LIKE '%' || clean_search || '%'
      OR lower(COALESCE(profile.display_name, profile.nickname, ''))
        LIKE '%' || clean_search || '%'
    )
  ORDER BY attempt.attempted_at DESC
  LIMIT safe_limit;
END;
$$;

DROP POLICY IF EXISTS trimatrix_org_chat_assets_select_v1 ON storage.objects;
CREATE POLICY trimatrix_org_chat_assets_select_v1 ON storage.objects
FOR SELECT TO authenticated USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'chats'
  AND can_access_chat_group_v1((storage.foldername(name))[4]::UUID)
);

DROP POLICY IF EXISTS trimatrix_org_chat_assets_insert_v1 ON storage.objects;
CREATE POLICY trimatrix_org_chat_assets_insert_v1 ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'chats'
  AND can_access_chat_group_v1((storage.foldername(name))[4]::UUID)
);

DROP POLICY IF EXISTS trimatrix_org_chat_assets_update_v1 ON storage.objects;
CREATE POLICY trimatrix_org_chat_assets_update_v1 ON storage.objects
FOR UPDATE TO authenticated USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'chats'
  AND can_access_chat_group_v1((storage.foldername(name))[4]::UUID)
) WITH CHECK (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'chats'
  AND can_access_chat_group_v1((storage.foldername(name))[4]::UUID)
);

DROP POLICY IF EXISTS trimatrix_org_chat_assets_delete_v1 ON storage.objects;
CREATE POLICY trimatrix_org_chat_assets_delete_v1 ON storage.objects
FOR DELETE TO authenticated USING (
  bucket_id = 'trimatrix-assets'
  AND (storage.foldername(name))[1] = 'organizations'
  AND (storage.foldername(name))[3] = 'chats'
  AND can_access_chat_group_v1((storage.foldername(name))[4]::UUID)
);

REVOKE ALL ON FUNCTION list_accessible_chat_threads_v3() FROM PUBLIC;
REVOKE ALL ON FUNCTION can_create_production_job_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION open_production_job_v2(UUID, TEXT, UUID, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_organization_production_workers_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_production_work_v3(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION save_organization_customer_v2(UUID, TEXT, TEXT, UUID, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_production_inspection_history_v1(UUID, TEXT, INTEGER) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION list_accessible_chat_threads_v3() TO authenticated;
GRANT EXECUTE ON FUNCTION can_create_production_job_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION open_production_job_v2(UUID, TEXT, UUID, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION list_organization_production_workers_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_production_work_v3(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION save_organization_customer_v2(UUID, TEXT, TEXT, UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION list_production_inspection_history_v1(UUID, TEXT, INTEGER) TO authenticated;

COMMIT;
