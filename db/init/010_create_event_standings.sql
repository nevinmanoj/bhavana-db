CREATE TABLE event_standings (
    id BIGSERIAL PRIMARY KEY,
    event_id BIGINT NOT NULL,
    position INTEGER NOT NULL CHECK (position >= 1),
    points NUMERIC(10,2) NOT NULL CHECK (points >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_event_standing_position
        UNIQUE (event_id, position),

    CONSTRAINT fk_event
        FOREIGN KEY (event_id)
        REFERENCES events(id)
        ON DELETE CASCADE
);

CREATE INDEX idx_event_standings_event ON event_standings(event_id);

CREATE OR REPLACE FUNCTION check_event_standing_modification()
RETURNS TRIGGER AS $$
DECLARE
    new_event_status TEXT;
    old_event_status TEXT;
BEGIN
    -------------------------------------------------
    -- DELETE
    -------------------------------------------------
    IF TG_OP = 'DELETE' THEN
        SELECT status INTO old_event_status
        FROM events WHERE id = OLD.event_id;

        IF old_event_status <> 'draft' THEN
            RAISE EXCEPTION
            USING ERRCODE = 'P0212',
            MESSAGE = FORMAT('Event standings can only be deleted when event is DRAFT. Current status: %s', old_event_status);
        END IF;

        RETURN OLD;
    END IF;

    -------------------------------------------------
    -- INSERT
    -------------------------------------------------
    IF TG_OP = 'INSERT' THEN
        SELECT status INTO new_event_status
        FROM events WHERE id = NEW.event_id;

          IF new_event_status <> 'draft' THEN
            RAISE EXCEPTION
            USING ERRCODE = 'P0213',
            MESSAGE = FORMAT('Event standings can only be added when event is DRAFT. Current status: %s', new_event_status);
        END IF;
        RETURN NEW;
    END IF;

    -------------------------------------------------
    -- UPDATE
    -------------------------------------------------
    IF TG_OP = 'UPDATE' THEN

        -- Check target event (insert part)
        SELECT status INTO new_event_status
        FROM events WHERE id = NEW.event_id;

        IF new_event_status <> 'draft' THEN
            RAISE EXCEPTION
            USING ERRCODE = 'P0214',
            MESSAGE = FORMAT('Event standings can only be edited when event is DRAFT. Current status: %s', new_event_status);
        END IF;

        -- If event_id changed → treat as delete from old event
        IF NEW.event_id <> OLD.event_id THEN
            SELECT status INTO old_event_status
            FROM events WHERE id = OLD.event_id;

            IF old_event_status <> 'draft' THEN
                RAISE EXCEPTION
                USING ERRCODE = 'P0215',
                MESSAGE = FORMAT('Cannot move standing FROM event with status: %s', old_event_status);
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_event_standing_modification
BEFORE INSERT OR UPDATE OR DELETE
ON event_standings
FOR EACH ROW
EXECUTE FUNCTION check_event_standing_modification();
