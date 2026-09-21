-- The only index that existed before this file was uniq_event_chest_number.
-- These support the finalize/ranking query and the leaderboard join across
-- scores x event_criteria x teams x schools, and general FK lookups.
CREATE INDEX idx_scores_team          ON scores(team_id);
CREATE INDEX idx_scores_criteria      ON scores(criteria_id);
CREATE INDEX idx_event_criteria_event ON event_criteria(event_id);
CREATE INDEX idx_teams_event          ON teams(event_id);
CREATE INDEX idx_teams_school         ON teams(school_id);
