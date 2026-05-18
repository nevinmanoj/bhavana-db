CREATE TABLE teams (
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

CREATE OR REPLACE FUNCTION validate_max_teams_per_school()
RETURNS TRIGGER AS $$
DECLARE
    max_teams INTEGER;
    team_count INTEGER;
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
            MESSAGE = 'Cannot change event_id for a team';
        END IF;
        IF NEW.school_id <> OLD.school_id THEN
            RAISE EXCEPTION USING ERRCODE = 'P0402', 
            MESSAGE = 'Cannot change school_id for a team';
        END IF;
        RETURN NEW;
    END IF;

    SELECT max_teams_per_school
    INTO max_teams
    FROM events
    WHERE id = NEW.event_id;

    SELECT COUNT(*)
    INTO team_count
    FROM teams
    WHERE school_id = NEW.school_id
      AND event_id = NEW.event_id
      AND id <> COALESCE(NEW.id, 0);

    IF team_count >= max_teams THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0403', 
        MESSAGE = FORMAT('School % has reached max teams allowed limit for event %', NEW.school_id, NEW.event_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_max_teams_per_school
BEFORE INSERT OR UPDATE ON teams
FOR EACH ROW
EXECUTE FUNCTION validate_max_teams_per_school();


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
    FROM teams
    WHERE event_id = NEW.event_id;

    NEW.chest_number := next_no;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER assign_chest_number
BEFORE INSERT ON teams
FOR EACH ROW
EXECUTE FUNCTION assign_chest_number();

CREATE UNIQUE INDEX uniq_event_chest_number
ON teams(event_id, chest_number);