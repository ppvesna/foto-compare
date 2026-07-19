-- foto-compare: plans, entitlements, organization roles, and restrictive RLS.
-- Review and apply after migrations 001-004. Existing local Flutter data is unaffected.

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

INSERT INTO access_plans (id, display_name, entitlements, limits)
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
  CHECK (entitlement_overrides IS NULL OR jsonb_typeof(entitlement_overrides) = 'array'),
  CHECK (jsonb_typeof(limit_overrides) = 'object')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_access_assignment_user
ON access_assignments(user_id) WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_access_assignment_org
ON access_assignments(organization_id) WHERE organization_id IS NOT NULL;

-- Preserve the current product behavior during rollout. Accounts that already exist
-- when this migration is applied receive a temporary Pro grace period. New accounts
-- without an assignment resolve to Free.
INSERT INTO access_assignments (
  user_id,
  plan_id,
  status,
  valid_until
)
SELECT
  id,
  'pro',
  'grace',
  now() + INTERVAL '90 days'
FROM auth.users
ON CONFLICT (user_id) WHERE user_id IS NOT NULL DO NOTHING;

CREATE OR REPLACE FUNCTION is_organization_member(target_organization UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM organization_members
    WHERE organization_id = target_organization
      AND user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION has_organization_role(
  target_organization UUID,
  allowed_roles TEXT[]
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM organization_members
    WHERE organization_id = target_organization
      AND user_id = auth.uid()
      AND role = ANY(allowed_roles)
  );
$$;

REVOKE ALL ON FUNCTION is_organization_member(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION has_organization_role(UUID, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION is_organization_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION has_organization_role(UUID, TEXT[]) TO authenticated;

ALTER TABLE access_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_read_access_plans" ON access_plans
FOR SELECT TO authenticated USING (true);

CREATE POLICY "read_own_access_assignment" ON access_assignments
FOR SELECT TO authenticated
USING (
  user_id = auth.uid()
  OR (organization_id IS NOT NULL AND is_organization_member(organization_id))
);

-- No client write policy is intentionally created for access_assignments.
-- Payment webhooks and enterprise administration must use a trusted backend.

CREATE OR REPLACE FUNCTION current_access_snapshot(
  requested_organization UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  selected_organization UUID;
  selected_role TEXT;
  selected_assignment access_assignments%ROWTYPE;
  selected_plan access_plans%ROWTYPE;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF requested_organization IS NOT NULL THEN
    SELECT organization_id, role
      INTO selected_organization, selected_role
    FROM organization_members
    WHERE organization_id = requested_organization
      AND user_id = current_user_id;

    IF selected_organization IS NULL THEN
      RAISE EXCEPTION 'Organization access denied';
    END IF;
  ELSE
    SELECT organization_id, role
      INTO selected_organization, selected_role
    FROM organization_members
    WHERE user_id = current_user_id
    ORDER BY
      CASE role
        WHEN 'owner' THEN 1
        WHEN 'admin' THEN 2
        WHEN 'technologist' THEN 3
        WHEN 'operator' THEN 4
        ELSE 5
      END,
      created_at
    LIMIT 1;
  END IF;

  SELECT * INTO selected_assignment
  FROM access_assignments
  WHERE
    (selected_organization IS NOT NULL AND organization_id = selected_organization)
    OR (selected_organization IS NULL AND user_id = current_user_id)
  LIMIT 1;

  IF selected_assignment.id IS NULL AND selected_organization IS NOT NULL THEN
    SELECT * INTO selected_assignment
    FROM access_assignments
    WHERE user_id = current_user_id
    LIMIT 1;
  END IF;

  IF selected_assignment.id IS NULL
     OR selected_assignment.status NOT IN ('active','trialing','grace')
     OR (selected_assignment.valid_until IS NOT NULL
         AND selected_assignment.valid_until <= now()) THEN
    SELECT * INTO selected_plan FROM access_plans WHERE id = 'free';
    RETURN jsonb_build_object(
      'plan', selected_plan.id,
      'subscription_status', 'active',
      'entitlements', selected_plan.entitlements,
      'limits', selected_plan.limits,
      'organization_id', selected_organization,
      'organization_role', selected_role
    );
  END IF;

  SELECT * INTO selected_plan
  FROM access_plans
  WHERE id = selected_assignment.plan_id;

  RETURN jsonb_build_object(
    'plan', selected_plan.id,
    'subscription_status', selected_assignment.status,
    'access_valid_until', selected_assignment.valid_until,
    'entitlements', COALESCE(
      selected_assignment.entitlement_overrides,
      selected_plan.entitlements
    ),
    'limits', selected_plan.limits || selected_assignment.limit_overrides,
    'organization_id', selected_organization,
    'organization_role', selected_role
  );
END;
$$;

REVOKE ALL ON FUNCTION current_access_snapshot(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION current_access_snapshot(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION has_product_capability(required_capability TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (current_access_snapshot() -> 'entitlements') ? required_capability,
    false
  );
$$;

REVOKE ALL ON FUNCTION has_product_capability(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION has_product_capability(TEXT) TO authenticated;

-- Attach production records to an organization while preserving personal records.
ALTER TABLE layouts
ADD COLUMN IF NOT EXISTS organization_id UUID
REFERENCES organizations(id) ON DELETE SET NULL;

ALTER TABLE check_results
ADD COLUMN IF NOT EXISTS organization_id UUID
REFERENCES organizations(id) ON DELETE SET NULL;

ALTER TABLE production_orders
ADD COLUMN IF NOT EXISTS organization_id UUID
REFERENCES organizations(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_layouts_organization
ON layouts(organization_id);

CREATE INDEX IF NOT EXISTS idx_check_results_organization
ON check_results(organization_id);

CREATE INDEX IF NOT EXISTS idx_production_orders_organization
ON production_orders(organization_id);

-- Replace prototype policies that allowed every authenticated user to see everything.
DROP POLICY IF EXISTS "auth_read_layouts" ON layouts;
DROP POLICY IF EXISTS "auth_write_layouts" ON layouts;
DROP POLICY IF EXISTS "auth_read_profiles" ON layout_profiles;
DROP POLICY IF EXISTS "auth_write_profiles" ON layout_profiles;
DROP POLICY IF EXISTS "auth_read_results" ON check_results;
DROP POLICY IF EXISTS "auth_write_results" ON check_results;
DROP POLICY IF EXISTS "auth_read_orders" ON production_orders;
DROP POLICY IF EXISTS "auth_write_orders" ON production_orders;

CREATE POLICY "read_accessible_layouts" ON layouts
FOR SELECT TO authenticated
USING (
  created_by = auth.uid()
  OR (organization_id IS NOT NULL AND is_organization_member(organization_id))
);

CREATE POLICY "create_accessible_layouts" ON layouts
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND has_product_capability('cloudSync')
  AND (organization_id IS NULL OR is_organization_member(organization_id))
);

CREATE POLICY "update_accessible_layouts" ON layouts
FOR UPDATE TO authenticated
USING (
  has_product_capability('cloudSync')
  AND (
    created_by = auth.uid()
    OR (organization_id IS NOT NULL AND has_organization_role(
      organization_id,
      ARRAY['owner','admin','technologist']
    ))
  )
)
WITH CHECK (
  has_product_capability('cloudSync')
  AND (
    created_by = auth.uid()
    OR (organization_id IS NOT NULL AND has_organization_role(
      organization_id,
      ARRAY['owner','admin','technologist']
    ))
  )
);

CREATE POLICY "delete_accessible_layouts" ON layouts
FOR DELETE TO authenticated
USING (
  has_product_capability('cloudSync')
  AND (
    created_by = auth.uid()
    OR (organization_id IS NOT NULL AND has_organization_role(
      organization_id,
      ARRAY['owner','admin']
    ))
  )
);

CREATE POLICY "read_accessible_layout_profiles" ON layout_profiles
FOR SELECT TO authenticated
USING (
  created_by = auth.uid()
  OR EXISTS (
    SELECT 1 FROM layouts
    WHERE layouts.id = layout_profiles.layout_id
      AND (
        layouts.created_by = auth.uid()
        OR is_organization_member(layouts.organization_id)
      )
  )
);

CREATE POLICY "create_accessible_layout_profiles" ON layout_profiles
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND has_product_capability('cloudSync')
  AND (
    layout_id IS NULL
    OR EXISTS (
      SELECT 1 FROM layouts
      WHERE layouts.id = layout_profiles.layout_id
        AND (
          layouts.created_by = auth.uid()
          OR is_organization_member(layouts.organization_id)
        )
    )
  )
);

CREATE POLICY "update_accessible_layout_profiles" ON layout_profiles
FOR UPDATE TO authenticated
USING (created_by = auth.uid() AND has_product_capability('cloudSync'))
WITH CHECK (created_by = auth.uid() AND has_product_capability('cloudSync'));

CREATE POLICY "delete_accessible_layout_profiles" ON layout_profiles
FOR DELETE TO authenticated
USING (created_by = auth.uid() AND has_product_capability('cloudSync'));

CREATE POLICY "read_accessible_check_results" ON check_results
FOR SELECT TO authenticated
USING (
  operator_id = auth.uid()
  OR (organization_id IS NOT NULL AND is_organization_member(organization_id))
);

CREATE POLICY "create_own_check_results" ON check_results
FOR INSERT TO authenticated
WITH CHECK (
  operator_id = auth.uid()
  AND has_product_capability('cloudSync')
  AND (organization_id IS NULL OR is_organization_member(organization_id))
);

CREATE POLICY "read_accessible_orders" ON production_orders
FOR SELECT TO authenticated
USING (
  created_by = auth.uid()
  OR (organization_id IS NOT NULL AND is_organization_member(organization_id))
);

CREATE POLICY "create_accessible_orders" ON production_orders
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND has_product_capability('cloudSync')
  AND (organization_id IS NULL OR is_organization_member(organization_id))
);

CREATE POLICY "update_accessible_orders" ON production_orders
FOR UPDATE TO authenticated
USING (
  has_product_capability('cloudSync')
  AND (
    created_by = auth.uid()
    OR (organization_id IS NOT NULL AND has_organization_role(
      organization_id,
      ARRAY['owner','admin','technologist']
    ))
  )
)
WITH CHECK (
  has_product_capability('cloudSync')
  AND (
    created_by = auth.uid()
    OR (organization_id IS NOT NULL AND has_organization_role(
      organization_id,
      ARRAY['owner','admin','technologist']
    ))
  )
);

CREATE POLICY "delete_accessible_orders" ON production_orders
FOR DELETE TO authenticated
USING (
  has_product_capability('cloudSync')
  AND (
    created_by = auth.uid()
    OR (organization_id IS NOT NULL AND has_organization_role(
      organization_id,
      ARRAY['owner','admin']
    ))
  )
);

-- Organization and collaboration policies.
DROP POLICY IF EXISTS "auth_read_organizations" ON organizations;
DROP POLICY IF EXISTS "auth_write_organizations" ON organizations;
DROP POLICY IF EXISTS "auth_read_org_members" ON organization_members;
DROP POLICY IF EXISTS "auth_write_org_members" ON organization_members;
DROP POLICY IF EXISTS "auth_read_chat_groups" ON chat_groups;
DROP POLICY IF EXISTS "auth_write_chat_groups" ON chat_groups;
DROP POLICY IF EXISTS "auth_read_chat_group_members" ON chat_group_members;
DROP POLICY IF EXISTS "auth_write_chat_group_members" ON chat_group_members;
DROP POLICY IF EXISTS "auth_read_chat_messages" ON chat_messages;
DROP POLICY IF EXISTS "auth_write_chat_messages" ON chat_messages;
DROP POLICY IF EXISTS "auth_read_check_assets" ON check_assets;
DROP POLICY IF EXISTS "auth_write_check_assets" ON check_assets;
DROP POLICY IF EXISTS "auth_read_check_comments" ON check_comments;
DROP POLICY IF EXISTS "auth_write_check_comments" ON check_comments;

CREATE POLICY "read_own_organizations" ON organizations
FOR SELECT TO authenticated
USING (created_by = auth.uid() OR is_organization_member(id));

CREATE POLICY "create_own_organization" ON organizations
FOR INSERT TO authenticated
WITH CHECK (created_by = auth.uid());

CREATE POLICY "update_managed_organization" ON organizations
FOR UPDATE TO authenticated
USING (
  created_by = auth.uid()
  OR has_organization_role(id, ARRAY['owner','admin'])
)
WITH CHECK (
  created_by = auth.uid()
  OR has_organization_role(id, ARRAY['owner','admin'])
);

CREATE POLICY "delete_owned_organization" ON organizations
FOR DELETE TO authenticated
USING (created_by = auth.uid() OR has_organization_role(id, ARRAY['owner']));

CREATE POLICY "read_organization_members" ON organization_members
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR is_organization_member(organization_id));

CREATE POLICY "create_organization_members" ON organization_members
FOR INSERT TO authenticated
WITH CHECK (
  has_organization_role(organization_id, ARRAY['owner','admin'])
  OR (
    user_id = auth.uid()
    AND role = 'owner'
    AND EXISTS (
      SELECT 1 FROM organizations
      WHERE organizations.id = organization_members.organization_id
        AND organizations.created_by = auth.uid()
    )
  )
);

CREATE POLICY "update_organization_members" ON organization_members
FOR UPDATE TO authenticated
USING (has_organization_role(organization_id, ARRAY['owner','admin']))
WITH CHECK (has_organization_role(organization_id, ARRAY['owner','admin']));

CREATE POLICY "delete_organization_members" ON organization_members
FOR DELETE TO authenticated
USING (has_organization_role(organization_id, ARRAY['owner','admin']));

CREATE POLICY "read_organization_chat_groups" ON chat_groups
FOR SELECT TO authenticated
USING (organization_id IS NOT NULL AND is_organization_member(organization_id));

CREATE POLICY "create_organization_chat_groups" ON chat_groups
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND has_product_capability('collaboration')
  AND organization_id IS NOT NULL
  AND is_organization_member(organization_id)
);

CREATE POLICY "update_organization_chat_groups" ON chat_groups
FOR UPDATE TO authenticated
USING (
  has_product_capability('collaboration')
  AND (
    created_by = auth.uid()
    OR has_organization_role(organization_id, ARRAY['owner','admin'])
  )
)
WITH CHECK (
  has_product_capability('collaboration')
  AND is_organization_member(organization_id)
);

CREATE POLICY "delete_organization_chat_groups" ON chat_groups
FOR DELETE TO authenticated
USING (
  has_product_capability('collaboration')
  AND (
    created_by = auth.uid()
    OR has_organization_role(organization_id, ARRAY['owner','admin'])
  )
);

CREATE POLICY "read_accessible_chat_group_members" ON chat_group_members
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM chat_groups
    WHERE chat_groups.id = chat_group_members.group_id
      AND is_organization_member(chat_groups.organization_id)
  )
);

CREATE POLICY "manage_accessible_chat_group_members" ON chat_group_members
FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM chat_groups
    WHERE chat_groups.id = chat_group_members.group_id
      AND (
        has_product_capability('collaboration')
        AND (
          chat_groups.created_by = auth.uid()
          OR has_organization_role(chat_groups.organization_id, ARRAY['owner','admin'])
        )
      )
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM chat_groups
    WHERE chat_groups.id = chat_group_members.group_id
      AND (
        has_product_capability('collaboration')
        AND (
          chat_groups.created_by = auth.uid()
          OR has_organization_role(chat_groups.organization_id, ARRAY['owner','admin'])
        )
      )
  )
);

