CREATE TABLE schools (
    id BIGSERIAL PRIMARY KEY,
    school_admin BIGINT UNIQUE,
    name TEXT NOT NULL,
    address TEXT NOT NULL,
    contact_name TEXT NOT NULL,
    contact_phone TEXT NOT NULL,
    contact_email TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'accepted'
        CHECK (status IN ('in_review', 'accepted')),
    principal_name TEXT NOT NULL,
    principal_phone TEXT NOT NULL,
    -- headcounts as submitted; informational only, nothing reads them
    participants_mc INT NOT NULL CHECK (participants_mc >= 0),
    participants_pc INT NOT NULL CHECK (participants_pc >= 0),
    participants_hc INT NOT NULL CHECK (participants_hc >= 0),
    non_participants INT NOT NULL CHECK (non_participants >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_school_admin
        FOREIGN KEY (school_admin)
        REFERENCES users(id)
        ON DELETE SET NULL
);

-- single row: is public school registration open?
CREATE TABLE school_registration (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
    is_open BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO school_registration DEFAULT VALUES;
