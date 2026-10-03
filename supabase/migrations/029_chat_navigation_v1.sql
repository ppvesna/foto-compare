-- Scalable chat navigation: persistent unread state and job metadata.
-- Prerequisites: migrations 012, 016, 017, and 022.

BEGIN;

CREATE TABLE IF NOT EXISTS chat_thread_reads (
  group_id      UUID NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  last_read_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

ALTER TABLE chat_thread_reads ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS chat_thread_reads_user_idx
ON chat_thread_reads(user_id, last_read_at DESC);

CREATE INDEX IF NOT EXISTS chat_messages_unread_idx
ON chat_messages(group_id, created_at DESC)
WHERE NOT is_deleted;

CREATE OR REPLACE FUNCTION mark_chat_thread_read_v1(
  target_thread UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT can_access_chat_group_v1(target_thread) THEN
    RAISE EXCEPTION 'Chat access denied';
  END IF;

  INSERT INTO chat_thread_reads(group_id, user_id, last_read_at)
  VALUES (target_thread, auth.uid(), now())
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET last_read_at = EXCLUDED.last_read_at;
END;
$$;

DROP FUNCTION IF EXISTS list_accessible_chat_threads_v1();

CREATE FUNCTION list_accessible_chat_threads_v1()
RETURNS TABLE(
  thread_id UUID,
  thread_name TEXT,
  thread_kind TEXT,
  organization_id UUID,
  job_id UUID,
  updated_at TIMESTAMPTZ,
  customer_shared BOOLEAN,
  can_manage_customer_access BOOLEAN,
  job_status TEXT,
  customer_name TEXT,
  unread_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  RETURN QUERY
  SELECT
    chat.id,
    chat.name,
    chat.kind,
    chat.organization_id,
    chat.job_id,
    chat.updated_at,
    COALESCE(job.customer_access_status = 'shared', FALSE),
    CASE
      WHEN chat.job_id IS NULL THEN FALSE
      ELSE can_manage_production_job_customer_access_v1(chat.job_id)
    END,
    COALESCE(job.status, ''),
    COALESCE(customer.name, job.requested_customer_name, ''),
    COUNT(message.id) FILTER (
      WHERE message.sender_id IS DISTINCT FROM auth.uid()
    )
  FROM chat_groups AS chat
  LEFT JOIN production_jobs AS job
    ON job.id = chat.job_id
  LEFT JOIN organization_customers AS customer
    ON customer.id = job.customer_id
  LEFT JOIN chat_thread_reads AS read_state
    ON read_state.group_id = chat.id
   AND read_state.user_id = auth.uid()
  LEFT JOIN chat_messages AS message
    ON message.group_id = chat.id
   AND NOT message.is_deleted
   AND message.created_at > COALESCE(
     read_state.last_read_at,
     '-infinity'::TIMESTAMPTZ
   )
  WHERE can_access_chat_group_v1(chat.id)
    AND NOT chat.is_deleted
  GROUP BY
    chat.id,
    chat.name,
    chat.kind,
    chat.organization_id,
    chat.job_id,
    chat.updated_at,
    job.customer_access_status,
    job.status,
    job.requested_customer_name,
    customer.name
  ORDER BY chat.updated_at DESC;
END;
$$;

REVOKE ALL ON TABLE chat_thread_reads FROM PUBLIC;
REVOKE ALL ON TABLE chat_thread_reads FROM authenticated;
REVOKE ALL ON FUNCTION mark_chat_thread_read_v1(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION list_accessible_chat_threads_v1() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION mark_chat_thread_read_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION list_accessible_chat_threads_v1() TO authenticated;

COMMIT;
