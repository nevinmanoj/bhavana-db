CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL
        CHECK (role IN ('admin', 'judge','school_admin')),
        -- TODO , host(manage events and entries)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