CREATE POLICY "read_organization_messages" ON chat_messages
FOR SELECT TO authenticated
USING (
  organization_id IS NOT NULL
  AND is_organization_member(organization_id)
  AND NOT is_deleted
);

CREATE POLICY "create_organization_messages" ON chat_messages
FOR INSERT TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND has_product_capability('collaboration')
  AND organization_id IS NOT NULL
  AND is_organization_member(organization_id)
);

CREATE POLICY "update_own_messages" ON chat_messages
FOR UPDATE TO authenticated
USING (
  has_product_capability('collaboration')
  AND (
    sender_id = auth.uid()
    OR has_organization_role(organization_id, ARRAY['owner','admin'])
  )
)
WITH CHECK (
  has_product_capability('collaboration')
  AND is_organization_member(organization_id)
);

CREATE POLICY "delete_own_messages" ON chat_messages
FOR DELETE TO authenticated
USING (
  has_product_capability('collaboration')
  AND (
    sender_id = auth.uid()
    OR has_organization_role(organization_id, ARRAY['owner','admin'])
  )
);

CREATE POLICY "read_organization_check_assets" ON check_assets
FOR SELECT TO authenticated
USING (
  created_by = auth.uid()
  OR (organization_id IS NOT NULL AND is_organization_member(organization_id))
);

