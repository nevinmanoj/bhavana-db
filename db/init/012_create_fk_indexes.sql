-- The only index that existed before this file was uniq_event_chest_number.
-- These support the finalize/ranking query and the leaderboard join across
-- scores x event_criteria x entries x schools, and general FK lookups.
CREATE INDEX idx_scores_entry         ON scores(entry_id);
CREATE INDEX idx_scores_criteria      ON scores(criteria_id);
CREATE INDEX idx_event_criteria_event ON event_criteria(event_id);
CREATE INDEX idx_entries_event        ON entries(event_id);
CREATE INDEX idx_entries_school       ON entries(school_id);
