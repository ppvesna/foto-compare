-- Recover interrupted organization invitations without creating duplicate users.
-- Prerequisite: migration 010.

BEGIN;

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
  nickname_owner_id UUID;
  nickname_owner_email TEXT;
  pending_invitation_id UUID;
  pending_invitation_organization UUID;
  recoverable_invitation_id UUID;
  invitation_id UUID;
BEGIN
  SELECT role INTO actor_role
  FROM organization_members
  WHERE organization_id = target_organization
    AND user_id = auth.uid();

  IF actor_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'invitation_access_denied';
  END IF;

  IF target_role NOT IN ('admin', 'employee', 'customer') THEN
    RAISE EXCEPTION 'invitation_unsupported_role';
  END IF;

  IF actor_role = 'admin' AND target_role = 'admin' THEN
    RAISE EXCEPTION 'invitation_admin_assignment_denied';
  END IF;

  IF clean_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION 'invitation_invalid_email';
  END IF;

  IF clean_nickname !~ '^[a-z0-9_]{3,24}$' THEN
    RAISE EXCEPTION 'invitation_invalid_nickname';
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
    RAISE EXCEPTION 'invitation_unsupported_employee_function';
  END IF;

  IF target_role <> 'employee' THEN
    clean_functions := '{}';
  END IF;

  -- Expired rows must not keep unique email/nickname reservations forever.
  UPDATE organization_invitations
  SET status = 'expired', updated_at = now()
  WHERE status = 'pending'
    AND expires_at <= now();

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
      RAISE EXCEPTION 'invitation_user_already_member';
    END IF;
    IF COALESCE(existing_nickname, '') <> '' THEN
      clean_nickname := lower(existing_nickname);
    END IF;
  END IF;

  SELECT
    profile.user_id,
    lower(COALESCE(auth_user.email, profile.email))
  INTO nickname_owner_id, nickname_owner_email
  FROM user_profiles AS profile
  LEFT JOIN auth.users AS auth_user ON auth_user.id = profile.user_id
  WHERE lower(profile.nickname) = clean_nickname
  LIMIT 1;

  IF nickname_owner_id IS NOT NULL THEN
    IF existing_user_id IS NULL AND nickname_owner_email = clean_email THEN
      existing_user_id := nickname_owner_id;
      existing_nickname := clean_nickname;
    ELSIF existing_user_id IS DISTINCT FROM nickname_owner_id THEN
      RAISE EXCEPTION 'invitation_nickname_conflict';
    END IF;
  END IF;

  IF existing_user_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM organization_members WHERE user_id = existing_user_id
  ) THEN
    RAISE EXCEPTION 'invitation_user_already_member';
  END IF;

  SELECT id, organization_id
  INTO pending_invitation_id, pending_invitation_organization
  FROM organization_invitations
  WHERE email = clean_email
    AND status = 'pending'
  ORDER BY updated_at DESC
  LIMIT 1;

  IF pending_invitation_id IS NOT NULL
    AND pending_invitation_organization <> target_organization THEN
    RAISE EXCEPTION 'invitation_email_conflict';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM organization_invitations
    WHERE nickname = clean_nickname
      AND status = 'pending'
      AND id IS DISTINCT FROM pending_invitation_id
  ) THEN
    RAISE EXCEPTION 'invitation_nickname_conflict';
  END IF;

  IF pending_invitation_id IS NOT NULL THEN
    invitation_id := pending_invitation_id;
  ELSE
    SELECT id
    INTO recoverable_invitation_id
    FROM organization_invitations
    WHERE organization_id = target_organization
      AND email = clean_email
      AND status IN ('cancelled', 'expired')
    ORDER BY updated_at DESC
    LIMIT 1;

    seat_limit := organization_seat_limit_v1(target_organization);
    used_seats := organization_used_seats_v1(target_organization);
    IF seat_limit IS NOT NULL AND used_seats >= seat_limit THEN
      RAISE EXCEPTION 'invitation_seat_limit';
    END IF;

    IF recoverable_invitation_id IS NOT NULL THEN
      invitation_id := recoverable_invitation_id;
    ELSE
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
    END IF;
  END IF;

  IF pending_invitation_id IS NOT NULL
    OR recoverable_invitation_id IS NOT NULL THEN
    UPDATE organization_invitations
    SET
      organization_id = target_organization,
      email = clean_email,
      nickname = clean_nickname,
      display_name = clean_display_name,
      role = target_role,
      employee_functions = clean_functions,
      status = 'pending',
      delivery_status = 'pending',
      delivery_error = NULL,
      invited_by = auth.uid(),
      accepted_by = NULL,
      accepted_at = NULL,
      expires_at = now() + INTERVAL '14 days',
      updated_at = now()
    WHERE id = invitation_id;
  END IF;

  RETURN jsonb_build_object(
    'invitation_id', invitation_id,
    'email', clean_email,
    'nickname', clean_nickname,
    'is_registered', existing_user_id IS NOT NULL,
    'user_id', existing_user_id,
    'recovered', recoverable_invitation_id IS NOT NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION create_organization_invitation_v1(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_organization_invitation_v1(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT[]
) TO authenticated;

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
      COALESCE(auth_user.email, '')::TEXT,
      COALESCE(profile.nickname, '')::TEXT,
      COALESCE(profile.display_name, '')::TEXT,
      member.role::TEXT,
      COALESCE(
        (
          SELECT array_agg(
            member_function.function_name::TEXT
            ORDER BY member_function.function_name
          )
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
      invitation.email::TEXT,
      invitation.nickname::TEXT,
      invitation.display_name::TEXT,
      invitation.role::TEXT,
      invitation.employee_functions::TEXT[],
      invitation.status::TEXT,
      invitation.delivery_status::TEXT,
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

REVOKE ALL ON FUNCTION list_organization_participants_v1(UUID)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION list_organization_participants_v1(UUID)
TO authenticated;

COMMIT;
