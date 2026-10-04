"""Small score API. Turso credentials stay on this server, never in Godot."""

from __future__ import annotations

import hashlib
import json
import math
import os
import sqlite3
import threading
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

BASE_SCORE = 10_000
POINTS_PER_SECOND = 2
BUILDING_PENALTY = 400
CAR_PENALTY = 700
RED_LIGHT_PENALTY = 500
MAX_BODY_BYTES = 16_384

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS players ("
    "id TEXT PRIMARY KEY, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE, "
    "created_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS rounds ("
    "id TEXT PRIMARY KEY, player_id TEXT NOT NULL REFERENCES players(id), "
    "route INTEGER NOT NULL CHECK(route BETWEEN 1 AND 3), "
    "time_seconds REAL NOT NULL CHECK(time_seconds >= 0), "
    "building_hits INTEGER NOT NULL, car_hits INTEGER NOT NULL, "
    "red_light_hits INTEGER NOT NULL, score INTEGER NOT NULL, completed_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS rounds_rank ON rounds(score DESC, time_seconds ASC)",
)


class SQLiteStore:
    """Local development store with the same SQL as the Turso adapter."""

    def __init__(self, path: str):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys = ON")
        self.lock = threading.Lock()

    def execute(self, sql: str, args: tuple = ()) -> list[dict]:
        with self.lock, self.db:
            cursor = self.db.execute(sql, args)
            return [dict(row) for row in cursor.fetchall()] if cursor.description else []


