import json
import io
import re
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

import score_api
from score_api import SQLiteStore, ScoreService, TursoStore, make_handler


class ScoreApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.service = ScoreService(SQLiteStore(str(Path(self.temp.name) / "scores.db")))
        self.http = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.service))
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()
        self.url = f"http://127.0.0.1:{self.http.server_port}"

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.url + path, data,
                                         {"Content-Type": "application/json"})
        with urllib.request.urlopen(request) as response:
            return json.load(response)

    def round(self, id, name="Chauffeur", route=1, time=120.2):
        return {"id": id, "name": name, "route": route, "time_seconds": time,
                "building_hits": 1, "car_hits": 1, "red_light_hits": 1,
                "score": 999999}

    def test_players_rounds_and_rankings(self):
        player = self.request("/api/players", {"name": "  Chauffeur  "})
        self.assertEqual(player["name"], "Chauffeur")
        self.assertEqual(self.request("/api/players/" + player["id"]), player)
        run = self.round("a" * 32)
        saved = self.request("/api/rounds", run)
        self.assertEqual(saved["score"], 8158)  # Server ignores submitted score.
        self.assertTrue(self.request("/api/rounds", run)["duplicate"])
        self.assertEqual(len(self.request("/api/leaderboard")["scores"]), 1)
        self.request("/api/rounds", self.round("b" * 32, time=90.0))
        self.assertEqual(len(self.request("/api/leaderboard")["scores"]), 1)
        self.assertEqual(self.request("/api/leaderboard")["scores"][0]["score"], 8220)
        self.request("/api/rounds", self.round("c" * 32, name="Tweede", route=3))
        self.assertEqual(len(self.request("/api/leaderboard")["scores"]), 2)

    def test_turso_wire_format_and_result_decode(self):
        response = {"results": [{"type": "ok", "response": {"result": {
            "cols": [{"name": "score"}],
            "rows": [[{"type": "integer", "value": "8158"}]],
        }}}]}
        sent = []

        def fake_urlopen(request, timeout):
            sent.append(request)
            return io.BytesIO(json.dumps(response).encode())

        with patch("score_api.urllib.request.urlopen", fake_urlopen):
            rows = TursoStore("libsql://example.turso.io", "server-secret").execute(
                "SELECT ? AS score", (8158,))
        self.assertEqual(rows, [{"score": 8158}])
        self.assertEqual(sent[0].full_url, "https://example.turso.io/v2/pipeline")
        statement = json.loads(sent[0].data)["requests"][0]["stmt"]
        self.assertEqual(statement["args"], [{"type": "integer", "value": "8158"}])

    def test_server_and_game_scoring_match(self):
        source = (Path(__file__).resolve().parents[1] / "scripts/game_session.gd").read_text()
        for name in ("BASE_SCORE", "POINTS_PER_SECOND", "BUILDING_PENALTY",
                     "CAR_PENALTY", "RED_LIGHT_PENALTY"):
            match = re.search(rf"const {name} := (\d+)", source)
            self.assertIsNotNone(match, name)
            self.assertEqual(int(match.group(1)), getattr(score_api, name), name)

    def test_invalid_and_conflicting_rounds(self):
        invalid = self.round("x" * 32)
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.request("/api/rounds", invalid)
        self.assertEqual(error.exception.code, 400)
        first = self.round("d" * 32)
        self.request("/api/rounds", first)
        changed = first | {"route": 2}
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.request("/api/rounds", changed)
        self.assertEqual(error.exception.code, 400)
        self.assertEqual(len(self.request("/api/leaderboard")["scores"]), 1)


if __name__ == "__main__":
    unittest.main()