CREATE POLICY "create_organization_check_assets" ON check_assets
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND has_product_capability('cloudAssets')
  AND (organization_id IS NULL OR is_organization_member(organization_id))
);

CREATE POLICY "update_organization_check_assets" ON check_assets
FOR UPDATE TO authenticated
USING (
  has_product_capability('cloudAssets')
  AND (
    created_by = auth.uid()
    OR has_organization_role(organization_id, ARRAY['owner','admin'])
  )
)
WITH CHECK (
  has_product_capability('cloudAssets')
  AND (
    created_by = auth.uid()
    OR has_organization_role(organization_id, ARRAY['owner','admin'])
  )
);

CREATE POLICY "delete_organization_check_assets" ON check_assets
FOR DELETE TO authenticated
USING (
  has_product_capability('cloudAssets')
  AND (
    created_by = auth.uid()
    OR has_organization_role(organization_id, ARRAY['owner','admin'])
  )
);

CREATE POLICY "read_organization_check_comments" ON check_comments
FOR SELECT TO authenticated
USING (
  author_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM check_assets
    WHERE check_assets.id = check_comments.asset_id
      AND is_organization_member(check_assets.organization_id)
  )
);

CREATE POLICY "create_organization_check_comments" ON check_comments
FOR INSERT TO authenticated
WITH CHECK (
  author_id = auth.uid()
  AND has_product_capability('collaboration')
  AND (
    asset_id IS NULL
    OR EXISTS (
      SELECT 1 FROM check_assets
      WHERE check_assets.id = check_comments.asset_id
        AND (
          check_assets.created_by = auth.uid()
          OR is_organization_member(check_assets.organization_id)
        )
    )
  )
);

