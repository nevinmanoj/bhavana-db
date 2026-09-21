CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    min_team_size INTEGER NOT NULL,
    max_team_size INTEGER NOT NULL,
    max_teams_per_school INTEGER NOT NULL,
    status TEXT NOT NULL
        CHECK (status IN ('draft', 'open', 'closed', 'finalized')),
        -- TODO PHASE 2 'registration_open', 'registration_closed' and if needed 'preparing'
    category TEXT NOT NULL
        CHECK (category IN ('HC', 'MC', 'PC')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_team_range
        CHECK (min_team_size <= max_team_size)
);

CREATE OR REPLACE FUNCTION protect_event_after_draft_or_finalized()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'finalized' THEN
        RAISE EXCEPTION 
        USING ERRCODE = 'P0201', 
        MESSAGE = 'Event is "finalized" and cannot be modified';
    END IF;
    -- If already left draft previously
    IF OLD.status <> 'draft' THEN
        
        -- Prevent going back to draft
        IF NEW.status = 'draft' THEN
            RAISE EXCEPTION USING ERRCODE = 'P0202', 
            MESSAGE = 'Cannot move event back to "draft"';
        END IF;

        -- Prevent editing protected fields
        IF NEW.title        <> OLD.title OR
           NEW.category     <> OLD.category OR
           NEW.description  <> OLD.description OR
           NEW.max_teams_per_school    <> OLD.max_teams_per_school OR
           NEW.min_team_size <> OLD.min_team_size OR
           NEW.max_team_size <> OLD.max_team_size THEN
           
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