class TursoStore:
    """Turso/libSQL Hrana HTTP v2 adapter; one stateless pipeline per statement."""

    def __init__(self, database_url: str, auth_token: str):
        if not database_url or not auth_token:
            raise ValueError("TURSO_DATABASE_URL and TURSO_AUTH_TOKEN are required")
        self.url = database_url.replace("libsql://", "https://", 1).rstrip("/")
        if not self.url.startswith("https://"):
            raise ValueError("Turso URL must use libsql:// or https://")
        self.token = auth_token

    @staticmethod
    def _arg(value: object) -> dict:
        if value is None:
            return {"type": "null"}
        if isinstance(value, int):
            return {"type": "integer", "value": str(value)}
        if isinstance(value, float):
            return {"type": "float", "value": value}
        return {"type": "text", "value": str(value)}

    @staticmethod
    def _value(cell: dict) -> object:
        if cell["type"] == "null":
            return None
        if cell["type"] == "integer":
            return int(cell["value"])
        if cell["type"] == "float":
            return float(cell["value"])
        return cell.get("value")

    def execute(self, sql: str, args: tuple = ()) -> list[dict]:
        body = json.dumps({
            "baton": None,
            "requests": [
                {"type": "execute", "stmt": {
                    "sql": sql, "args": [self._arg(value) for value in args],
                    "want_rows": True,
                }},
                {"type": "close"},
            ],
        }).encode()
        request = urllib.request.Request(
            self.url + "/v2/pipeline", body,
            {"Authorization": "Bearer " + self.token,
             "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            document = json.load(response)
        result = document["results"][0]
        if result["type"] != "ok":
            raise RuntimeError("Turso query failed: " + result["error"]["message"])
        statement = result["response"]["result"]
        names = [column["name"] for column in statement["cols"]]
        return [dict(zip(names, map(self._value, row))) for row in statement["rows"]]


class ScoreService:
    def __init__(self, store):
        self.store = store
        for sql in SCHEMA:
            store.execute(sql)

    @staticmethod
    def clean_name(value: object) -> str:
        if not isinstance(value, str):
            raise ValueError("Naam ontbreekt")
        name = value.strip()
        if not name or len(name) > 24 or any(ord(char) < 32 for char in name):
            raise ValueError("Naam moet 1 tot 24 leesbare tekens hebben")
        return name

    def player(self, value: object) -> dict:
        name = self.clean_name(value)
        key = name.casefold()
        player_id = hashlib.sha256(key.encode()).hexdigest()[:32]
        self.store.execute(
            "INSERT OR IGNORE INTO players(id, name, name_key, created_at) VALUES (?, ?, ?, ?)",
            (player_id, name, key, datetime.now(timezone.utc).isoformat()),
        )
        return self.store.execute("SELECT id, name FROM players WHERE id = ?", (player_id,))[0]

    def get_player(self, player_id: str) -> dict | None:
        if len(player_id) != 32 or any(c not in "0123456789abcdef" for c in player_id):
            return None
        rows = self.store.execute("SELECT id, name FROM players WHERE id = ?", (player_id,))
        return rows[0] if rows else None

    @staticmethod
    def _int(value: object, label: str, minimum: int, maximum: int) -> int:
        if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
            raise ValueError(f"{label} moet tussen {minimum} en {maximum} liggen")
        return value

    def add_round(self, body: dict) -> dict:
        run_id = body.get("id")
        if not isinstance(run_id, str) or len(run_id) != 32 or any(c not in "0123456789abcdef" for c in run_id):
            raise ValueError("Ongeldig ronde-ID")
        name = self.clean_name(body.get("name"))
        route = self._int(body.get("route"), "Route", 1, 3)
        seconds = body.get("time_seconds")
        if isinstance(seconds, bool) or not isinstance(seconds, (int, float)) or not math.isfinite(seconds) or not 0 < seconds <= 7200:
            raise ValueError("Ongeldige rondetijd")
        building = self._int(body.get("building_hits"), "Gebouwbotsingen", 0, 1000)
        cars = self._int(body.get("car_hits"), "Autobotsingen", 0, 1000)
        red = self._int(body.get("red_light_hits"), "Roodlichtovertredingen", 0, 1000)
        score = max(0, BASE_SCORE - math.ceil(seconds) * POINTS_PER_SECOND
                    - building * BUILDING_PENALTY - cars * CAR_PENALTY
                    - red * RED_LIGHT_PENALTY)
        player = self.player(name)
        existing = self.store.execute("SELECT * FROM rounds WHERE id = ?", (run_id,))
        if existing:
            old = existing[0]
            if (old["player_id"], old["route"], old["time_seconds"], old["building_hits"],
                old["car_hits"], old["red_light_hits"]) != (
                    player["id"], route, seconds, building, cars, red):
                raise ValueError("Ronde-ID is al gebruikt met andere gegevens")
            return {"id": run_id, "score": old["score"], "saved": True, "duplicate": True}
        self.store.execute(
            "INSERT OR IGNORE INTO rounds(id, player_id, route, time_seconds, building_hits, "
            "car_hits, red_light_hits, score, completed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (run_id, player["id"], route, seconds, building, cars, red, score,
             datetime.now(timezone.utc).isoformat()),
        )
        stored = self.store.execute("SELECT * FROM rounds WHERE id = ?", (run_id,))[0]
        if (stored["player_id"], stored["route"], stored["time_seconds"], stored["building_hits"],
            stored["car_hits"], stored["red_light_hits"]) != (
                player["id"], route, seconds, building, cars, red):
            raise ValueError("Ronde-ID is al gebruikt met andere gegevens")
        return {"id": run_id, "score": stored["score"], "saved": True, "duplicate": False}

    def leaderboard(self, limit: int = 10) -> list[dict]:
        limit = max(1, min(limit, 50))
        return self.store.execute(
            "SELECT name, route, time_seconds, building_hits, car_hits, red_light_hits, score "
            "FROM (SELECT p.name, r.route, r.time_seconds, r.building_hits, r.car_hits, "
            "r.red_light_hits, r.score, ROW_NUMBER() OVER "
            "(PARTITION BY r.player_id ORDER BY r.score DESC, r.time_seconds ASC) AS place "
            "FROM rounds r JOIN players p ON p.id = r.player_id) "
            "WHERE place = 1 ORDER BY score DESC, time_seconds ASC LIMIT ?", (limit,),
        )


def make_handler(service: ScoreService):
    class Handler(BaseHTTPRequestHandler):
        def _json(self, status: int, value: dict) -> None:
            encoded = json.dumps(value, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

        def do_GET(self) -> None:
            parsed = urlparse(self.path)
            try:
                if parsed.path == "/health":
                    self._json(200, {"ok": True})
                elif parsed.path == "/api/leaderboard":
                    raw = parse_qs(parsed.query).get("limit", ["10"])[0]
                    self._json(200, {"scores": service.leaderboard(int(raw))})
                elif parsed.path.startswith("/api/players/"):
                    player = service.get_player(parsed.path.removeprefix("/api/players/"))
                    if player:
                        self._json(200, player)
                    else:
                        self._json(404, {"error": "Speler niet gevonden"})
                else:
                    self._json(404, {"error": "Niet gevonden"})
            except ValueError as error:
                self._json(400, {"error": str(error)})
            except Exception:
                self._json(503, {"error": "Database tijdelijk niet beschikbaar"})

        def do_POST(self) -> None:
            if self.path not in ("/api/players", "/api/rounds"):
                self._json(404, {"error": "Niet gevonden"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= MAX_BODY_BYTES:
                    raise ValueError("Ongeldige verzoekgrootte")
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    raise ValueError("JSON-object verwacht")
                if self.path == "/api/players":
                    self._json(200, service.player(body.get("name")))
                else:
                    self._json(200, service.add_round(body))
            except (ValueError, json.JSONDecodeError) as error:
                self._json(400, {"error": str(error)})
            except Exception:
                self._json(503, {"error": "Database tijdelijk niet beschikbaar"})

    return Handler


def main() -> None:
    local_path = os.getenv("EVW_LOCAL_DB_PATH")
    if local_path:
        Path(local_path).parent.mkdir(parents=True, exist_ok=True)
        store = SQLiteStore(local_path)
    else:
        store = TursoStore(os.getenv("TURSO_DATABASE_URL", ""), os.getenv("TURSO_AUTH_TOKEN", ""))
    service = ScoreService(store)
    host = os.getenv("EVW_API_HOST", "127.0.0.1")
    port = int(os.getenv("EVW_API_PORT", "8787"))
    server = ThreadingHTTPServer((host, port), make_handler(service))
    print(f"EVW score API listening on {host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
