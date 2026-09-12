-- Separate internal team seats from customer representative seats.
-- Prerequisites: migrations 010, 011, and 019.

BEGIN;

UPDATE access_plans
SET
  limits = CASE id
    WHEN 'free' THEN limits
      || '{"organizationSeats":1,"customerRepresentativeSeats":0}'::jsonb
    WHEN 'pro' THEN limits
      || '{"organizationSeats":20,"customerRepresentativeSeats":20}'::jsonb
    WHEN 'enterprise' THEN limits
      || '{"organizationSeats":null,"customerRepresentativeSeats":null}'::jsonb
    ELSE limits
  END,
  updated_at = now()
WHERE id IN ('free', 'pro', 'enterprise');

CREATE OR REPLACE FUNCTION organization_role_seat_limit_v2(
  target_organization UUID,
  customer_representatives BOOLEAN
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_plan TEXT := 'free';
  selected_status TEXT := 'active';
  selected_valid_until TIMESTAMPTZ;
  effective_limits JSONB := '{}'::jsonb;
  owner_metadata JSONB := '{}'::jsonb;
  configured_limit TEXT;
BEGIN
  SELECT
    assignment.plan_id,
    assignment.status,
    assignment.valid_until,
    plan.limits || COALESCE(assignment.limit_overrides, '{}'::jsonb)
  INTO
    selected_plan,
    selected_status,
    selected_valid_until,
    effective_limits
  FROM access_assignments AS assignment
  JOIN access_plans AS plan ON plan.id = assignment.plan_id
  WHERE assignment.organization_id = target_organization
  LIMIT 1;

  IF NOT FOUND THEN
    SELECT COALESCE(owner_user.raw_app_meta_data, '{}'::jsonb)
    INTO owner_metadata
    FROM organization_members AS owner_membership
    JOIN auth.users AS owner_user ON owner_user.id = owner_membership.user_id
    WHERE owner_membership.organization_id = target_organization
      AND owner_membership.role = 'owner'
    LIMIT 1;

    selected_plan := COALESCE(owner_metadata ->> 'plan', 'free');
    selected_status := COALESCE(
      owner_metadata ->> 'subscription_status',
      CASE WHEN selected_plan = 'free' THEN 'active' ELSE '' END
    );
    selected_valid_until := CASE
      WHEN COALESCE(owner_metadata ->> 'access_valid_until', '') = '' THEN NULL
      ELSE (owner_metadata ->> 'access_valid_until')::TIMESTAMPTZ
    END;
    SELECT limits INTO effective_limits
    FROM access_plans
    WHERE id = selected_plan;
  END IF;

  IF selected_plan IN ('pro', 'enterprise')
    AND selected_status NOT IN ('active', 'trialing', 'grace') THEN
    selected_plan := 'free';
    SELECT limits INTO effective_limits FROM access_plans WHERE id = 'free';
  END IF;

  IF selected_plan IN ('pro', 'enterprise')
    AND selected_valid_until IS NOT NULL
    AND selected_valid_until <= now() THEN
    selected_plan := 'free';
    SELECT limits INTO effective_limits FROM access_plans WHERE id = 'free';
  END IF;

  configured_limit := effective_limits ->> CASE
    WHEN customer_representatives THEN 'customerRepresentativeSeats'
    ELSE 'organizationSeats'
  END;

  IF configured_limit ~ '^[0-9]+$' THEN
    RETURN configured_limit::INTEGER;
  END IF;

  RETURN CASE selected_plan
    WHEN 'enterprise' THEN NULL
    WHEN 'pro' THEN 20
    WHEN 'free' THEN CASE WHEN customer_representatives THEN 0 ELSE 1 END
    ELSE CASE WHEN customer_representatives THEN 0 ELSE 1 END
  END;
END;
$$;

-- Compatibility for invitation functions from migrations 010 and 011. They
-- still perform a total-seat preflight; category-specific triggers below are
-- the final authority for the 20 + 20 split.
CREATE OR REPLACE FUNCTION organization_seat_limit_v1(
  target_organization UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  team_limit INTEGER;
  customer_limit INTEGER;
BEGIN
  team_limit := organization_role_seat_limit_v2(target_organization, FALSE);
  customer_limit := organization_role_seat_limit_v2(target_organization, TRUE);
  IF team_limit IS NULL OR customer_limit IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN team_limit + customer_limit;
END;
$$;

CREATE OR REPLACE FUNCTION enforce_organization_invitation_seats_v2()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_customer BOOLEAN := NEW.role = 'customer';
  role_limit INTEGER;
  used_role_seats INTEGER;
BEGIN
  IF NEW.status <> 'pending' OR NEW.expires_at <= now() THEN
    RETURN NEW;
  END IF;

  role_limit := organization_role_seat_limit_v2(
    NEW.organization_id,
    is_customer
  );
  IF role_limit IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT (
    (SELECT count(*)
     FROM organization_members AS member
     WHERE member.organization_id = NEW.organization_id
       AND (member.role = 'customer') = is_customer)
    +
    (SELECT count(*)
     FROM organization_invitations AS invitation
     WHERE invitation.organization_id = NEW.organization_id
       AND invitation.status = 'pending'
       AND invitation.expires_at > now()
       AND (invitation.role = 'customer') = is_customer
       AND invitation.id IS DISTINCT FROM NEW.id)
  )::INTEGER
  INTO used_role_seats;

  IF used_role_seats >= role_limit THEN
    IF is_customer THEN
      RAISE EXCEPTION 'invitation_customer_seat_limit';
    END IF;
    RAISE EXCEPTION 'invitation_seat_limit';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS organization_invitation_seats_v2
ON organization_invitations;
CREATE TRIGGER organization_invitation_seats_v2
BEFORE INSERT OR UPDATE OF organization_id, role, status, expires_at
ON organization_invitations
FOR EACH ROW
EXECUTE FUNCTION enforce_organization_invitation_seats_v2();

CREATE OR REPLACE FUNCTION enforce_organization_member_seats_v2()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_customer BOOLEAN := NEW.role = 'customer';
  role_limit INTEGER;
  active_role_seats INTEGER;
BEGIN
  IF TG_OP = 'UPDATE'
    AND OLD.organization_id = NEW.organization_id
    AND (OLD.role = 'customer') = is_customer THEN
    RETURN NEW;
  END IF;

  role_limit := organization_role_seat_limit_v2(
    NEW.organization_id,
    is_customer
  );
  IF role_limit IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*)::INTEGER
  INTO active_role_seats
  FROM organization_members AS member
  WHERE member.organization_id = NEW.organization_id
    AND (member.role = 'customer') = is_customer
    AND member.user_id IS DISTINCT FROM NEW.user_id;

  IF active_role_seats >= role_limit THEN
    IF is_customer THEN
      RAISE EXCEPTION 'organization_customer_seat_limit';
    END IF;
    RAISE EXCEPTION 'organization_seat_limit';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS organization_member_seats_v2
ON organization_members;
CREATE TRIGGER organization_member_seats_v2
BEFORE INSERT OR UPDATE OF organization_id, role
ON organization_members
FOR EACH ROW
EXECUTE FUNCTION enforce_organization_member_seats_v2();

REVOKE ALL ON FUNCTION organization_role_seat_limit_v2(UUID, BOOLEAN)
FROM PUBLIC;
REVOKE ALL ON FUNCTION enforce_organization_invitation_seats_v2()
FROM PUBLIC;
REVOKE ALL ON FUNCTION enforce_organization_member_seats_v2()
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION organization_role_seat_limit_v2(UUID, BOOLEAN)
TO authenticated;

COMMIT;
