-- Read-only checks before applying 006_organization_access_v2.sql.
-- Missing organization tables are valid before the first 006 installation.

SELECT
  to_regclass('public.user_profiles') AS user_profiles,
  to_regclass('public.organizations') AS organizations,
  to_regclass('public.organization_members') AS organization_members;

DO $$
DECLARE
  item RECORD;
BEGIN
  IF to_regclass('public.organization_members') IS NULL THEN
    RAISE NOTICE
      'organization_members is absent; migration 006 will create it';
    RETURN;
  END IF;

  FOR item IN EXECUTE
    'SELECT role, count(*) AS members
       FROM organization_members
      GROUP BY role
      ORDER BY role'
  LOOP
    RAISE NOTICE 'role=% members=%', item.role, item.members;
  END LOOP;

  FOR item IN EXECUTE
    'SELECT organization_id, count(*) AS owner_count
       FROM organization_members
      WHERE role = ''owner''
      GROUP BY organization_id
     HAVING count(*) <> 1'
  LOOP
    RAISE WARNING
      'organization=% has owner_count=%',
      item.organization_id,
      item.owner_count;
  END LOOP;

  IF to_regclass('public.user_profiles') IS NOT NULL THEN
    FOR item IN EXECUTE
      'SELECT member.organization_id, member.user_id, member.role
         FROM organization_members AS member
         LEFT JOIN user_profiles AS profile ON profile.user_id = member.user_id
        WHERE profile.user_id IS NULL'
    LOOP
      RAISE WARNING
        'member without profile: organization=% user=% role=%',
        item.organization_id,
        item.user_id,
        item.role;
    END LOOP;
  END IF;
END $$;

SELECT
  schemaname,
  tablename,
  policyname
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('organizations', 'organization_members')
ORDER BY tablename, policyname;

-- Required before 006: user_profiles exists.
-- Valid first-install state: organizations and organization_members are NULL.
-- If organization tables already exist, resolve duplicate-owner and missing-profile
-- warnings before applying 006.
