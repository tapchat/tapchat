CREATE TABLE users (
    uid         INTEGER  NOT NULL PRIMARY KEY AUTOINCREMENT,
    name        TEXT     NOT NULL UNIQUE,
    password    TEXT     NOT NULL,
    is_admin    BOOLEAN  NOT NULL DEFAULT 0,
    push_id     TEXT     NOT NULL,
    push_key    TEXT     NOT NULL,
    created_at  DATETIME DEFAULT (strftime('%s','now')),
    updated_at  DATETIME
);

CREATE INDEX users_name ON users (name);

ALTER TABLE connections ADD COLUMN uid INTEGER;
ALTER TABLE buffers ADD COLUMN uid INTEGER;

UPDATE connections SET uid = 1;
UPDATE buffers SET uid = 1;

--- ALTER TABLE connections ALTER COLUMN uid NOT NULL;
--- ALTER TABLE buffers ALTER COLUMN uid NOT NULL;