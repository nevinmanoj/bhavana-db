-- Locks every row that backs a finalized event's results.
--
-- 'finalized' is terminal (no edge leads out of it in the events lifecycle
-- trigger), and the event row itself is already frozen by
-- protect_event_after_draft_or_finalized (P0201) and
-- protect_finalized_event_delete (P0216). Judges, criteria and standings are
-- already locked by their own status triggers. This file closes the remaining
-- paths, all of which used to reach a finalized event through ON DELETE
-- CASCADE from a parent nobody guarded:
--
--   entries        UPDATE / DELETE        P0410
--   entry_members  INSERT/UPDATE/DELETE   P0411
--   scores         DELETE                 P0505  (INSERT/UPDATE already need 'open')
--   results        DELETE                 P0603  (UPDATE already blocked, P0602)
--   events         DELETE outside draft/preparing   P0217  (see below)
--
-- Deleting a school, a student or a user (judge) cascades into these tables,
-- and Postgres fires the child tables' row triggers during a cascade, so those
-- deletes are refused too whenever they would touch a finalized event. Rows of
-- events that are not finalized are unaffected.
--
-- The event's status is read FOR SHARE so a write racing a concurrent
-- finalize waits for it and then sees 'finalized', rather than slipping in
-- just before the results snapshot is taken.
--
-- Safe to run more than once, and against a live database: db/init/*.sql only
-- executes on an empty data directory and will never reach a deployed one.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f 013_lock_finalized_events.sql


-- entries ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION protect_finalized_entry()
RETURNS TRIGGER AS $$
DECLARE
    ev_status TEXT;
BEGIN
    SELECT status INTO ev_status FROM events WHERE id = OLD.event_id FOR SHARE;

    IF ev_status = 'finalized' THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0410',
        MESSAGE = FORMAT('Entry %s belongs to a finalized event and cannot be %s',
                         OLD.id, CASE TG_OP WHEN 'DELETE' THEN 'deleted' ELSE 'modified' END);
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS protect_finalized_entry ON entries;
CREATE TRIGGER protect_finalized_entry
BEFORE UPDATE OR DELETE ON entries
FOR EACH ROW
EXECUTE FUNCTION protect_finalized_entry();


-- entry_members ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION protect_finalized_entry_members()
RETURNS TRIGGER AS $$
DECLARE
    member_entry_id BIGINT;
    ev_status       TEXT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        member_entry_id := OLD.entry_id;
    ELSE
        member_entry_id := NEW.entry_id;
    END IF;

    -- When the parent entry is itself being deleted (cascade), its row is
    -- already gone and this finds nothing - that delete was vetted by
    -- protect_finalized_entry above.
    SELECT e.status INTO ev_status
    FROM entries t
    JOIN events e ON e.id = t.event_id
    WHERE t.id = member_entry_id
    FOR SHARE OF e;

    IF ev_status = 'finalized' THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0411',
        MESSAGE = FORMAT('Entry %s belongs to a finalized event; its members cannot be changed',
                         member_entry_id);
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS protect_finalized_entry_members ON entry_members;
CREATE TRIGGER protect_finalized_entry_members
BEFORE INSERT OR UPDATE OR DELETE ON entry_members
FOR EACH ROW
EXECUTE FUNCTION protect_finalized_entry_members();


-- scores ----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION protect_finalized_score_delete()
RETURNS TRIGGER AS $$
DECLARE
    ev_status TEXT;
BEGIN
    -- Resolved through the criterion, which outlives the score in every
    -- cascade that can reach a finalized event (criteria themselves are
    -- locked outside draft/preparing).
    SELECT e.status INTO ev_status
    FROM event_criteria ec
    JOIN events e ON e.id = ec.event_id
    WHERE ec.id = OLD.criteria_id
    FOR SHARE OF e;

    IF ev_status = 'finalized' THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0505',
        MESSAGE = 'Scores of a finalized event cannot be deleted';
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS protect_finalized_score_delete ON scores;
CREATE TRIGGER protect_finalized_score_delete
BEFORE DELETE ON scores
FOR EACH ROW
EXECUTE FUNCTION protect_finalized_score_delete();


-- events ----------------------------------------------------------------------

-- An event may only be deleted during setup (draft / preparing); finalized is
-- already refused by protect_finalized_event_delete (P0216). This has to be
-- explicit: the judge/criteria/standing triggers look like they would refuse
-- the cascade, but by the time ON DELETE CASCADE reaches them the event row is
-- gone, their status lookup returns NULL, and they let it through - so without
-- this a closed event with a full set of scores could be deleted outright.
CREATE OR REPLACE FUNCTION protect_event_delete_outside_setup()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status NOT IN ('draft', 'preparing', 'finalized') THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0217',
        MESSAGE = FORMAT('Events can only be deleted while in draft or preparing. Current status: %s', OLD.status);
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS protect_event_delete_outside_setup ON events;
CREATE TRIGGER protect_event_delete_outside_setup
BEFORE DELETE ON events
FOR EACH ROW
EXECUTE FUNCTION protect_event_delete_outside_setup();


-- results ---------------------------------------------------------------------

-- Results only ever exist for finalized events (trg_validate_result) and
-- finalized is terminal, so every results row is permanently locked.
CREATE OR REPLACE FUNCTION protect_results_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION
    USING ERRCODE = 'P0603',
    MESSAGE = 'Results are immutable and cannot be deleted once written';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_protect_results_delete ON results;
CREATE TRIGGER trg_protect_results_delete
BEFORE DELETE ON results
FOR EACH ROW
EXECUTE FUNCTION protect_results_delete();
