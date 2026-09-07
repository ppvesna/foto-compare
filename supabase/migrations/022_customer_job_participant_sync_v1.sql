-- Keep customer representatives synchronized with active production jobs.
-- Being a participant does not publish the job: customer access still depends
-- on production_jobs.customer_access_status = 'shared'.

BEGIN;

CREATE OR REPLACE FUNCTION sync_customer_job_participants_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO production_job_participants(
      job_id,
      user_id,
      participant_type,
      added_by
    )
    SELECT
      job.id,
      NEW.user_id,
      'customer',
      NEW.linked_by
    FROM production_jobs AS job
    WHERE job.customer_id = NEW.customer_id
      AND job.customer_confirmed
      AND job.status = 'active'
    ON CONFLICT (job_id, user_id, participant_type) DO NOTHING;

    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    DELETE FROM production_job_participants AS participant
    USING production_jobs AS job
    WHERE participant.job_id = job.id
      AND participant.user_id = OLD.user_id
      AND participant.participant_type = 'customer'
      AND job.customer_id = OLD.customer_id;

    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS sync_customer_job_participants_v1
ON organization_customer_users;

CREATE TRIGGER sync_customer_job_participants_v1
AFTER INSERT OR DELETE
ON organization_customer_users
FOR EACH ROW
EXECUTE FUNCTION sync_customer_job_participants_v1();

-- Repair representatives linked after their customer's jobs were created.
INSERT INTO production_job_participants(
  job_id,
  user_id,
  participant_type,
  added_by
)
SELECT
  job.id,
  customer_user.user_id,
  'customer',
  customer_user.linked_by
FROM production_jobs AS job
JOIN organization_customer_users AS customer_user
  ON customer_user.customer_id = job.customer_id
WHERE job.customer_confirmed
  AND job.status = 'active'
ON CONFLICT (job_id, user_id, participant_type) DO NOTHING;

REVOKE ALL ON FUNCTION sync_customer_job_participants_v1()
FROM PUBLIC;

COMMIT;
