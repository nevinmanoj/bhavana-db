CREATE TABLE entries (
    id BIGSERIAL PRIMARY KEY,
    event_id BIGINT NOT NULL,
    school_id BIGINT NOT NULL,
    chest_number INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_event
        FOREIGN KEY (event_id)
        REFERENCES events(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_school
        FOREIGN KEY (school_id)
        REFERENCES schools(id)
        ON DELETE CASCADE
);

CREATE OR REPLACE FUNCTION validate_max_entries_per_school()
RETURNS TRIGGER AS $$
DECLARE
    max_entries INTEGER;
    entry_count INTEGER;
BEGIN
    IF TG_OP = 'UPDATE' AND
       NEW.event_id = OLD.event_id AND
       NEW.school_id = OLD.school_id THEN
        RETURN NEW;
    END IF;
    -- Lock event_id and school_id as immutable
    IF TG_OP = 'UPDATE' THEN
        IF NEW.event_id <> OLD.event_id THEN
            RAISE EXCEPTION USING ERRCODE = 'P0401',
            MESSAGE = 'Cannot change event_id for an entry';
        END IF;
        IF NEW.school_id <> OLD.school_id THEN
            RAISE EXCEPTION USING ERRCODE = 'P0402',
            MESSAGE = 'Cannot change school_id for an entry';
        END IF;
        RETURN NEW;
    END IF;

    SELECT max_entries_per_school
    INTO max_entries
    FROM events
    WHERE id = NEW.event_id;

    SELECT COUNT(*)
    INTO entry_count
    FROM entries
    WHERE school_id = NEW.school_id
      AND event_id = NEW.event_id
      AND id <> COALESCE(NEW.id, 0);

    IF entry_count >= max_entries THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0403',
        MESSAGE = FORMAT('School % has reached max entries allowed limit for event %', NEW.school_id, NEW.event_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_max_entries_per_school
BEFORE INSERT OR UPDATE ON entries
FOR EACH ROW
EXECUTE FUNCTION validate_max_entries_per_school();


CREATE OR REPLACE FUNCTION assign_chest_number()
RETURNS TRIGGER AS $$
DECLARE
    next_no INTEGER;
BEGIN
    -- Only auto assign if not manually provided
    IF NEW.chest_number IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT COALESCE(MAX(chest_number), 0) + 1
    INTO next_no
    FROM entries
    WHERE event_id = NEW.event_id;

    NEW.chest_number := next_no;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER assign_chest_number
BEFORE INSERT ON entries
FOR EACH ROW
EXECUTE FUNCTION assign_chest_number();

CREATE UNIQUE INDEX uniq_event_chest_number
ON entries(event_id, chest_number);
