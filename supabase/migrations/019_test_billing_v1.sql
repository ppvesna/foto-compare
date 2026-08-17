-- Trimatrix test billing and assignment-backed entitlement snapshot.
-- Prerequisite: migration 006 (current organization roles and helpers).
-- This migration intentionally bootstraps only the neutral access tables from the
-- unapplied 005 prototype. It does not install its obsolete roles or policies.
-- IMPORTANT: disable test_payments_enabled before connecting a real provider.

BEGIN;

CREATE TABLE IF NOT EXISTS access_plans (
  id           TEXT PRIMARY KEY CHECK (id IN ('free', 'pro', 'enterprise')),
  display_name TEXT NOT NULL,
  entitlements JSONB NOT NULL DEFAULT '[]'::jsonb,
  limits       JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(entitlements) = 'array'),
  CHECK (jsonb_typeof(limits) = 'object')
);

INSERT INTO access_plans(id, display_name, entitlements, limits)
VALUES
  (
    'free',
    'Free',
    '["runInspection","barcode","protocolHistory"]'::jsonb,
    '{"checksPerDay":10,"savedReferences":3,"organizationSeats":1}'::jsonb
  ),
  (
    'pro',
    'Pro',
    '["runInspection","exactDeltaE","ocr","barcode","aiAnalysis","protocolHistory","multipleReferences","cloudSync","cloudAssets","pdfReports","collaboration"]'::jsonb,
    '{"checksPerDay":500,"savedReferences":50,"organizationSeats":5}'::jsonb
  ),
  (
    'enterprise',
    'Enterprise',
    '["runInspection","exactDeltaE","ocr","barcode","aiAnalysis","protocolHistory","multipleReferences","cloudSync","cloudAssets","pdfReports","collaboration"]'::jsonb,
    '{"checksPerDay":null,"savedReferences":null,"organizationSeats":null}'::jsonb
  )
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS access_assignments (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  organization_id       UUID REFERENCES organizations(id) ON DELETE CASCADE,
  plan_id               TEXT NOT NULL REFERENCES access_plans(id),
  status                TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active','trialing','grace','paused','cancelled')),
  entitlement_overrides JSONB,
  limit_overrides       JSONB NOT NULL DEFAULT '{}'::jsonb,
  valid_until           TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((user_id IS NULL) <> (organization_id IS NULL)),
  CHECK (
    entitlement_overrides IS NULL
    OR jsonb_typeof(entitlement_overrides) = 'array'
  ),
  CHECK (jsonb_typeof(limit_overrides) = 'object')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_access_assignment_user
ON access_assignments(user_id)
WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_access_assignment_org
ON access_assignments(organization_id)
WHERE organization_id IS NOT NULL;

ALTER TABLE access_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_assignments ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS billing_runtime_config (
  id                     BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  test_payments_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO billing_runtime_config(id, test_payments_enabled)
VALUES (TRUE, TRUE)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS billing_plan_prices (
  plan_id        TEXT NOT NULL REFERENCES access_plans(id),
  period_months  INTEGER NOT NULL CHECK (period_months IN (1, 12)),
  amount_minor   INTEGER NOT NULL CHECK (amount_minor > 0),
  currency       TEXT NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (plan_id, period_months, currency)
);

INSERT INTO billing_plan_prices(
  plan_id,
  period_months,
  amount_minor,
  currency
)
VALUES
  ('pro', 1, 2900, 'EUR'),
  ('pro', 12, 29000, 'EUR'),
  ('enterprise', 1, 9900, 'EUR'),
  ('enterprise', 12, 99000, 'EUR')
ON CONFLICT (plan_id, period_months, currency)
DO UPDATE SET
  amount_minor = EXCLUDED.amount_minor,
  active = TRUE,
  updated_at = now();

CREATE TABLE IF NOT EXISTS billing_profiles (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  organization_id  UUID REFERENCES organizations(id) ON DELETE CASCADE,
  billing_email    TEXT NOT NULL DEFAULT '',
  legal_name       TEXT NOT NULL DEFAULT '',
  country_code     TEXT NOT NULL DEFAULT '',
  tax_id           TEXT NOT NULL DEFAULT '',
  billing_address  TEXT NOT NULL DEFAULT '',
  created_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((user_id IS NULL) <> (organization_id IS NULL)),
  CHECK (country_code = '' OR country_code ~ '^[A-Z]{2}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS billing_profiles_user_unique
ON billing_profiles(user_id)
WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS billing_profiles_org_unique
ON billing_profiles(organization_id)
WHERE organization_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS billing_payment_attempts (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requested_by     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  organization_id  UUID REFERENCES organizations(id) ON DELETE CASCADE,
  billing_scope    TEXT NOT NULL CHECK (billing_scope IN ('personal', 'organization')),
  plan_id          TEXT NOT NULL REFERENCES access_plans(id),
  period_months    INTEGER NOT NULL CHECK (period_months IN (1, 12)),
  amount_minor     INTEGER NOT NULL CHECK (amount_minor > 0),
  currency         TEXT NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  provider         TEXT NOT NULL DEFAULT 'test',
  status           TEXT NOT NULL CHECK (status IN ('pending', 'succeeded', 'failed')),
  valid_until      TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS billing_payment_attempts_user_idx
ON billing_payment_attempts(requested_by, created_at DESC);

CREATE INDEX IF NOT EXISTS billing_payment_attempts_org_idx
ON billing_payment_attempts(organization_id, created_at DESC)
WHERE organization_id IS NOT NULL;

ALTER TABLE billing_runtime_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_plan_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_payment_attempts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION billing_quote_v1(
  target_plan TEXT,
  target_period_months INTEGER,
  target_currency TEXT DEFAULT 'EUR'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_price billing_plan_prices%ROWTYPE;
  test_mode_enabled BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO selected_price
  FROM billing_plan_prices
  WHERE plan_id = target_plan
    AND period_months = target_period_months
    AND currency = upper(target_currency)
    AND active;

  IF selected_price.plan_id IS NULL THEN
    RAISE EXCEPTION 'Billing price was not found';
  END IF;

  SELECT test_payments_enabled INTO test_mode_enabled
  FROM billing_runtime_config
  WHERE id = TRUE;

  RETURN jsonb_build_object(
    'plan', selected_price.plan_id,
    'period_months', selected_price.period_months,
    'amount_minor', selected_price.amount_minor,
    'currency', selected_price.currency,
    'test_mode', COALESCE(test_mode_enabled, FALSE)
  );
END;
$$;

CREATE OR REPLACE FUNCTION current_billing_profile_v1(
  target_scope TEXT,
  target_organization UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_profile billing_profiles%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF target_scope = 'organization' THEN
    IF target_organization IS NULL OR NOT has_organization_role_v2(
      target_organization,
      ARRAY['owner']
    ) THEN
      RAISE EXCEPTION 'Organization billing access required';
    END IF;
    SELECT * INTO selected_profile
    FROM billing_profiles
    WHERE organization_id = target_organization;
  ELSIF target_scope = 'personal' THEN
    SELECT * INTO selected_profile
    FROM billing_profiles
    WHERE user_id = auth.uid();
  ELSE
    RAISE EXCEPTION 'Unknown billing scope';
  END IF;

  RETURN jsonb_build_object(
    'billing_email', COALESCE(selected_profile.billing_email, ''),
    'legal_name', COALESCE(selected_profile.legal_name, ''),
    'country_code', COALESCE(selected_profile.country_code, ''),
    'tax_id', COALESCE(selected_profile.tax_id, ''),
    'billing_address', COALESCE(selected_profile.billing_address, '')
  );
END;
$$;

CREATE OR REPLACE FUNCTION save_billing_profile_v1(
  target_scope TEXT,
  target_organization UUID,
  target_billing_email TEXT,
  target_legal_name TEXT,
  target_country_code TEXT,
  target_tax_id TEXT,
  target_billing_address TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  clean_country TEXT := upper(trim(COALESCE(target_country_code, '')));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF clean_country <> '' AND clean_country !~ '^[A-Z]{2}$' THEN
    RAISE EXCEPTION 'Country code must contain two letters';
  END IF;
  IF length(COALESCE(target_billing_email, '')) > 320
    OR length(COALESCE(target_legal_name, '')) > 200
    OR length(COALESCE(target_tax_id, '')) > 80
    OR length(COALESCE(target_billing_address, '')) > 500 THEN
    RAISE EXCEPTION 'Billing profile field is too long';
  END IF;

  IF target_scope = 'organization' THEN
    IF target_organization IS NULL OR NOT has_organization_role_v2(
      target_organization,
      ARRAY['owner']
    ) THEN
      RAISE EXCEPTION 'Organization billing access required';
    END IF;
    INSERT INTO billing_profiles(
      organization_id,
      billing_email,
      legal_name,
      country_code,
      tax_id,
      billing_address,
      created_by,
      updated_by
    )
    VALUES (
      target_organization,
      lower(trim(COALESCE(target_billing_email, ''))),
      trim(COALESCE(target_legal_name, '')),
      clean_country,
      trim(COALESCE(target_tax_id, '')),
      trim(COALESCE(target_billing_address, '')),
      auth.uid(),
      auth.uid()
    )
    ON CONFLICT (organization_id) WHERE organization_id IS NOT NULL
    DO UPDATE SET
      billing_email = EXCLUDED.billing_email,
      legal_name = EXCLUDED.legal_name,
      country_code = EXCLUDED.country_code,
      tax_id = EXCLUDED.tax_id,
      billing_address = EXCLUDED.billing_address,
      updated_by = auth.uid(),
      updated_at = now();
  ELSIF target_scope = 'personal' THEN
    INSERT INTO billing_profiles(
      user_id,
      billing_email,
      legal_name,
      country_code,
      tax_id,
      billing_address,
      created_by,
      updated_by
    )
    VALUES (
      auth.uid(),
      lower(trim(COALESCE(target_billing_email, ''))),
      trim(COALESCE(target_legal_name, '')),
      clean_country,
      trim(COALESCE(target_tax_id, '')),
      trim(COALESCE(target_billing_address, '')),
      auth.uid(),
      auth.uid()
    )
    ON CONFLICT (user_id) WHERE user_id IS NOT NULL
    DO UPDATE SET
      billing_email = EXCLUDED.billing_email,
      legal_name = EXCLUDED.legal_name,
      country_code = EXCLUDED.country_code,
      tax_id = EXCLUDED.tax_id,
      billing_address = EXCLUDED.billing_address,
      updated_by = auth.uid(),
      updated_at = now();
  ELSE
    RAISE EXCEPTION 'Unknown billing scope';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION activate_test_subscription_v1(
  target_scope TEXT,
  target_organization UUID,
  target_plan TEXT,
  target_period_months INTEGER,
  target_amount_minor INTEGER,
  target_currency TEXT DEFAULT 'EUR'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  selected_price billing_plan_prices%ROWTYPE;
  previous_valid_until TIMESTAMPTZ;
  next_valid_until TIMESTAMPTZ;
  payment_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT COALESCE(
    (SELECT test_payments_enabled FROM billing_runtime_config WHERE id = TRUE),
    FALSE
  ) THEN
    RAISE EXCEPTION 'Test payments are disabled';
  END IF;

  SELECT * INTO selected_price
  FROM billing_plan_prices
  WHERE plan_id = target_plan
    AND period_months = target_period_months
    AND currency = upper(target_currency)
    AND active;

  IF selected_price.plan_id IS NULL
    OR selected_price.amount_minor <> target_amount_minor THEN
    RAISE EXCEPTION 'Billing quote has changed';
  END IF;

  IF target_scope = 'organization' THEN
    IF target_organization IS NULL OR NOT has_organization_role_v2(
      target_organization,
      ARRAY['owner']
    ) THEN
      RAISE EXCEPTION 'Organization billing access required';
    END IF;

    SELECT valid_until INTO previous_valid_until
    FROM access_assignments
    WHERE organization_id = target_organization;

    next_valid_until := GREATEST(
      now(),
      COALESCE(previous_valid_until, now())
    ) + make_interval(months => target_period_months);

    INSERT INTO access_assignments(
      organization_id,
      plan_id,
      status,
      valid_until,
      updated_at
    )
    VALUES (
      target_organization,
      target_plan,
      'active',
      next_valid_until,
      now()
    )
    ON CONFLICT (organization_id) WHERE organization_id IS NOT NULL
    DO UPDATE SET
      plan_id = EXCLUDED.plan_id,
      status = 'active',
      entitlement_overrides = NULL,
      limit_overrides = '{}'::jsonb,
      valid_until = EXCLUDED.valid_until,
      updated_at = now();
  ELSIF target_scope = 'personal' THEN
    SELECT valid_until INTO previous_valid_until
    FROM access_assignments
    WHERE user_id = auth.uid();

    next_valid_until := GREATEST(
      now(),
      COALESCE(previous_valid_until, now())
    ) + make_interval(months => target_period_months);

    INSERT INTO access_assignments(
      user_id,
      plan_id,
      status,
      valid_until,
      updated_at
    )
    VALUES (
      auth.uid(),
      target_plan,
      'active',
      next_valid_until,
      now()
    )
    ON CONFLICT (user_id) WHERE user_id IS NOT NULL
    DO UPDATE SET
      plan_id = EXCLUDED.plan_id,
      status = 'active',
      entitlement_overrides = NULL,
      limit_overrides = '{}'::jsonb,
      valid_until = EXCLUDED.valid_until,
      updated_at = now();

    UPDATE auth.users
    SET raw_app_meta_data =
      (COALESCE(raw_app_meta_data, '{}'::jsonb) - 'entitlements' - 'limits')
      || jsonb_build_object(
        'plan', target_plan,
        'subscription_status', 'active',
        'access_valid_until', next_valid_until
      )
    WHERE id = auth.uid();
  ELSE
    RAISE EXCEPTION 'Unknown billing scope';
  END IF;

  INSERT INTO billing_payment_attempts(
    requested_by,
    organization_id,
    billing_scope,
    plan_id,
    period_months,
    amount_minor,
    currency,
    provider,
    status,
    valid_until
  )
  VALUES (
    auth.uid(),
    CASE WHEN target_scope = 'organization' THEN target_organization END,
    target_scope,
    target_plan,
    target_period_months,
    selected_price.amount_minor,
    selected_price.currency,
    'test',
    'succeeded',
    next_valid_until
  )
  RETURNING id INTO payment_id;

  RETURN jsonb_build_object(
    'payment_id', payment_id,
    'status', 'succeeded',
    'plan', target_plan,
    'period_months', target_period_months,
    'amount_minor', selected_price.amount_minor,
    'currency', selected_price.currency,
    'valid_until', next_valid_until,
    'test_mode', TRUE
  );
END;
$$;

CREATE OR REPLACE FUNCTION current_entitlement_v4()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  selected_organization_id UUID;
  personal_metadata JSONB;
  owner_metadata JSONB;
  personal_assignment access_assignments%ROWTYPE;
  effective_assignment access_assignments%ROWTYPE;
  selected_plan access_plans%ROWTYPE;
  personal_plan TEXT := 'free';
  effective_plan TEXT := 'free';
  effective_status TEXT := 'active';
  effective_valid_until TIMESTAMPTZ;
  effective_entitlements JSONB;
  effective_limits JSONB;
  entitlement_scope TEXT := 'personal';
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT COALESCE(raw_app_meta_data, '{}'::jsonb)
  INTO personal_metadata
  FROM auth.users
  WHERE id = current_user_id;

  SELECT * INTO personal_assignment
  FROM access_assignments
  WHERE user_id = current_user_id;

  IF personal_assignment.id IS NOT NULL THEN
    personal_plan := personal_assignment.plan_id;
  ELSE
    personal_plan := COALESCE(personal_metadata ->> 'plan', 'free');
  END IF;

  SELECT membership.organization_id
  INTO selected_organization_id
  FROM organization_members AS membership
  WHERE membership.user_id = current_user_id
  ORDER BY
    CASE membership.role
      WHEN 'owner' THEN 1
      WHEN 'admin' THEN 2
      WHEN 'employee' THEN 3
      WHEN 'customer' THEN 4
      ELSE 5
    END,
    membership.created_at
  LIMIT 1;

  IF selected_organization_id IS NOT NULL THEN
    entitlement_scope := 'organization';
    SELECT * INTO effective_assignment
    FROM access_assignments
    WHERE organization_id = selected_organization_id;

    IF effective_assignment.id IS NULL THEN
      SELECT COALESCE(owner_user.raw_app_meta_data, '{}'::jsonb)
      INTO owner_metadata
      FROM organization_members AS owner_membership
      JOIN auth.users AS owner_user
        ON owner_user.id = owner_membership.user_id
      WHERE owner_membership.organization_id = selected_organization_id
        AND owner_membership.role = 'owner'
      LIMIT 1;

      effective_plan := COALESCE(owner_metadata ->> 'plan', 'free');
      effective_status := COALESCE(
        owner_metadata ->> 'subscription_status',
        CASE WHEN effective_plan = 'free' THEN 'active' ELSE '' END
      );
      effective_valid_until := CASE
        WHEN COALESCE(owner_metadata ->> 'access_valid_until', '') = '' THEN NULL
        ELSE (owner_metadata ->> 'access_valid_until')::TIMESTAMPTZ
      END;
      SELECT * INTO selected_plan FROM access_plans WHERE id = effective_plan;
      effective_entitlements := COALESCE(
        owner_metadata -> 'entitlements',
        selected_plan.entitlements
      );
      effective_limits := COALESCE(
        owner_metadata -> 'limits',
        selected_plan.limits
      );
    END IF;
  ELSE
    effective_assignment := personal_assignment;
    IF effective_assignment.id IS NULL THEN
      effective_plan := COALESCE(personal_metadata ->> 'plan', 'free');
      effective_status := COALESCE(
        personal_metadata ->> 'subscription_status',
        CASE WHEN effective_plan = 'free' THEN 'active' ELSE '' END
      );
      effective_valid_until := CASE
        WHEN COALESCE(personal_metadata ->> 'access_valid_until', '') = '' THEN NULL
        ELSE (personal_metadata ->> 'access_valid_until')::TIMESTAMPTZ
      END;
      SELECT * INTO selected_plan FROM access_plans WHERE id = effective_plan;
      effective_entitlements := COALESCE(
        personal_metadata -> 'entitlements',
        selected_plan.entitlements
      );
      effective_limits := COALESCE(
        personal_metadata -> 'limits',
        selected_plan.limits
      );
    END IF;
  END IF;

  IF effective_assignment.id IS NOT NULL THEN
    effective_plan := effective_assignment.plan_id;
    effective_status := effective_assignment.status;
    effective_valid_until := effective_assignment.valid_until;
    SELECT * INTO selected_plan
    FROM access_plans
    WHERE id = effective_assignment.plan_id;
    effective_entitlements := COALESCE(
      effective_assignment.entitlement_overrides,
      selected_plan.entitlements
    );
    effective_limits := selected_plan.limits
      || COALESCE(effective_assignment.limit_overrides, '{}'::jsonb);
  END IF;

  RETURN jsonb_build_object(
    'plan', effective_plan,
    'personal_plan', personal_plan,
    'entitlement_scope', entitlement_scope,
    'organization_id', selected_organization_id,
    'subscription_status', effective_status,
    'access_valid_until', effective_valid_until,
    'entitlements', effective_entitlements,
    'limits', effective_limits
  );
END;
$$;

REVOKE ALL ON TABLE billing_runtime_config FROM PUBLIC;
REVOKE ALL ON TABLE billing_plan_prices FROM PUBLIC;
REVOKE ALL ON TABLE billing_profiles FROM PUBLIC;
REVOKE ALL ON TABLE billing_payment_attempts FROM PUBLIC;
REVOKE ALL ON FUNCTION billing_quote_v1(TEXT, INTEGER, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION current_billing_profile_v1(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION save_billing_profile_v1(
  TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION activate_test_subscription_v1(
  TEXT, UUID, TEXT, INTEGER, INTEGER, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION current_entitlement_v4() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION billing_quote_v1(TEXT, INTEGER, TEXT)
TO authenticated;
GRANT EXECUTE ON FUNCTION current_billing_profile_v1(TEXT, UUID)
TO authenticated;
GRANT EXECUTE ON FUNCTION save_billing_profile_v1(
  TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT
) TO authenticated;
GRANT EXECUTE ON FUNCTION activate_test_subscription_v1(
  TEXT, UUID, TEXT, INTEGER, INTEGER, TEXT
) TO authenticated;
GRANT EXECUTE ON FUNCTION current_entitlement_v4()
TO authenticated;

COMMIT;
