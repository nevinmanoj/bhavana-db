CREATE TABLE results (
    id BIGSERIAL PRIMARY KEY,
    event_id BIGINT NOT NULL,
    entry_id BIGINT NOT NULL,
    school_id BIGINT NOT NULL,
    position INTEGER CHECK (position IS NULL OR position >= 1),  -- NULL = unscored, not ranked
    points NUMERIC(10,2),                                        -- NULL = unscored, or no mapping for this position
    total_score NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_result_event_entry
        UNIQUE (event_id, entry_id),

    CONSTRAINT unscored_has_no_points
        CHECK (position IS NOT NULL OR points IS NULL),

    CONSTRAINT fk_event
        FOREIGN KEY (event_id)
        REFERENCES events(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_entry
        FOREIGN KEY (entry_id)
        REFERENCES entries(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_school
        FOREIGN KEY (school_id)
        REFERENCES schools(id)
        ON DELETE CASCADE
);

CREATE INDEX idx_results_event  ON results(event_id);
CREATE INDEX idx_results_school ON results(school_id);

CREATE OR REPLACE FUNCTION validate_result()
RETURNS TRIGGER AS $$
DECLARE
    event_status TEXT;
BEGIN
    SELECT status INTO event_status
    FROM events WHERE id = NEW.event_id;

    IF event_status IS DISTINCT FROM 'finalized' THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0601',
        MESSAGE = FORMAT('Results can only be created once the event is finalized. Current status: %s', event_status);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_result
BEFORE INSERT ON results
FOR EACH ROW
EXECUTE FUNCTION validate_result();

CREATE OR REPLACE FUNCTION protect_results()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION
    USING ERRCODE = 'P0602',
    MESSAGE = 'Results are immutable and cannot be modified once written';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_results
BEFORE UPDATE ON results
FOR EACH ROW
EXECUTE FUNCTION protect_results();
