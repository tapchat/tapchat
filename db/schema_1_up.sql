CREATE TABLE connections (
  cid          INTEGER  NOT NULL PRIMARY KEY AUTOINCREMENT,
  name         TEXT     NOT NULL,
  server       TEXT     NOT NULL,
  port         INTEGER  NOT NULL,
  is_ssl       BOOLEAN  NOT NULL,
  nick         TEXT     NOT NULL,
  user_name    TEXT     NOT NULL,
  real_name    TEXT     NOT NULL,
  auto_connect BOOLEAN  NOT NULL DEFAULT 1,
  created_at   DATETIME DEFAULT (strftime('%s','now')),
  updated_at   DATETIME
);

CREATE TABLE buffers (
  bid           INTEGER  NOT NULL PRIMARY KEY AUTOINCREMENT,
  cid           INTEGER  NOT NULL,
  name          TEXT     NOT NULL,
  type          TEXT     NOT NULL,
  archived      BOOLEAN  NOT NULL DEFAULT 0,
  auto_join     BOOLEAN,
  last_seen_eid INTEGER,
  created_at    DATETIME DEFAULT (strftime('%s','now')),
  updated_at    DATETIME
);

CREATE TABLE events (
  eid        INTEGER  NOT NULL PRIMARY KEY AUTOINCREMENT,
  bid        INTEGER  NOT NULL,
  data       TEXT     NOT NULL,
  created_at DATETIME DEFAULT (strftime('%s','now'))
);

CREATE INDEX connections_name ON connections (name);

CREATE INDEX events_bid ON events (bid);