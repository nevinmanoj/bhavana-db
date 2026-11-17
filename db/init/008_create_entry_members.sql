CREATE TABLE entry_members (
    entry_id BIGINT NOT NULL,
    student_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_entry
        FOREIGN KEY (entry_id)
        REFERENCES entries(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_student
        FOREIGN KEY (student_id)
        REFERENCES students(id)
        ON DELETE CASCADE,

    CONSTRAINT uniq_entry_student
        UNIQUE (entry_id, student_id)
);


-- Junior (JR) is under 13 on 01-01-2027, i.e. born after 01-01-2014; everyone
-- else is Senior (SR). NULL when the DOB isn't recorded. The cutoff changes
-- every year: update it here and in the frontend's content file together.
CREATE OR REPLACE FUNCTION student_age_group(dob DATE)
RETURNS TEXT AS $$
    SELECT CASE
        WHEN dob IS NULL THEN NULL
        WHEN dob > DATE '2014-01-01' THEN 'JR'
        ELSE 'SR'
    END;
$$ LANGUAGE sql IMMUTABLE;


CREATE OR REPLACE FUNCTION validate_student_for_entry()
RETURNS TRIGGER AS $$
DECLARE
    event_category     TEXT;
    student_category   TEXT;
    event_age_group    TEXT;
    student_dob        DATE;
    entry_school_id     BIGINT;
    student_school_id  BIGINT;
    entry_event_id      BIGINT;
    already_in_entry    BOOLEAN;
    max_size           INTEGER;
    min_size           INTEGER;
    current_entry_size  INTEGER;
BEGIN
    -- fetch entry school and event info in one query
    SELECT t.school_id, e.category, e.age_group, t.event_id, e.max_members, e.min_members
    INTO entry_school_id, event_category, event_age_group, entry_event_id, max_size, min_size
    FROM entries t
    JOIN events e ON e.id = t.event_id
    WHERE t.id = NEW.entry_id;

    -- fetch student school and category
    SELECT school_id, category, dob
    INTO student_school_id, student_category, student_dob
    FROM students
    WHERE id = NEW.student_id;

    -- school match
    IF entry_school_id IS DISTINCT FROM student_school_id THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0404',
        MESSAGE = 'School of student does not match school of entry';
    END IF;

    -- category match (COMMON events accept students of every category)
    IF event_category <> 'COMMON'
       AND event_category IS DISTINCT FROM student_category THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0405',
        MESSAGE = 'Category of student does not match event category';
    END IF;

    -- age group match (BOTH events accept any age). A student with no DOB has
    -- no age group, so they fail this check for JR and SR events.
    IF event_age_group <> 'BOTH'
       AND event_age_group IS DISTINCT FROM student_age_group(student_dob) THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0412',
        MESSAGE = 'Age group of student does not match event age group';
    END IF;

    -- student already in another entry for the same event
    SELECT EXISTS (
        SELECT 1
        FROM entry_members tm
        JOIN entries t ON t.id = tm.entry_id
        WHERE tm.student_id = NEW.student_id
          AND t.event_id = entry_event_id
          AND tm.entry_id IS DISTINCT FROM NEW.entry_id  -- exclude current entry on UPDATE
    ) INTO already_in_entry;

    IF already_in_entry THEN
        RAISE EXCEPTION
        USING ERRCODE = 'P0406',
        MESSAGE = 'Student is already in an entry for this event';
    END IF;

    SELECT Count(*)
    INTO current_entry_size
    FROM entry_members tm
    WHERE tm.entry_id = NEW.entry_id;

    IF TG_OP = 'DELETE' THEN
        IF current_entry_size <= min_size THEN
            RAISE EXCEPTION
            USING ERRCODE = 'P0407',
            MESSAGE = 'Cannot remove student, violates min size requirement for event ';
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF current_entry_size  >= max_size THEN
            RAISE EXCEPTION
            USING ERRCODE = 'P0408',
            MESSAGE = 'Cannot add student, violates max size requirement for event ';
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' THEN
       RAISE EXCEPTION
        USING ERRCODE = 'P0409',
        MESSAGE = 'Cannot update entry_members, only insert or delete allowed';

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_student_for_entry
BEFORE INSERT OR UPDATE ON entry_members
FOR EACH ROW
EXECUTE FUNCTION validate_student_for_entry();
