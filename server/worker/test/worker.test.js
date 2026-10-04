import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHandler, tursoQuery } from '../src/index.js';

function fakeDatabase() {
  const players = new Map();
  const rounds = new Map();
  const query = async (_env, sql, args) => {
    if (sql.startsWith('INSERT OR IGNORE INTO players')) {
      if (!players.has(args[0])) players.set(args[0], { id: args[0], name: args[1] });
      return [];
    }
    if (sql.startsWith('SELECT id, name FROM players'))
      return players.has(args[0]) ? [players.get(args[0])] : [];
    if (sql.startsWith('INSERT OR IGNORE INTO rounds')) {
      if (!rounds.has(args[0])) rounds.set(args[0], {
        id: args[0], player_id: args[1], route: args[2], time_seconds: args[3],
        building_hits: args[4], car_hits: args[5], red_light_hits: args[6], score: args[7],
      });
      return [];
    }
    if (sql.startsWith('SELECT * FROM rounds'))
      return rounds.has(args[0]) ? [rounds.get(args[0])] : [];
    if (sql.startsWith('SELECT name, route, time_seconds')) {
      const best = new Map();
      for (const round of rounds.values()) {
        const old = best.get(round.player_id);
        if (!old || round.score > old.score) best.set(round.player_id, round);
      }
      return [...best.values()].sort((a, b) => b.score - a.score).slice(0, args[0])
        .map(r => ({ name: players.get(r.player_id).name, route: r.route,
          time_seconds: r.time_seconds, building_hits: r.building_hits,
          car_hits: r.car_hits, red_light_hits: r.red_light_hits, score: r.score }));
    }
    throw new Error(`Unexpected SQL: ${sql}`);
  };
  return { handler: createHandler(query), players, rounds };
}

const env = { EVW_ALLOWED_ORIGIN: 'https://example.github.io' };
const origin = 'https://example.github.io';
function request(path, method = 'GET', body, from = origin) {
  return new Request('https://api.example.test' + path, {
    method, headers: { Origin: from, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

test('preflight, origin restriction, and health', async () => {
  const { handler } = fakeDatabase();
  const preflight = await handler(request('/api/rounds', 'OPTIONS'), env);
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('Access-Control-Allow-Origin'), origin);
  assert.equal((await handler(request('/health'), env)).status, 200);
  assert.equal((await handler(request('/health', 'GET', undefined, 'https://other.test'), env)).status, 403);
});

test('score is recomputed, duplicate retry is safe, leaderboard keeps best run', async () => {
  const { handler, rounds } = fakeDatabase();
  const round = { id: 'a'.repeat(32), name: 'Chauffeur', route: 2, time_seconds: 101.5,
    building_hits: 1, car_hits: 2, red_light_hits: 1, score: 999999 };
  const first = await (await handler(request('/api/rounds', 'POST', round), env)).json();
  assert.deepEqual(first, { id: round.id, score: 7496, saved: true, duplicate: false });
  const retry = await (await handler(request('/api/rounds', 'POST', round), env)).json();
  assert.equal(retry.duplicate, true);
  assert.equal(rounds.size, 1);
  const conflict = await handler(request('/api/rounds', 'POST', { ...round, car_hits: 1 }), env);
  assert.equal(conflict.status, 400);
  const better = { ...round, id: 'b'.repeat(32), time_seconds: 50, building_hits: 0,
    car_hits: 0, red_light_hits: 0 };
  assert.equal((await handler(request('/api/rounds', 'POST', better), env)).status, 200);
  const list = await (await handler(request('/api/leaderboard?limit=10'), env)).json();
  assert.equal(list.scores.length, 1);
  assert.equal(list.scores[0].score, 9900);
});

test('invalid input is rejected without writing a round', async () => {
  const { handler, rounds } = fakeDatabase();
  for (const bad of [
    { id: 'x', name: 'A', route: 1, time_seconds: 10, building_hits: 0, car_hits: 0, red_light_hits: 0 },
    { id: 'c'.repeat(32), name: 'A', route: 4, time_seconds: 10, building_hits: 0, car_hits: 0, red_light_hits: 0 },
    { id: 'd'.repeat(32), name: 'A', route: 1, time_seconds: 0, building_hits: 0, car_hits: 0, red_light_hits: 0 },
  ]) assert.equal((await handler(request('/api/rounds', 'POST', bad), env)).status, 400);
  assert.equal(rounds.size, 0);
});

test('Hrana request keeps credentials server-side and decodes rows', async () => {
  const oldFetch = globalThis.fetch;
  try {
    globalThis.fetch = async (url, options) => {
      assert.equal(url, 'https://db.turso.io/v2/pipeline');
      assert.equal(options.headers.Authorization, 'Bearer server-secret');
      const body = JSON.parse(options.body);
      assert.deepEqual(body.requests[0].stmt.args, [{ type: 'integer', value: '2' }]);
      return new Response(JSON.stringify({ results: [{ type: 'ok', response: { result: {
        cols: [{ name: 'score' }], rows: [[{ type: 'integer', value: '9900' }]],
      } } }] }), { status: 200 });
    };
    const rows = await tursoQuery({ TURSO_DATABASE_URL: 'libsql://db.turso.io',
      TURSO_AUTH_TOKEN: 'server-secret' }, 'SELECT score LIMIT ?', [2]);
    assert.deepEqual(rows, [{ score: 9900 }]);
  } finally { globalThis.fetch = oldFetch; }
});
