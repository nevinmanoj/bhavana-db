-- Patch 001 — event lifecycle states + deferred chest-number draw
--
-- Mirrors the changes made to db/init/002, 003, 004, 007 and 010. Safe to run
-- more than once. Run this against the live database: db/init/*.sql only
-- executes on an empty data directory and will never reach a deployed one.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f 001_event_lifecycle_and_chest_draw.sql
--
-- Existing rows need no backfill — draft / open / closed / finalized all remain
-- legal values. Two things to know before running:
--   * an event sitting in 'draft' can now only advance to 'registration_open'
--   * entries that already hold a chest number are left untouched by the draw

BEGIN;

-- 1. Widen the status domain -------------------------------------------------

ALTER TABLE events DROP CONSTRAINT IF EXISTS events_status_check;
ALTER TABLE events ADD CONSTRAINT events_status_check
    CHECK (status IN (
        'draft',
        'registration_open',
        'registration_closed',
        'preparing',
        'open',
        'closed',
        'finalized'
    ));

-- 2. Lifecycle graph ---------------------------------------------------------
--   draft -> registration_open <-> registration_closed -> preparing
--         -> open <-> closed -> finalized

CREATE OR REPLACE FUNCTION protect_event_after_draft_or_finalized()
RETURNS TRIGGER AS $fn$
BEGIN
    IF OLD.status = 'finalized' THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0201',
        MESSAGE = 'Event is "finalized" and cannot be modified';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT (
            (OLD.status = 'draft'               AND NEW.status = 'registration_open')                  OR
            (OLD.status = 'registration_open'   AND NEW.status = 'registration_closed')                OR
            (OLD.status = 'registration_closed' AND NEW.status IN ('registration_open', 'preparing'))  OR
            (OLD.status = 'preparing'           AND NEW.status = 'open')                               OR
            (OLD.status = 'open'                AND NEW.status = 'closed')                             OR
            (OLD.status = 'closed'              AND NEW.status IN ('open', 'finalized'))
        ) THEN
            RAISE EXCEPTION
            USING ERRCODE = 'P0202',
            MESSAGE = FORMAT('Invalid event status transition: %s -> %s', OLD.status, NEW.status);
        END IF;
    END IF;

    IF OLD.status <> 'draft' THEN
        IF NEW.title        <> OLD.title OR
           NEW.category     <> OLD.category OR
           NEW.description  <> OLD.description OR
           NEW.max_entries_per_school    <> OLD.max_entries_per_school OR
           NEW.min_members <> OLD.min_members OR
           NEW.max_members <> OLD.max_members THEN

            RAISE EXCEPTION
            USING ERRCODE = 'P0203',
            MESSAGE = 'Event core fields cannot be edited after leaving "draft"';
        END IF;
    END IF;

    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

-- 3. 'preparing' becomes the setup window for judges, criteria and standings --

CREATE OR REPLACE FUNCTION check_event_judge_modification()
RETURNS TRIGGER AS $fn$
DECLARE
    new_event_status TEXT;
    old_event_status TEXT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        SELECT status INTO old_event_status FROM events WHERE id = OLD.event_id;
        IF old_event_status NOT IN ('draft','preparing') THEN
            RAISE EXCEPTION USING ERRCODE = 'P0204',
            MESSAGE = FORMAT('Judges can only be removed when event is DRAFT or PREPARING. Current status: %s', old_event_status);
        END IF;
        RETURN OLD;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT status INTO new_event_status FROM events WHERE id = NEW.event_id;
        IF new_event_status NOT IN ('draft','preparing','open','closed') THEN
            RAISE EXCEPTION USING ERRCODE = 'P0205',
            MESSAGE = FORMAT('Judges can only be added when event is DRAFT, PREPARING, OPEN or CLOSED. Current status: %s', new_event_status);
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        SELECT status INTO new_event_status FROM events WHERE id = NEW.event_id;
        IF new_event_status NOT IN ('draft','preparing','open','closed') THEN
            RAISE EXCEPTION USING ERRCODE = 'P0206',
            MESSAGE = FORMAT('Cannot move/update judge to event with status: %s', new_event_status);
        END IF;

        IF NEW.event_id <> OLD.event_id THEN
            SELECT status INTO old_event_status FROM events WHERE id = OLD.event_id;
            IF old_event_status NOT IN ('draft','preparing') THEN
                RAISE EXCEPTION USING ERRCODE = 'P0207',
                MESSAGE = FORMAT('Cannot move judge FROM event with status: %s', old_event_status);
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$fn$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_event_criteria_modification()
RETURNS TRIGGER AS $fn$
DECLARE
    new_event_status TEXT;
    old_event_status TEXT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        SELECT status INTO old_event_status FROM events WHERE id = OLD.event_id;
        IF old_event_status NOT IN ('draft','preparing') THEN
            RAISE EXCEPTION USING ERRCODE = 'P0208',
            MESSAGE = FORMAT('Event criteria can only be deleted when event is DRAFT or PREPARING. Current status: %s', old_event_status);
        END IF;
        RETURN OLD;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT status INTO new_event_status FROM events WHERE id = NEW.event_id;
        IF new_event_status NOT IN ('draft','preparing') THEN
            RAISE EXCEPTION USING ERRCODE = 'P0209',
            MESSAGE = FORMAT('Event criteria can only be added when event is DRAFT or PREPARING. Current status: %s', new_event_status);
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        SELECT status INTO new_event_status FROM events WHERE id = NEW.event_id;
        IF new_event_status NOT IN ('draft','preparing') THEN
            RAISE EXCEPTION USING ERRCODE = 'P0210',
            MESSAGE = FORMAT('Event criteria can only be edited when event is DRAFT or PREPARING. Current status: %s', new_event_status);
        END IF;

        IF NEW.event_id <> OLD.event_id THEN
            SELECT status INTO old_event_status FROM events WHERE id = OLD.event_id;
            IF old_event_status NOT IN ('draft','preparing') THEN
                RAISE EXCEPTION USING ERRCODE = 'P0211',
                MESSAGE = FORMAT('Cannot move criteria FROM event with status: %s', old_event_status);
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$fn$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_event_standing_modification()
RETURNS TRIGGER AS $fn$
DECLARE
    new_event_status TEXT;
    old_event_status TEXT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        SELECT status INTO old_event_status FROM events WHERE id = OLD.event_id;
        IF old_event_status NOT IN ('draft','preparing') THEN
            RAISE EXCEPTION USING ERRCODE = 'P0212',
            MESSAGE = FORMAT('Event standings can only be deleted when event is DRAFT or PREPARING. Current status: %s', old_event_status);
        END IF;
        RETURN OLD;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT status INTO new_event_status FROM events WHERE id = NEW.event_id;
        IF new_event_status NOT IN ('draft','preparing') THEN
            RAISE EXCEPTION USING ERRCODE = 'P0213',
            MESSAGE = FORMAT('Event standings can only be added when event is DRAFT or PREPARING. Current status: %s', new_event_status);
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        SELECT status INTO new_event_status FROM events WHERE id = NEW.event_id;
        IF new_event_status NOT IN ('draft','preparing') THEN
            RAISE EXCEPTION USING ERRCODE = 'P0214',
            MESSAGE = FORMAT('Event standings can only be edited when event is DRAFT or PREPARING. Current status: %s', new_event_status);
        END IF;

        IF NEW.event_id <> OLD.event_id THEN
            SELECT status INTO old_event_status FROM events WHERE id = OLD.event_id;
            IF old_event_status NOT IN ('draft','preparing') THEN
                RAISE EXCEPTION USING ERRCODE = 'P0215',
                MESSAGE = FORMAT('Cannot move standing FROM event with status: %s', old_event_status);
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$fn$ LANGUAGE plpgsql;

-- 4. Registration window for entries -----------------------------------------
-- The union of what every role may do; the narrower per-role window
-- (school admins: registration_open only) is enforced in the service.

CREATE OR REPLACE FUNCTION validate_entry_event_status()
RETURNS TRIGGER AS $fn$
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
$fn$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS validate_entry_event_status ON entries;
CREATE TRIGGER validate_entry_event_status
BEFORE INSERT ON entries
FOR EACH ROW
EXECUTE FUNCTION validate_entry_event_status();

-- 5. Chest numbers: deferred draw, advisory-locked allocation ----------------

-- Serializes chest-number allocation for one event. Callers WAIT for the lock
-- rather than racing to the same MAX+1 and losing on uniq_event_chest_number.
-- Released automatically on commit or rollback.
CREATE OR REPLACE FUNCTION lock_event_chest_numbers(p_event_id BIGINT)
RETURNS VOID AS $fn$
BEGIN
    -- Wait for a competing allocation rather than failing outright, but give up
    -- after 5s so a stuck transaction cannot pin a web request open forever.
    PERFORM set_config('lock_timeout', '5s', true);
    PERFORM pg_advisory_xact_lock(hashtext('entries.chest_number'), p_event_id::INT);
END;
$fn$ LANGUAGE plpgsql;

-- During registration the chest number is deliberately left NULL: the draw
-- happens once, for the whole event, on registration_closed -> preparing. Only
-- entries added after that draw allocate a number on the spot.
CREATE OR REPLACE FUNCTION assign_chest_number()
RETURNS TRIGGER AS $fn$
DECLARE
    ev_status TEXT;
    next_no   INTEGER;
BEGIN
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
$fn$ LANGUAGE plpgsql;

-- The draw. Numbers every unnumbered entry of the event in random order, so a
-- chest number reveals nothing about which school an entry came from. Runs
-- inside the caller's transaction and is idempotent.
CREATE OR REPLACE FUNCTION assign_event_chest_numbers(p_event_id BIGINT)
RETURNS INTEGER AS $fn$
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
$fn$ LANGUAGE plpgsql;

COMMIT;