CREATE POLICY "update_own_check_comments" ON check_comments
FOR UPDATE TO authenticated
USING (author_id = auth.uid() AND has_product_capability('collaboration'))
WITH CHECK (author_id = auth.uid() AND has_product_capability('collaboration'));

CREATE POLICY "delete_own_check_comments" ON check_comments
FOR DELETE TO authenticated
USING (author_id = auth.uid() AND has_product_capability('collaboration'));

-- Keep the existing object paths working while restricting them to accessible rows.
DROP POLICY IF EXISTS "auth_upload_layouts" ON storage.objects;
DROP POLICY IF EXISTS "auth_read_layouts_storage" ON storage.objects;
DROP POLICY IF EXISTS "auth_upload_check_assets" ON storage.objects;
DROP POLICY IF EXISTS "auth_read_check_assets_storage" ON storage.objects;

CREATE POLICY "read_accessible_layout_objects" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'layouts'
  AND EXISTS (
    SELECT 1 FROM layouts
    WHERE layouts.id::text = split_part(storage.objects.name, '/', 1)
      AND (
        layouts.created_by = auth.uid()
        OR is_organization_member(layouts.organization_id)
      )
  )
);

CREATE POLICY "create_accessible_layout_objects" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'layouts'
  AND has_product_capability('cloudAssets')
  AND EXISTS (
    SELECT 1 FROM layouts
    WHERE layouts.id::text = split_part(storage.objects.name, '/', 1)
      AND (
        layouts.created_by = auth.uid()
        OR has_organization_role(
          layouts.organization_id,
          ARRAY['owner','admin','technologist']
        )
      )
  )
);

