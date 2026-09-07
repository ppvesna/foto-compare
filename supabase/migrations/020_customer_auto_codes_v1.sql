-- Generate stable customer codes inside each organization.
-- The UI no longer asks users to maintain an internal identifier manually.

BEGIN;

ALTER TABLE organizations
ADD COLUMN IF NOT EXISTS next_customer_number INTEGER NOT NULL DEFAULT 1;

UPDATE organizations AS organization
SET next_customer_number = GREATEST(
  organization.next_customer_number,
  COALESCE(
    (
      SELECT max(substring(customer.code FROM '^C-([0-9]+)$')::INTEGER) + 1
      FROM organization_customers AS customer
      WHERE customer.organization_id = organization.id
        AND customer.code ~ '^C-[0-9]+$'
    ),
    1
  )
);

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
    SELECT 1
    FROM organization_members
    WHERE organization_id = target_organization
      AND user_id = target_manager_user
      AND role IN ('owner', 'admin', 'employee')
  ) THEN
    RAISE EXCEPTION 'Selected employee is not an organization member';
  END IF;

  IF target_customer_user IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM organization_members
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
      organization_id,
      code,
      code_key,
      name,
      primary_manager_user_id,
      created_by,
      updated_by
    )
    VALUES (
      target_organization,
      clean_code,
      lower(clean_code),
      clean_name,
      target_manager_user,
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO selected_customer;
  ELSE
    UPDATE organization_customers
    SET
      code = clean_code,
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

  DELETE FROM organization_customer_users
  WHERE customer_id = selected_customer;

  IF target_customer_user IS NOT NULL THEN
    INSERT INTO organization_customer_users(
      customer_id,
      user_id,
      linked_by
    )
    VALUES (
      selected_customer,
      target_customer_user,
      auth.uid()
    )
    ON CONFLICT (customer_id, user_id)
    DO UPDATE SET linked_by = auth.uid(), linked_at = now();
  END IF;

  RETURN selected_customer;
END;
$$;

REVOKE ALL ON FUNCTION save_organization_customer_v1(
  UUID, TEXT, TEXT, UUID, UUID, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_organization_customer_v1(
  UUID, TEXT, TEXT, UUID, UUID, UUID
) TO authenticated;

COMMIT;
