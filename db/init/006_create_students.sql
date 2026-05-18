CREATE TABLE students (
    id BIGSERIAL PRIMARY KEY,
    school_id BIGINT NOT NULL,
    name TEXT NOT NULL,
    age INTEGER NOT NULL,
    category TEXT NOT NULL
        CHECK (category IN ('HC', 'MC', 'PC')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

        CONSTRAINT fk_school
            FOREIGN KEY (school_id)
            REFERENCES schools(id)
            ON DELETE CASCADE 
);