CREATE POLICY "update_accessible_layout_objects" ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'layouts'
  AND has_product_capability('cloudAssets')
  AND EXISTS (
    SELECT 1 FROM layouts
    WHERE layouts.id::text = split_part(storage.objects.name, '/', 1)
      AND (
        layouts.created_by = auth.uid()
        OR has_organization_role(
          layouts.organization_id,
          ARRAY['owner','admin','technologist']
        )
      )
  )
)
WITH CHECK (
  bucket_id = 'layouts'
  AND has_product_capability('cloudAssets')
);

CREATE POLICY "read_accessible_check_asset_objects" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'check-assets'
  AND (
    split_part(storage.objects.name, '/', 1) = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM organization_members
      WHERE organization_members.organization_id::text =
            split_part(storage.objects.name, '/', 1)
        AND organization_members.user_id = auth.uid()
    )
  )
);

CREATE POLICY "create_accessible_check_asset_objects" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'check-assets'
  AND has_product_capability('cloudAssets')
  AND (
    split_part(storage.objects.name, '/', 1) = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM organization_members
      WHERE organization_members.organization_id::text =
            split_part(storage.objects.name, '/', 1)
        AND organization_members.user_id = auth.uid()
    )
  )
);

CREATE POLICY "update_accessible_check_asset_objects" ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'check-assets'
  AND has_product_capability('cloudAssets')
  AND (
    split_part(storage.objects.name, '/', 1) = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM organization_members
      WHERE organization_members.organization_id::text =
            split_part(storage.objects.name, '/', 1)
        AND organization_members.user_id = auth.uid()
    )
  )
)
WITH CHECK (
  bucket_id = 'check-assets'
  AND has_product_capability('cloudAssets')
);

CREATE POLICY "delete_accessible_check_asset_objects" ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'check-assets'
  AND has_product_capability('cloudAssets')
  AND (
    split_part(storage.objects.name, '/', 1) = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM organization_members
      WHERE organization_members.organization_id::text =
            split_part(storage.objects.name, '/', 1)
        AND organization_members.user_id = auth.uid()
    )
  )
);
