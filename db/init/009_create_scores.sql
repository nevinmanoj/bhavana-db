CREATE TABLE scores (
    id BIGSERIAL PRIMARY KEY,
    entry_id BIGINT NOT NULL,
    judge_id BIGINT NOT NULL,
    criteria_id BIGINT NOT NULL,

    score NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_score_judge_entry_criteria
        UNIQUE (judge_id, entry_id, criteria_id),

    CONSTRAINT fk_entry
        FOREIGN KEY (entry_id)
        REFERENCES entries(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_judge
        FOREIGN KEY (judge_id)
        REFERENCES users(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_criteria
        FOREIGN KEY (criteria_id)
        REFERENCES event_criteria(id)
        ON DELETE CASCADE
);

CREATE OR REPLACE FUNCTION validate_score()
RETURNS TRIGGER AS $$
DECLARE
    event_status    TEXT;
    max_allowed     NUMERIC;
    is_judge        BOOLEAN;
    entry_event     BIGINT;
    criteria_event  BIGINT;
BEGIN
    -- fetch event status, max score, and criteria event_id in one query
    SELECT e.status, ec.max_score, ec.event_id
    INTO event_status, max_allowed, criteria_event
    FROM event_criteria ec
    JOIN events e ON e.id = ec.event_id
    WHERE ec.id = NEW.criteria_id;

    -- event must be open
    IF event_status IS DISTINCT FROM 'open' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0501', 
        MESSAGE = 'Cannot score when event status is not open';
    END IF;

    -- score within range
    IF NEW.score < 0 OR NEW.score > max_allowed THEN
        RAISE EXCEPTION 
        USING ERRCODE = 'P0502',
        MESSAGE = 'Score is out of range for event_criteria';
    END IF;

    -- judge belongs to event
    SELECT EXISTS (
        SELECT 1 FROM event_judges
        WHERE user_id = NEW.judge_id AND event_id = criteria_event
    ) INTO is_judge;

    IF NOT is_judge THEN
        RAISE EXCEPTION 
        USING ERRCODE = 'P0503',
        MESSAGE = 'User is not a judge for this event';
    END IF;

    -- entry belongs to same event as criteria
    SELECT event_id INTO entry_event FROM entries WHERE id = NEW.entry_id;

    IF entry_event IS DISTINCT FROM criteria_event THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0504',
        MESSAGE = 'Entry does not belong to the same event as criteria';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_score
BEFORE INSERT OR UPDATE ON scores
FOR EACH ROW
EXECUTE FUNCTION validate_score();