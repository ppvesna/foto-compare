-- Trimatrix organization invitations and protected nickname lookup.
-- Prerequisites: migrations 002, 006, 007, 008, and 009.

BEGIN;

CREATE TABLE IF NOT EXISTS organization_invitations (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  email               TEXT NOT NULL,
  nickname            TEXT NOT NULL,
  display_name        TEXT NOT NULL DEFAULT '',
  role                TEXT NOT NULL,
  employee_functions  TEXT[] NOT NULL DEFAULT '{}',
  status              TEXT NOT NULL DEFAULT 'pending',
  delivery_status     TEXT NOT NULL DEFAULT 'pending',
  delivery_error      TEXT,
  invited_by          UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  accepted_by         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  accepted_at         TIMESTAMPTZ,
  expires_at          TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '14 days'),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT organization_invitation_role_check
    CHECK (role IN ('admin', 'employee', 'customer')),
  CONSTRAINT organization_invitation_status_check
    CHECK (status IN ('pending', 'accepted', 'cancelled', 'expired')),
  CONSTRAINT organization_invitation_delivery_check
    CHECK (delivery_status IN ('pending', 'sent', 'failed')),
  CONSTRAINT organization_invitation_email_normalized
    CHECK (email = lower(trim(email))),
  CONSTRAINT organization_invitation_nickname_normalized
    CHECK (nickname = lower(trim(nickname)))
);

CREATE UNIQUE INDEX IF NOT EXISTS one_pending_invitation_per_email
ON organization_invitations(email)
WHERE status = 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS one_pending_invitation_per_nickname
ON organization_invitations(nickname)
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS organization_invitations_org_idx
ON organization_invitations(organization_id, status, created_at);

CREATE TABLE IF NOT EXISTS organization_member_functions (
  organization_id UUID NOT NULL,
  user_id          UUID NOT NULL,
  function_name    TEXT NOT NULL,
  assigned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, user_id, function_name),
  FOREIGN KEY (organization_id, user_id)
    REFERENCES organization_members(organization_id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT organization_member_function_check
    CHECK (function_name IN ('manager', 'designer', 'inspectionSpecialist'))
);

ALTER TABLE organization_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_member_functions ENABLE ROW LEVEL SECURITY;

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
  metadata JSONB;
  selected_plan TEXT;
  selected_status TEXT;
  selected_valid_until TIMESTAMPTZ;
  configured_limit TEXT;
BEGIN
  SELECT COALESCE(owner_user.raw_app_meta_data, '{}'::JSONB)
  INTO metadata
  FROM organization_members AS owner_membership
  JOIN auth.users AS owner_user ON owner_user.id = owner_membership.user_id
  WHERE owner_membership.organization_id = target_organization
    AND owner_membership.role = 'owner'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN 1;
  END IF;

  selected_plan := COALESCE(metadata ->> 'plan', 'free');
  selected_status := COALESCE(metadata ->> 'subscription_status', '');
  selected_valid_until := CASE
    WHEN COALESCE(metadata ->> 'access_valid_until', '') = '' THEN NULL
    ELSE (metadata ->> 'access_valid_until')::TIMESTAMPTZ
  END;

  IF selected_plan IN ('pro', 'enterprise')
    AND selected_status NOT IN ('active', 'trialing', 'grace') THEN
    selected_plan := 'free';
  END IF;

  IF selected_plan IN ('pro', 'enterprise')
    AND selected_valid_until IS NOT NULL
    AND selected_valid_until <= now() THEN
    selected_plan := 'free';
  END IF;

  configured_limit := metadata #>> '{limits,organizationSeats}';
  IF selected_plan <> 'free' AND configured_limit ~ '^[0-9]+$' THEN
    RETURN configured_limit::INTEGER;
  END IF;

  RETURN CASE selected_plan
    WHEN 'enterprise' THEN NULL
    WHEN 'pro' THEN 5
    ELSE 1
  END;
END;
$$;

CREATE OR REPLACE FUNCTION organization_used_seats_v1(
  target_organization UUID
)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (
    (SELECT count(*) FROM organization_members
      WHERE organization_id = target_organization)
    +
    (SELECT count(*) FROM organization_invitations
      WHERE organization_id = target_organization
        AND status = 'pending'
        AND expires_at > now())
  )::INTEGER;
$$;

