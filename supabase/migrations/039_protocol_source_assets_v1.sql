-- Preserve the exact source images used by an organization inspection.
-- Files remain private in trimatrix-assets and inherit the existing job RLS.

BEGIN;

ALTER TABLE cloud_check_protocols
ADD COLUMN IF NOT EXISTS reference_asset_id TEXT,
ADD COLUMN IF NOT EXISTS reference_object_path TEXT,
ADD COLUMN IF NOT EXISTS sample_asset_id TEXT,
ADD COLUMN IF NOT EXISTS sample_object_path TEXT;

COMMENT ON COLUMN cloud_check_protocols.reference_object_path IS
  'Private provider path for the exact reference image used by this protocol.';
COMMENT ON COLUMN cloud_check_protocols.sample_object_path IS
  'Private provider path for the exact sample image used by this protocol.';

COMMIT;
