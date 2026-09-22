CREATE TABLE entries (
    id BIGSERIAL PRIMARY KEY,
    event_id BIGINT NOT NULL,
    school_id BIGINT NOT NULL,
    -- NULL until the chest-number draw runs on registration_closed -> preparing
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
        MESSAGE = FORMAT('School %s has reached max entries allowed limit for event %s', NEW.school_id, NEW.event_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_max_entries_per_school
BEFORE INSERT OR UPDATE ON entries
FOR EACH ROW
EXECUTE FUNCTION validate_max_entries_per_school();


-- Entries may only be registered while the event is in a registration-capable
-- state. This is the union of what every role may do; the narrower per-role
-- window (school admins: registration_open only) is enforced in the service.
CREATE OR REPLACE FUNCTION validate_entry_event_status()
RETURNS TRIGGER AS $$
DECLARE
    ev_status TEXT;
BEGIN
    SELECT status INTO ev_status FROM events WHERE id = NEW.event_id FOR SHARE;

    IF ev_status NOT IN ('registration_open', 'registration_closed', 'preparing', 'open', 'closed') THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0409',
        MESSAGE = FORMAT('Entries cannot be registered while the event is %s', ev_status);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_entry_event_status
BEFORE INSERT ON entries
FOR EACH ROW
EXECUTE FUNCTION validate_entry_event_status();


-- Serializes chest-number allocation for one event. Callers WAIT for the lock
-- rather than racing to the same MAX+1 and losing on uniq_event_chest_number.
-- Advisory locks are held for the duration of the transaction and released on
-- commit or rollback; the (tag, event_id) pair keeps this from blocking any
-- other work that touches the event.
CREATE OR REPLACE FUNCTION lock_event_chest_numbers(p_event_id BIGINT)
RETURNS VOID AS $$
BEGIN
    -- Wait for a competing allocation rather than failing outright, but give up
    -- after 5s so a stuck transaction cannot pin a web request open forever.
    PERFORM set_config('lock_timeout', '5s', true);
    PERFORM pg_advisory_xact_lock(hashtext('entries.chest_number'), p_event_id::INT);
END;
$$ LANGUAGE plpgsql;


-- During registration the chest number is deliberately left NULL: the draw
-- happens once, for the whole event, on registration_closed -> preparing. Only
-- entries added after that draw (admin-only, late additions) allocate a number
-- on the spot.
CREATE OR REPLACE FUNCTION assign_chest_number()
RETURNS TRIGGER AS $$
DECLARE
    ev_status TEXT;
    next_no   INTEGER;
BEGIN
    -- Only auto assign if not manually provided
    IF NEW.chest_number IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- FOR SHARE: if a draw is committing right now, wait for it and then read
    -- the status it left behind, so this row is either part of the draw or
    -- numbered by the fallback below - never silently skipped by both.
    SELECT status INTO ev_status FROM events WHERE id = NEW.event_id FOR SHARE;

    IF ev_status IN ('draft', 'registration_open', 'registration_closed') THEN
        RETURN NEW;
    END IF;

    PERFORM lock_event_chest_numbers(NEW.event_id);

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


-- The draw. Numbers every unnumbered entry of the event in random order, so a
-- chest number reveals nothing about which school an entry came from. Runs
-- inside the caller's transaction on registration_closed -> preparing, and is
-- idempotent: entries that already hold a number are left untouched.
CREATE OR REPLACE FUNCTION assign_event_chest_numbers(p_event_id BIGINT)
RETURNS INTEGER AS $$
DECLARE
    base_no  INTEGER;
    assigned INTEGER;
BEGIN
    PERFORM lock_event_chest_numbers(p_event_id);

    SELECT COALESCE(MAX(chest_number), 0)
    INTO base_no
    FROM entries
    WHERE event_id = p_event_id;

    WITH draw AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY random()) AS n
        FROM entries
        WHERE event_id = p_event_id
          AND chest_number IS NULL
    )
    UPDATE entries e
    SET chest_number = base_no + draw.n
    FROM draw
    WHERE e.id = draw.id;

    GET DIAGNOSTICS assigned = ROW_COUNT;
    RETURN assigned;
END;
$$ LANGUAGE plpgsql;

CREATE UNIQUE INDEX uniq_event_chest_number
ON entries(event_id, chest_number);