CREATE OR REPLACE FUNCTION is_nickname_available_v1(
  target_nickname TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    lower(trim(target_nickname)) ~ '^[a-z0-9_]{3,24}$'
    AND NOT EXISTS (
      SELECT 1
      FROM user_profiles
      WHERE lower(nickname) = lower(trim(target_nickname))
    )
    AND NOT EXISTS (
      SELECT 1
      FROM organization_invitations
      WHERE nickname = lower(trim(target_nickname))
        AND status = 'pending'
        AND expires_at > now()
    );
$$;

CREATE OR REPLACE FUNCTION create_organization_invitation_v1(
  target_organization UUID,
  target_email TEXT,
  target_nickname TEXT,
  target_display_name TEXT,
  target_role TEXT,
  target_functions TEXT[] DEFAULT '{}'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  actor_role TEXT;
  clean_email TEXT := lower(trim(target_email));
  clean_nickname TEXT := lower(trim(target_nickname));
  clean_display_name TEXT := trim(COALESCE(target_display_name, ''));
  clean_functions TEXT[] := COALESCE(target_functions, '{}');
  seat_limit INTEGER;
  used_seats INTEGER;
  existing_user_id UUID;
  existing_nickname TEXT;
  existing_invitation_id UUID;
  invitation_id UUID;
BEGIN
  SELECT role INTO actor_role
  FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = auth.uid();

  IF actor_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'Organization administration access required';
  END IF;

  IF target_role NOT IN ('admin', 'employee', 'customer') THEN
    RAISE EXCEPTION 'Unsupported assignable role: %', target_role;
  END IF;

  IF actor_role = 'admin' AND target_role = 'admin' THEN
    RAISE EXCEPTION 'Only the owner may appoint an administrator';
  END IF;

  IF clean_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION 'A valid invitation email is required';
  END IF;

  IF clean_nickname !~ '^[a-z0-9_]{3,24}$' THEN
    RAISE EXCEPTION 'Nickname must contain 3-24 latin letters, digits, or underscores';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(clean_functions) AS requested_function
    WHERE requested_function NOT IN (
      'manager',
      'designer',
      'inspectionSpecialist'
    )
  ) THEN
    RAISE EXCEPTION 'Unsupported employee function';
  END IF;

  IF target_role <> 'employee' THEN
    clean_functions := '{}';
  END IF;

  SELECT auth_user.id, profile.nickname
  INTO existing_user_id, existing_nickname
  FROM auth.users AS auth_user
  LEFT JOIN user_profiles AS profile ON profile.user_id = auth_user.id
  WHERE lower(auth_user.email) = clean_email
  LIMIT 1;

  IF existing_user_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM organization_members WHERE user_id = existing_user_id
    ) THEN
      RAISE EXCEPTION 'This user already belongs to an organization';
    END IF;
    IF COALESCE(existing_nickname, '') <> '' THEN
      clean_nickname := existing_nickname;
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM user_profiles
    WHERE lower(nickname) = clean_nickname
      AND user_id IS DISTINCT FROM existing_user_id
  ) THEN
    RAISE EXCEPTION 'This nickname is already registered';
  END IF;

  SELECT id INTO existing_invitation_id
  FROM organization_invitations
  WHERE email = clean_email
    AND status = 'pending'
  LIMIT 1;

  IF existing_invitation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM organization_invitations
    WHERE id = existing_invitation_id
      AND organization_id = target_organization
  ) THEN
    RAISE EXCEPTION 'This email already has a pending organization invitation';
  END IF;

  IF existing_invitation_id IS NULL THEN
    seat_limit := organization_seat_limit_v1(target_organization);
    used_seats := organization_used_seats_v1(target_organization);
    IF seat_limit IS NOT NULL AND used_seats >= seat_limit THEN
      RAISE EXCEPTION 'The organization seat limit has been reached';
    END IF;

    INSERT INTO organization_invitations(
      organization_id,
      email,
      nickname,
      display_name,
      role,
      employee_functions,
      invited_by
    )
    VALUES (
      target_organization,
      clean_email,
      clean_nickname,
      clean_display_name,
      target_role,
      clean_functions,
      auth.uid()
    )
    RETURNING id INTO invitation_id;
  ELSE
    UPDATE organization_invitations
    SET
      nickname = clean_nickname,
      display_name = clean_display_name,
      role = target_role,
      employee_functions = clean_functions,
      delivery_status = 'pending',
      delivery_error = NULL,
      expires_at = now() + INTERVAL '14 days',
      updated_at = now()
    WHERE id = existing_invitation_id
    RETURNING id INTO invitation_id;
  END IF;

  RETURN jsonb_build_object(
    'invitation_id', invitation_id,
    'email', clean_email,
    'nickname', clean_nickname,
    'is_registered', existing_user_id IS NOT NULL
  );
END;
$$;

