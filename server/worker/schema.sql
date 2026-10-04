CREATE TABLE IF NOT EXISTS players (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    name_key TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS rounds (
    id TEXT PRIMARY KEY,
    player_id TEXT NOT NULL REFERENCES players(id),
    route INTEGER NOT NULL CHECK(route BETWEEN 1 AND 3),
    time_seconds REAL NOT NULL CHECK(time_seconds >= 0),
    building_hits INTEGER NOT NULL,
    car_hits INTEGER NOT NULL,
    red_light_hits INTEGER NOT NULL,
    score INTEGER NOT NULL,
    completed_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS rounds_rank ON rounds(score DESC, time_seconds ASC);
