"""Create the MVP schema in Turso using server-only environment variables.

Run from the repository root after setting TURSO_DATABASE_URL and
TURSO_AUTH_TOKEN in your own shell. Never paste those values into source files.
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from score_api import SCHEMA, TursoStore  # noqa: E402


def main() -> None:
    store = TursoStore(os.getenv("TURSO_DATABASE_URL", ""),
                       os.getenv("TURSO_AUTH_TOKEN", ""))
    for statement in SCHEMA:
        store.execute(statement)
    if not any(row["name"] == "traffic_fines" for row in store.execute("PRAGMA table_info(rounds)")):
        store.execute("ALTER TABLE rounds ADD COLUMN traffic_fines INTEGER NOT NULL DEFAULT 0")
    print("Turso schema initialized")


if __name__ == "__main__":
    main()
