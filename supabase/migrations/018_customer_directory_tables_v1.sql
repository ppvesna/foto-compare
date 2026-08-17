-- Inline organization tables and customer-bound invitations.
-- Prerequisites: migrations 010, 011, and 012.

BEGIN;

ALTER TABLE organization_invitations
ADD COLUMN IF NOT EXISTS customer_id UUID
REFERENCES organization_customers(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS organization_invitations_customer_idx
ON organization_invitations(customer_id, status, created_at);

CREATE OR REPLACE FUNCTION attach_organization_invitation_customer_v1(
  target_invitation UUID,
  target_customer UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_invitation organization_invitations%ROWTYPE;
  selected_customer organization_customers%ROWTYPE;
BEGIN
  SELECT * INTO selected_invitation
  FROM organization_invitations
  WHERE id = target_invitation;

  SELECT * INTO selected_customer
  FROM organization_customers
  WHERE id = target_customer;

  IF selected_invitation.id IS NULL OR selected_customer.id IS NULL THEN
    RAISE EXCEPTION 'Invitation or customer not found';
  END IF;
  IF selected_invitation.organization_id <> selected_customer.organization_id
    OR NOT selected_customer.active THEN
    RAISE EXCEPTION 'Customer does not belong to this invitation organization';
  END IF;
  IF selected_invitation.role <> 'customer'
    OR selected_invitation.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending customer invitation can be attached';
  END IF;
  IF NOT has_organization_role_v2(
    selected_invitation.organization_id,
    ARRAY['owner', 'admin']
  ) THEN
    RAISE EXCEPTION 'Customer administration access required';
  END IF;

  UPDATE organization_invitations
  SET customer_id = target_customer, updated_at = now()
  WHERE id = target_invitation;
END;
$$;

CREATE OR REPLACE FUNCTION link_accepted_customer_invitation_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'accepted'
    AND OLD.status IS DISTINCT FROM NEW.status
    AND NEW.role = 'customer'
    AND NEW.customer_id IS NOT NULL
    AND NEW.accepted_by IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM organization_customers AS customer
      WHERE customer.id = NEW.customer_id
        AND customer.organization_id = NEW.organization_id
    ) THEN
      RAISE EXCEPTION 'Invitation customer does not belong to the organization';
    END IF;

    INSERT INTO organization_customer_users(
      customer_id,
      user_id,
      linked_by
    )
    VALUES (
      NEW.customer_id,
      NEW.accepted_by,
      NEW.invited_by
    )
    ON CONFLICT (customer_id, user_id)
    DO UPDATE SET
      linked_by = EXCLUDED.linked_by,
      linked_at = now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS link_accepted_customer_invitation_v1
ON organization_invitations;

CREATE TRIGGER link_accepted_customer_invitation_v1
AFTER UPDATE OF status, accepted_by
ON organization_invitations
FOR EACH ROW
EXECUTE FUNCTION link_accepted_customer_invitation_v1();

CREATE OR REPLACE FUNCTION list_organization_customers_v2(
  target_organization UUID,
  include_archived BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(
  customer_id UUID,
  code TEXT,
  name TEXT,
  active BOOLEAN,
  primary_manager_user_id UUID,
  primary_manager_nickname TEXT,
  customer_user_id UUID,
  customer_user_nickname TEXT,
  created_by_user_id UUID,
  created_by_nickname TEXT,
  updated_by_user_id UUID,
  updated_by_nickname TEXT,
  pending_invitation_id UUID,
  pending_invitation_email TEXT,
  pending_invitation_nickname TEXT,
  pending_invitation_display_name TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT has_organization_role_v2(
    target_organization,
    ARRAY['owner', 'admin', 'employee']
  ) THEN
    RAISE EXCEPTION 'Customer directory access required';
  END IF;

  RETURN QUERY
  SELECT
    customer.id,
    customer.code,
    customer.name,
    customer.active,
    customer.primary_manager_user_id,
    COALESCE(manager_profile.nickname, '')::TEXT,
    customer_link.user_id,
    COALESCE(customer_profile.nickname, '')::TEXT,
    customer.created_by,
    COALESCE(creator_profile.nickname, '')::TEXT,
    customer.updated_by,
    COALESCE(updater_profile.nickname, '')::TEXT,
    pending_invitation.id,
    COALESCE(pending_invitation.email, '')::TEXT,
    COALESCE(pending_invitation.nickname, '')::TEXT,
    COALESCE(pending_invitation.display_name, '')::TEXT,
    customer.created_at,
    customer.updated_at
  FROM organization_customers AS customer
  LEFT JOIN user_profiles AS manager_profile
    ON manager_profile.user_id = customer.primary_manager_user_id
  LEFT JOIN LATERAL (
    SELECT link.user_id
    FROM organization_customer_users AS link
    WHERE link.customer_id = customer.id
    ORDER BY link.linked_at DESC
    LIMIT 1
  ) AS customer_link ON TRUE
  LEFT JOIN user_profiles AS customer_profile
    ON customer_profile.user_id = customer_link.user_id
  LEFT JOIN user_profiles AS creator_profile
    ON creator_profile.user_id = customer.created_by
  LEFT JOIN user_profiles AS updater_profile
    ON updater_profile.user_id = customer.updated_by
  LEFT JOIN LATERAL (
    SELECT invitation.id,
           invitation.email,
           invitation.nickname,
           invitation.display_name
    FROM organization_invitations AS invitation
    WHERE invitation.customer_id = customer.id
      AND invitation.status = 'pending'
      AND invitation.expires_at > now()
    ORDER BY invitation.created_at DESC
    LIMIT 1
  ) AS pending_invitation ON TRUE
  WHERE customer.organization_id = target_organization
    AND (include_archived OR customer.active)
  ORDER BY customer.active DESC, lower(customer.name), lower(customer.code);
END;
$$;

CREATE OR REPLACE FUNCTION list_customer_jobs_v1(
  target_customer UUID
)
RETURNS TABLE(
  job_id UUID,
  job_number TEXT,
  job_status TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_organization UUID;
BEGIN
  SELECT organization_id INTO target_organization
  FROM organization_customers
  WHERE id = target_customer;

  IF target_organization IS NULL THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;
  IF NOT has_organization_role_v2(
    target_organization,
    ARRAY['owner', 'admin', 'employee']
  ) AND NOT EXISTS (
    SELECT 1
    FROM organization_customer_users
    WHERE customer_id = target_customer
      AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Customer work access required';
  END IF;

  RETURN QUERY
  SELECT
    job.id,
    job.number,
    job.status,
    job.created_at,
    job.updated_at
  FROM production_jobs AS job
  WHERE job.customer_id = target_customer
  ORDER BY job.updated_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION update_organization_member_v1(
  target_organization UUID,
  target_user UUID,
  target_role TEXT,
  target_functions TEXT[] DEFAULT '{}'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor_role TEXT;
  current_role TEXT;
BEGIN
  SELECT role INTO actor_role
  FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = auth.uid();

  SELECT role INTO current_role
  FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = target_user;

  IF actor_role NOT IN ('owner', 'admin') OR current_role IS NULL THEN
    RAISE EXCEPTION 'Member administration access required';
  END IF;
  IF current_role = 'owner' THEN
    RAISE EXCEPTION 'The owner role cannot be changed here';
  END IF;
  IF actor_role = 'admin' AND current_role = 'admin' THEN
    RAISE EXCEPTION 'An administrator cannot change another administrator';
  END IF;
  IF target_role NOT IN ('admin', 'employee')
    OR (actor_role = 'admin' AND target_role = 'admin') THEN
    RAISE EXCEPTION 'Requested role is not allowed';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM unnest(target_functions) AS requested_function
    WHERE requested_function NOT IN (
      'manager',
      'designer',
      'inspectionSpecialist'
    )
  ) THEN
    RAISE EXCEPTION 'Unknown employee function';
  END IF;

  UPDATE organization_members
  SET role = target_role
  WHERE organization_id = target_organization
    AND user_id = target_user;

  DELETE FROM organization_member_functions
  WHERE organization_id = target_organization
    AND user_id = target_user;

  IF target_role = 'employee' THEN
    INSERT INTO organization_member_functions(
      organization_id,
      user_id,
      function_name
    )
    SELECT
      target_organization,
      target_user,
      requested_function
    FROM unnest(target_functions) AS requested_function
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION remove_organization_member_v1(
  target_organization UUID,
  target_user UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor_role TEXT;
  current_role TEXT;
BEGIN
  SELECT role INTO actor_role
  FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = auth.uid();

  SELECT role INTO current_role
  FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = target_user;

  IF actor_role NOT IN ('owner', 'admin') OR current_role IS NULL THEN
    RAISE EXCEPTION 'Member administration access required';
  END IF;
  IF current_role = 'owner' THEN
    RAISE EXCEPTION 'The owner cannot be removed';
  END IF;
  IF actor_role = 'admin' AND current_role = 'admin' THEN
    RAISE EXCEPTION 'An administrator cannot remove another administrator';
  END IF;

  DELETE FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = target_user;
END;
$$;

CREATE OR REPLACE FUNCTION restore_organization_customer_v1(
  target_customer UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_organization UUID;
BEGIN
  SELECT organization_id INTO target_organization
  FROM organization_customers
  WHERE id = target_customer;

  IF target_organization IS NULL OR NOT has_organization_role_v2(
    target_organization,
    ARRAY['owner', 'admin']
  ) THEN
    RAISE EXCEPTION 'Customer administration access required';
  END IF;

  UPDATE organization_customers
  SET
    active = TRUE,
    updated_by = auth.uid(),
    updated_at = now()
  WHERE id = target_customer;
END;
$$;

REVOKE ALL ON FUNCTION attach_organization_invitation_customer_v1(UUID, UUID)
FROM PUBLIC;
REVOKE ALL ON FUNCTION list_organization_customers_v2(UUID, BOOLEAN)
FROM PUBLIC;
REVOKE ALL ON FUNCTION list_customer_jobs_v1(UUID)
FROM PUBLIC;
REVOKE ALL ON FUNCTION update_organization_member_v1(UUID, UUID, TEXT, TEXT[])
FROM PUBLIC;
REVOKE ALL ON FUNCTION remove_organization_member_v1(UUID, UUID)
FROM PUBLIC;
REVOKE ALL ON FUNCTION restore_organization_customer_v1(UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION attach_organization_invitation_customer_v1(UUID, UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION list_organization_customers_v2(UUID, BOOLEAN)
TO authenticated;
GRANT EXECUTE ON FUNCTION list_customer_jobs_v1(UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION update_organization_member_v1(UUID, UUID, TEXT, TEXT[])
TO authenticated;
GRANT EXECUTE ON FUNCTION remove_organization_member_v1(UUID, UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION restore_organization_customer_v1(UUID)
TO authenticated;

COMMIT;
