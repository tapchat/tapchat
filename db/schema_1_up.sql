CREATE TABLE IF NOT EXISTS connections (
    cid        INTEGER  NOT NULL PRIMARY KEY AUTOINCREMENT,
    name       TEXT     NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME
);

CREATE TABLE IF NOT EXISTS buffers (
    bid           INTEGER  NOT NULL PRIMARY KEY AUTOINCREMENT,
    cid           INTEGER  NOT NULL,
    name          TEXT     NOT NULL,
    last_seen_eid INTEGER,
    created_at    DATETIME NOT NULL,
    updated_at    DATETIME
);

CREATE TABLE IF NOT EXISTS events (
    eid        INTEGER  NOT NULL PRIMARY KEY AUTOINCREMENT, 
    bid        INTEGER  NOT NULL,
    data       TEXT     NOT NULL,
    created_at DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS connections_name ON connections (name);
CREATE INDEX IF NOT EXISTS events_bid ON events (bid);
