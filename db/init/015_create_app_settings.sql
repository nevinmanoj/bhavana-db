-- single row of admin-controlled switches
CREATE TABLE app_settings (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
    -- can schools sign up at /register?
    school_registration_open BOOLEAN NOT NULL DEFAULT FALSE,
    -- can school admins add, edit and delete students? admins always can
    student_registration_open BOOLEAN NOT NULL DEFAULT FALSE,
    -- can school admins add, edit and delete entries? admins always can
    entry_registration_open BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO app_settings DEFAULT VALUES;
