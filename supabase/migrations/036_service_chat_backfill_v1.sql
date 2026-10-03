-- Backfill the writable service conversation for organizations that existed
-- before ensure_default_chat_threads_v1 started creating it on sign-in.

BEGIN;

INSERT INTO chat_groups(
  organization_id, name, kind, created_by, scope_key
)
SELECT
  organization.id,
  'Служебные',
  'service',
  NULL,
  'organization:' || organization.id::TEXT || ':service'
FROM organizations AS organization
ON CONFLICT (scope_key) WHERE scope_key IS NOT NULL
DO UPDATE SET
  name = EXCLUDED.name,
  kind = 'service',
  is_deleted = FALSE,
  archived_at = NULL;

COMMIT;
