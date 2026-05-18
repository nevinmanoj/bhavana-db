CREATE TABLE schools (
    id BIGSERIAL PRIMARY KEY,
    school_admin BIGINT UNIQUE,
    name TEXT NOT NULL,
    address TEXT NOT NULL,
    contact_name TEXT NOT NULL,
    contact_phone TEXT NOT NULL,
    contact_email TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_school_admin
        FOREIGN KEY (school_admin)
        REFERENCES users(id)
        ON DELETE SET NULL
);