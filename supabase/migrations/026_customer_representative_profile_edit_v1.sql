-- Correct customer-representative details without changing customer links,
-- job access, or message history.

BEGIN;

CREATE OR REPLACE FUNCTION update_customer_representative_v1(
  target_customer UUID,
  target_user UUID DEFAULT NULL,
  target_invitation UUID DEFAULT NULL,
  target_email TEXT DEFAULT '',
  target_nickname TEXT DEFAULT '',
  target_display_name TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_organization UUID;
  actor_role TEXT;
  clean_email TEXT := lower(trim(COALESCE(target_email, '')));
  clean_nickname TEXT := lower(trim(COALESCE(target_nickname, '')));
  clean_display_name TEXT := trim(COALESCE(target_display_name, ''));
BEGIN
  SELECT organization_id INTO selected_organization
  FROM organization_customers
  WHERE id = target_customer;

  IF selected_organization IS NULL THEN
    RAISE EXCEPTION 'customer_representative_customer_not_found';
  END IF;

  SELECT role INTO actor_role
  FROM organization_members
  WHERE organization_id = selected_organization
    AND user_id = auth.uid();

  IF actor_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'customer_representative_access_denied';
  END IF;
  IF (target_user IS NULL) = (target_invitation IS NULL) THEN
    RAISE EXCEPTION 'customer_representative_target_required';
  END IF;
  IF length(clean_display_name) NOT BETWEEN 2 AND 120 THEN
    RAISE EXCEPTION 'customer_representative_invalid_display_name';
  END IF;

  IF target_invitation IS NOT NULL THEN
    IF clean_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
      RAISE EXCEPTION 'customer_representative_invalid_email';
    END IF;
    IF clean_nickname !~ '^[a-z0-9_]{3,24}$' THEN
      RAISE EXCEPTION 'customer_representative_invalid_nickname';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM user_profiles
      WHERE (lower(email) = clean_email AND lower(nickname) <> clean_nickname)
         OR (lower(nickname) = clean_nickname AND lower(email) <> clean_email)
    ) THEN
      RAISE EXCEPTION 'customer_representative_nickname_conflict';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM organization_invitations
      WHERE status = 'pending'
        AND id <> target_invitation
        AND (email = clean_email OR nickname = clean_nickname)
    ) THEN
      RAISE EXCEPTION 'customer_representative_invitation_conflict';
    END IF;

    UPDATE organization_invitations
    SET
      email = clean_email,
      nickname = clean_nickname,
      display_name = clean_display_name,
      delivery_status = 'pending',
      delivery_error = NULL,
      expires_at = now() + INTERVAL '14 days',
      updated_at = now()
    WHERE id = target_invitation
      AND organization_id = selected_organization
      AND customer_id = target_customer
      AND role = 'customer'
      AND status = 'pending';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'customer_representative_invitation_not_found';
    END IF;
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM organization_customer_users
    WHERE customer_id = target_customer
      AND user_id = target_user
  ) OR NOT EXISTS (
    SELECT 1
    FROM organization_members
    WHERE organization_id = selected_organization
      AND user_id = target_user
      AND role = 'customer'
  ) THEN
    RAISE EXCEPTION 'customer_representative_user_not_found';
  END IF;

  UPDATE user_profiles
  SET display_name = clean_display_name, updated_at = now()
  WHERE user_id = target_user;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'customer_representative_profile_not_found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION update_customer_representative_v1(
  UUID, UUID, UUID, TEXT, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_customer_representative_v1(
  UUID, UUID, UUID, TEXT, TEXT, TEXT
) TO authenticated;

COMMIT;
