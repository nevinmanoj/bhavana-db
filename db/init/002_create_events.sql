CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    min_members INTEGER NOT NULL,
    max_members INTEGER NOT NULL,
    max_entries_per_school INTEGER NOT NULL,
    status TEXT NOT NULL
        CHECK (status IN (
            'draft',
            'registration_open',
            'registration_closed',
            'preparing',
            'open',
            'closed',
            'finalized'
        )),
    category TEXT NOT NULL
        CHECK (category IN ('HC', 'MC', 'PC')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_member_range
        CHECK (min_members <= max_members)
);

-- Lifecycle:
--   draft -> registration_open <-> registration_closed -> preparing
--         -> open <-> closed -> finalized
--
-- Chest numbers are drawn in one batch on registration_closed -> preparing
-- (see assign_event_chest_numbers in 007_create_entries.sql), so the entry
-- list is stable by the time numbers exist.
CREATE OR REPLACE FUNCTION protect_event_after_draft_or_finalized()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'finalized' THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0201',
        MESSAGE = 'Event is "finalized" and cannot be modified';
    END IF;

    -- Enforce the lifecycle graph. This also subsumes the old "cannot go back
    -- to draft" rule: no edge leads into draft.
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

    -- If already left draft previously, core fields are frozen
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER protect_event_after_draft_or_finalized
BEFORE UPDATE ON events
FOR EACH ROW
EXECUTE FUNCTION protect_event_after_draft_or_finalized();

CREATE OR REPLACE FUNCTION protect_finalized_event_delete()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'finalized' THEN
        RAISE EXCEPTION USING ERRCODE = 'P0216',
        MESSAGE = 'Event is "finalized" and cannot be deleted';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER protect_finalized_event_delete
BEFORE DELETE ON events
FOR EACH ROW
EXECUTE FUNCTION protect_finalized_event_delete();