CREATE OR REPLACE FUNCTION list_organization_participants_v1(
  target_organization UUID
)
RETURNS TABLE(
  participant_id UUID,
  user_id UUID,
  email TEXT,
  nickname TEXT,
  display_name TEXT,
  role TEXT,
  employee_functions TEXT[],
  status TEXT,
  delivery_status TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT has_organization_role_v2(
    target_organization,
    ARRAY['owner', 'admin']
  ) THEN
    RAISE EXCEPTION 'Organization administration access required';
  END IF;

  RETURN QUERY
  SELECT *
  FROM (
    SELECT
      member.user_id AS participant_id,
      member.user_id,
      COALESCE(auth_user.email, ''),
      COALESCE(profile.nickname, ''),
      COALESCE(profile.display_name, ''),
      member.role,
      COALESCE(
        (
          SELECT array_agg(member_function.function_name ORDER BY member_function.function_name)
          FROM organization_member_functions AS member_function
          WHERE member_function.organization_id = member.organization_id
            AND member_function.user_id = member.user_id
        ),
        '{}'::TEXT[]
      ),
      'active'::TEXT,
      'sent'::TEXT,
      member.created_at
    FROM organization_members AS member
    JOIN auth.users AS auth_user ON auth_user.id = member.user_id
    LEFT JOIN user_profiles AS profile ON profile.user_id = member.user_id
    WHERE member.organization_id = target_organization

    UNION ALL

    SELECT
      invitation.id,
      NULL::UUID,
      invitation.email,
      invitation.nickname,
      invitation.display_name,
      invitation.role,
      invitation.employee_functions,
      invitation.status,
      invitation.delivery_status,
      invitation.created_at
    FROM organization_invitations AS invitation
    WHERE invitation.organization_id = target_organization
      AND invitation.status = 'pending'
      AND invitation.expires_at > now()
  ) AS participants
  ORDER BY
    CASE participants.role
      WHEN 'owner' THEN 1
      WHEN 'admin' THEN 2
      WHEN 'employee' THEN 3
      WHEN 'customer' THEN 4
      ELSE 5
    END,
    participants.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION cancel_organization_invitation_v1(
  target_invitation UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_organization UUID;
BEGIN
  SELECT organization_id INTO selected_organization
  FROM organization_invitations
  WHERE id = target_invitation
    AND status = 'pending';

  IF selected_organization IS NULL THEN
    RAISE EXCEPTION 'Pending invitation was not found';
  END IF;

  IF NOT has_organization_role_v2(
    selected_organization,
    ARRAY['owner', 'admin']
  ) THEN
    RAISE EXCEPTION 'Organization administration access required';
  END IF;

  UPDATE organization_invitations
  SET status = 'cancelled', updated_at = now()
  WHERE id = target_invitation;
END;
$$;

CREATE OR REPLACE FUNCTION current_organization_invitation_v1()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_email TEXT;
  selected_invitation organization_invitations%ROWTYPE;
  selected_organization_name TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT lower(email)
  INTO current_email
  FROM auth.users
  WHERE id = auth.uid()
    AND email_confirmed_at IS NOT NULL;

  IF current_email IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT invitation.*
  INTO selected_invitation
  FROM organization_invitations AS invitation
  WHERE invitation.email = current_email
    AND invitation.status = 'pending'
    AND invitation.expires_at > now()
  ORDER BY invitation.created_at
  LIMIT 1;

  IF selected_invitation.id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT name INTO selected_organization_name
  FROM organizations
  WHERE id = selected_invitation.organization_id;

  RETURN jsonb_build_object(
    'invitation_id', selected_invitation.id,
    'organization_id', selected_invitation.organization_id,
    'organization_name', selected_organization_name,
    'nickname', selected_invitation.nickname,
    'display_name', selected_invitation.display_name,
    'role', selected_invitation.role,
    'employee_functions', selected_invitation.employee_functions
  );
END;
$$;

CREATE OR REPLACE FUNCTION accept_current_organization_invitation_v1()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  current_email TEXT;
  selected_invitation organization_invitations%ROWTYPE;
  selected_organization_name TEXT;
  profile_nickname TEXT;
  profile_display_name TEXT;
  effective_nickname TEXT;
  effective_display_name TEXT;
  seat_limit INTEGER;
  used_seats INTEGER;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT lower(email)
  INTO current_email
  FROM auth.users
  WHERE id = current_user_id
    AND email_confirmed_at IS NOT NULL;

  IF current_email IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT invitation.*
  INTO selected_invitation
  FROM organization_invitations AS invitation
  WHERE invitation.email = current_email
    AND invitation.status = 'pending'
    AND invitation.expires_at > now()
  ORDER BY invitation.created_at
  LIMIT 1;

  IF selected_invitation.id IS NULL THEN
    RETURN NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM organization_members WHERE user_id = current_user_id
  ) THEN
    RAISE EXCEPTION 'The current user already belongs to an organization';
  END IF;

  seat_limit := organization_seat_limit_v1(
    selected_invitation.organization_id
  );
  used_seats := organization_used_seats_v1(
    selected_invitation.organization_id
  ) - 1;
  IF seat_limit IS NOT NULL AND used_seats >= seat_limit THEN
    RAISE EXCEPTION 'The organization seat limit has been reached';
  END IF;

  SELECT nickname, COALESCE(display_name, '')
  INTO profile_nickname, profile_display_name
  FROM user_profiles
  WHERE user_id = current_user_id;

  effective_nickname := COALESCE(
    NULLIF(profile_nickname, ''),
    selected_invitation.nickname
  );
  effective_display_name := COALESCE(
    NULLIF(profile_display_name, ''),
    selected_invitation.display_name
  );

  IF EXISTS (
    SELECT 1
    FROM user_profiles
    WHERE lower(nickname) = lower(effective_nickname)
      AND user_id <> current_user_id
  ) THEN
    RAISE EXCEPTION 'This nickname is already registered';
  END IF;

  SELECT name INTO selected_organization_name
  FROM organizations
  WHERE id = selected_invitation.organization_id;

  INSERT INTO user_profiles(
    user_id,
    email,
    nickname,
    display_name,
    organization_name
  )
  VALUES (
    current_user_id,
    current_email,
    effective_nickname,
    effective_display_name,
    selected_organization_name
  )
  ON CONFLICT (user_id)
  DO UPDATE SET
    email = EXCLUDED.email,
    nickname = EXCLUDED.nickname,
    display_name = EXCLUDED.display_name,
    organization_name = EXCLUDED.organization_name,
    updated_at = now();

  INSERT INTO organization_members(organization_id, user_id, role)
  VALUES (
    selected_invitation.organization_id,
    current_user_id,
    selected_invitation.role
  );

  IF selected_invitation.role = 'employee' THEN
    INSERT INTO organization_member_functions(
      organization_id,
      user_id,
      function_name
    )
    SELECT
      selected_invitation.organization_id,
      current_user_id,
      requested_function
    FROM unnest(selected_invitation.employee_functions) AS requested_function
    ON CONFLICT DO NOTHING;
  END IF;

  UPDATE organization_invitations
  SET
    status = 'accepted',
    accepted_by = current_user_id,
    accepted_at = now(),
    updated_at = now()
  WHERE id = selected_invitation.id;

  RETURN jsonb_build_object(
    'organization_id', selected_invitation.organization_id,
    'organization_name', selected_organization_name,
    'role', selected_invitation.role,
    'nickname', effective_nickname
  );
END;
$$;

DROP POLICY IF EXISTS "public_read_user_profiles" ON user_profiles;
DROP POLICY IF EXISTS "authenticated_read_own_profile_v1" ON user_profiles;

CREATE POLICY "authenticated_read_own_profile_v1"
ON user_profiles
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "managed_read_invitations_v1"
ON organization_invitations;
CREATE POLICY "managed_read_invitations_v1"
ON organization_invitations
FOR SELECT
TO authenticated
USING (
  has_organization_role_v2(
    organization_id,
    ARRAY['owner', 'admin']
  )
);

DROP POLICY IF EXISTS "managed_read_member_functions_v1"
ON organization_member_functions;
CREATE POLICY "managed_read_member_functions_v1"
ON organization_member_functions
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR has_organization_role_v2(
    organization_id,
    ARRAY['owner', 'admin']
  )
);

REVOKE ALL ON FUNCTION organization_seat_limit_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION organization_used_seats_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION is_nickname_available_v1(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION create_organization_invitation_v1(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT[]
) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_organization_participants_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION cancel_organization_invitation_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION current_organization_invitation_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION accept_current_organization_invitation_v1()
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION is_nickname_available_v1(TEXT)
TO anon, authenticated;
GRANT EXECUTE ON FUNCTION create_organization_invitation_v1(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT[]
) TO authenticated;
GRANT EXECUTE ON FUNCTION list_organization_participants_v1(UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_organization_invitation_v1(UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION current_organization_invitation_v1()
TO authenticated;
GRANT EXECUTE ON FUNCTION accept_current_organization_invitation_v1()
TO authenticated;

COMMIT;
