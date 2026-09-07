-- Return every representative of a customer and preserve existing links when
-- customer details are edited. A customer remains one directory entity while
-- the UI may display one row per representative.

BEGIN;

CREATE OR REPLACE FUNCTION list_organization_customers_v3(
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
  representatives JSONB,
  created_by_user_id UUID,
  created_by_nickname TEXT,
  updated_by_user_id UUID,
  updated_by_nickname TEXT,
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
    COALESCE(representative_list.items, '[]'::JSONB),
    customer.created_by,
    COALESCE(creator_profile.nickname, '')::TEXT,
    customer.updated_by,
    COALESCE(updater_profile.nickname, '')::TEXT,
    customer.created_at,
    customer.updated_at
  FROM organization_customers AS customer
  LEFT JOIN user_profiles AS manager_profile
    ON manager_profile.user_id = customer.primary_manager_user_id
  LEFT JOIN user_profiles AS creator_profile
    ON creator_profile.user_id = customer.created_by
  LEFT JOIN user_profiles AS updater_profile
    ON updater_profile.user_id = customer.updated_by
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(
      representative.item
      ORDER BY representative.pending, representative.sort_name
    ) AS items
    FROM (
      SELECT
        FALSE AS pending,
        lower(COALESCE(profile.nickname, profile.email, '')) AS sort_name,
        jsonb_build_object(
          'user_id', link.user_id,
          'invitation_id', NULL,
          'email', COALESCE(profile.email, ''),
          'nickname', COALESCE(profile.nickname, ''),
          'display_name', COALESCE(profile.display_name, ''),
          'status', 'active',
          'email_sent', TRUE
        ) AS item
      FROM organization_customer_users AS link
      LEFT JOIN user_profiles AS profile ON profile.user_id = link.user_id
      WHERE link.customer_id = customer.id

      UNION ALL

      SELECT
        TRUE AS pending,
        lower(invitation.nickname) AS sort_name,
        jsonb_build_object(
          'user_id', NULL,
          'invitation_id', invitation.id,
          'email', invitation.email,
          'nickname', invitation.nickname,
          'display_name', invitation.display_name,
          'status', 'pending',
          'email_sent', invitation.delivery_status = 'sent'
        ) AS item
      FROM organization_invitations AS invitation
      WHERE invitation.customer_id = customer.id
        AND invitation.role = 'customer'
        AND invitation.status = 'pending'
        AND invitation.expires_at > now()
    ) AS representative
  ) AS representative_list ON TRUE
  WHERE customer.organization_id = target_organization
    AND (include_archived OR customer.active)
  ORDER BY customer.active DESC, lower(customer.name), lower(customer.code);
END;
$$;

-- Earlier versions replaced all customer-user links on every edit. Keep all
-- representatives and add a selected user without removing the others.
CREATE OR REPLACE FUNCTION save_organization_customer_v1(
  target_organization UUID,
  target_code TEXT,
  target_name TEXT,
  target_manager_user UUID DEFAULT NULL,
  target_customer_user UUID DEFAULT NULL,
  target_customer UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor_role TEXT;
  clean_code TEXT := trim(COALESCE(target_code, ''));
  clean_name TEXT := trim(COALESCE(target_name, ''));
  selected_customer UUID;
BEGIN
  SELECT role INTO actor_role
  FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = auth.uid();

  IF actor_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'Customer administration access required';
  END IF;
  IF length(clean_name) NOT BETWEEN 2 AND 160 THEN
    RAISE EXCEPTION 'Customer name must contain 2-160 characters';
  END IF;

  IF target_manager_user IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE organization_id = target_organization
      AND user_id = target_manager_user
      AND role IN ('owner', 'admin', 'employee')
  ) THEN
    RAISE EXCEPTION 'Selected employee is not an organization member';
  END IF;

  IF target_customer_user IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM organization_members
    WHERE organization_id = target_organization
      AND user_id = target_customer_user
      AND role = 'customer'
  ) THEN
    RAISE EXCEPTION 'Selected customer user does not have the customer role';
  END IF;

  IF target_customer IS NULL AND clean_code = '' THEN
    UPDATE organizations
    SET next_customer_number = next_customer_number + 1
    WHERE id = target_organization
    RETURNING 'C-' || lpad((next_customer_number - 1)::TEXT, 4, '0')
    INTO clean_code;
  ELSIF target_customer IS NOT NULL AND clean_code = '' THEN
    SELECT code INTO clean_code
    FROM organization_customers
    WHERE id = target_customer
      AND organization_id = target_organization;
  END IF;

  IF length(clean_code) NOT BETWEEN 1 AND 32 THEN
    RAISE EXCEPTION 'Customer code could not be generated';
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
    UPDATE organization_customers
    SET code = clean_code,
        code_key = lower(clean_code),
        name = clean_name,
        primary_manager_user_id = target_manager_user,
        active = TRUE,
        updated_by = auth.uid(),
        updated_at = now()
    WHERE id = target_customer
      AND organization_id = target_organization
    RETURNING id INTO selected_customer;

    IF selected_customer IS NULL THEN
      RAISE EXCEPTION 'Customer not found in this organization';
    END IF;
  END IF;

  IF target_customer_user IS NOT NULL THEN
    INSERT INTO organization_customer_users(customer_id, user_id, linked_by)
    VALUES (selected_customer, target_customer_user, auth.uid())
    ON CONFLICT (customer_id, user_id)
    DO UPDATE SET linked_by = auth.uid(), linked_at = now();
  END IF;

  RETURN selected_customer;
END;
$$;

REVOKE ALL ON FUNCTION list_organization_customers_v3(UUID, BOOLEAN)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION list_organization_customers_v3(UUID, BOOLEAN)
TO authenticated;

REVOKE ALL ON FUNCTION save_organization_customer_v1(
  UUID, TEXT, TEXT, UUID, UUID, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_organization_customer_v1(
  UUID, TEXT, TEXT, UUID, UUID, UUID
) TO authenticated;

COMMIT;
