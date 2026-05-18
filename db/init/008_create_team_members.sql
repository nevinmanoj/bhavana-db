CREATE TABLE team_members (
    team_id BIGINT NOT NULL,
    student_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_team
        FOREIGN KEY (team_id)
        REFERENCES teams(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_student
        FOREIGN KEY (student_id)
        REFERENCES students(id)
        ON DELETE CASCADE, 

    CONSTRAINT uniq_team_student
        UNIQUE (team_id, student_id)    
);


CREATE OR REPLACE FUNCTION validate_student_for_team()
RETURNS TRIGGER AS $$
DECLARE
    event_category    TEXT;
    student_category  TEXT;
    team_school_id    BIGINT;
    student_school_id BIGINT;
    team_event_id     BIGINT;
    already_in_team   BOOLEAN;
    max_size          INTEGER;
    min_size          INTEGER;
    current_team_size  INTEGER;
BEGIN
    -- fetch team school and event info in one query
    SELECT t.school_id, e.category, t.event_id, e.max_team_size, e.min_team_size
    INTO team_school_id, event_category, team_event_id, max_size, min_size
    FROM teams t
    JOIN events e ON e.id = t.event_id
    WHERE t.id = NEW.team_id;

    -- fetch student school and category
    SELECT school_id, category
    INTO student_school_id, student_category
    FROM students
    WHERE id = NEW.student_id;

    -- school match
    IF team_school_id IS DISTINCT FROM student_school_id THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0404', 
        MESSAGE = 'School of student does not match school of team';
    END IF;

    -- category match
    IF event_category IS DISTINCT FROM student_category THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0405', 
        MESSAGE = 'Category of student does not match event category';
    END IF;

    -- student already in another team for the same event
    SELECT EXISTS (
        SELECT 1
        FROM team_members tm
        JOIN teams t ON t.id = tm.team_id
        WHERE tm.student_id = NEW.student_id
          AND t.event_id = team_event_id
          AND tm.team_id IS DISTINCT FROM NEW.team_id  -- exclude current team on UPDATE
    ) INTO already_in_team;

    IF already_in_team THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0406', 
        MESSAGE = 'Student is already in a team for this event';
    END IF;

    SELECT Count(*)
    INTO current_team_size
    FROM team_members tm
    WHERE tm.team_id = NEW.team_id;

    IF TG_OP = 'DELETE' THEN
        IF current_team_size <= min_size THEN
            RAISE EXCEPTION
            USING ERRCODE = 'P0407', 
            MESSAGE = 'Cannot remove student, violates min size requirement for event ';
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF current_team_size  >= max_size THEN
            RAISE EXCEPTION
            USING ERRCODE = 'P0408', 
            MESSAGE = 'Cannot add student, violates max size requirement for event ';
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' THEN
       RAISE EXCEPTION
        USING ERRCODE = 'P0409', 
        MESSAGE = 'Cannot update team_members, only insert or delete allowed';
        
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_student_for_team
BEFORE INSERT OR UPDATE ON team_members
FOR EACH ROW
EXECUTE FUNCTION validate_student_for_team();