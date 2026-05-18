CREATE TABLE event_judges (
    event_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_event
        FOREIGN KEY (event_id)
        REFERENCES events(id)
        ON DELETE CASCADE, 

    CONSTRAINT fk_judge
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE,

    CONSTRAINT uniq_event_judge
        UNIQUE (event_id, user_id)       

);


CREATE OR REPLACE FUNCTION check_event_judge_modification()
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
            USING ERRCODE = 'P0204', 
            MESSAGE = FORMAT('Judges can only be removed when event is DRAFT. Current status: %s', old_event_status);
        END IF;

        RETURN OLD;
    END IF;

    -------------------------------------------------
    -- INSERT
    -------------------------------------------------
    IF TG_OP = 'INSERT' THEN
        SELECT status INTO new_event_status
        FROM events WHERE id = NEW.event_id;

        IF new_event_status NOT IN ('draft','open','closed') THEN
            RAISE EXCEPTION
             USING ERRCODE = 'P0205', 
            MESSAGE = FORMAT('Judges can only be added when event is DRAFT, OPEN or CLOSED. Current status: %s', new_event_status);
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

        IF new_event_status NOT IN ('draft','open','closed') THEN
            RAISE EXCEPTION
            USING ERRCODE = 'P0206', 
            MESSAGE = FORMAT('Cannot move/update judge to event with status: %s', new_event_status);
        END IF;

        -- If event_id changed → treat as delete from old event
        IF NEW.event_id <> OLD.event_id THEN
            SELECT status INTO old_event_status
            FROM events WHERE id = OLD.event_id;

            IF old_event_status <> 'draft' THEN
                RAISE EXCEPTION
                USING ERRCODE = 'P0207', 
                MESSAGE = FORMAT('Cannot move judge FROM event with status: %s', old_event_status);
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_event_judge_modification
BEFORE INSERT OR UPDATE OR DELETE
ON event_judges
FOR EACH ROW
EXECUTE FUNCTION check_event_judge_modification();