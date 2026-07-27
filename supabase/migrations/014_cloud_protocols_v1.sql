-- Trimatrix private cloud protocol metadata.
-- Preview binaries stay in the private trimatrix-assets bucket from migration 013.
-- Organization sharing is intentionally not enabled in this stage.

BEGIN;

CREATE TABLE IF NOT EXISTS cloud_check_protocols (
  owner_user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  protocol_id         TEXT NOT NULL,
  organization_id     UUID REFERENCES organizations(id) ON DELETE SET NULL,
  job_id              TEXT NOT NULL DEFAULT '',
  job_number          TEXT NOT NULL DEFAULT '',
  protocol_data       JSONB NOT NULL,
  preview_asset_id    TEXT,
  protocol_created_at TIMESTAMPTZ NOT NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_user_id, protocol_id),
  CONSTRAINT cloud_check_protocol_id_check
    CHECK (length(trim(protocol_id)) BETWEEN 1 AND 160),
  CONSTRAINT cloud_check_protocol_data_check
    CHECK (jsonb_typeof(protocol_data) = 'object')
);

CREATE INDEX IF NOT EXISTS cloud_check_protocols_owner_created_idx
ON cloud_check_protocols(owner_user_id, protocol_created_at DESC);

CREATE INDEX IF NOT EXISTS cloud_check_protocols_organization_job_idx
ON cloud_check_protocols(organization_id, job_id, protocol_created_at DESC)
WHERE organization_id IS NOT NULL;

ALTER TABLE cloud_check_protocols ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE cloud_check_protocols FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE cloud_check_protocols
TO authenticated;

DROP POLICY IF EXISTS cloud_check_protocols_select_own
ON cloud_check_protocols;
DROP POLICY IF EXISTS cloud_check_protocols_insert_own
ON cloud_check_protocols;
DROP POLICY IF EXISTS cloud_check_protocols_update_own
ON cloud_check_protocols;
DROP POLICY IF EXISTS cloud_check_protocols_delete_own
ON cloud_check_protocols;

CREATE POLICY cloud_check_protocols_select_own
ON cloud_check_protocols
FOR SELECT
TO authenticated
USING (owner_user_id = auth.uid());

CREATE POLICY cloud_check_protocols_insert_own
ON cloud_check_protocols
FOR INSERT
TO authenticated
WITH CHECK (owner_user_id = auth.uid());

CREATE POLICY cloud_check_protocols_update_own
ON cloud_check_protocols
FOR UPDATE
TO authenticated
USING (owner_user_id = auth.uid())
WITH CHECK (owner_user_id = auth.uid());

CREATE POLICY cloud_check_protocols_delete_own
ON cloud_check_protocols
FOR DELETE
TO authenticated
USING (owner_user_id = auth.uid());

COMMIT;
