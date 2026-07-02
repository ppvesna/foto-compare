-- ═══════════════════════════════════════════════════════════════
-- foto-compare: Lab fingerprints for layouts and check history
-- Выполнить в Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE layouts
ADD COLUMN IF NOT EXISTS lab_id TEXT,
ADD COLUMN IF NOT EXISTS lab_global_hash TEXT,
ADD COLUMN IF NOT EXISTS lab_zone_hash TEXT,
ADD COLUMN IF NOT EXISTS lab_detail_hash TEXT,
ADD COLUMN IF NOT EXISTS lab_signature JSONB;

ALTER TABLE check_results
ADD COLUMN IF NOT EXISTS reference_lab_id TEXT,
ADD COLUMN IF NOT EXISTS compare_lab_id TEXT,
ADD COLUMN IF NOT EXISTS lab_match_score REAL;

CREATE INDEX IF NOT EXISTS idx_layouts_lab_id ON layouts(lab_id);
CREATE INDEX IF NOT EXISTS idx_check_results_reference_lab_id
ON check_results(reference_lab_id);
