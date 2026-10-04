// Cloudflare Worker for the web MVP. Turso credentials exist only in Worker secrets.
const BASE_SCORE = 10_000;
const MAX_BODY_BYTES = 16_384;
const ID = /^[0-9a-f]{32}$/;

function fail(message, status = 400) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

function json(value, status = 200, cors = {}) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store', ...cors },
  });
}

function corsHeaders(request, env) {
  const origin = request.headers.get('Origin');
  const allowed = String(env.EVW_ALLOWED_ORIGIN || '').split(',').map(x => x.trim());
  if (!origin || !allowed.includes(origin)) return {};
  return { 'Access-Control-Allow-Origin': origin, 'Vary': 'Origin',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400' };
}

function tursoArg(value) {
  if (value === null) return { type: 'null' };
  if (Number.isInteger(value)) return { type: 'integer', value: String(value) };
  if (typeof value === 'number') return { type: 'float', value };
  return { type: 'text', value: String(value) };
}

function tursoValue(cell) {
  if (cell.type === 'null') return null;
  if (cell.type === 'integer' || cell.type === 'float') return Number(cell.value);
  return cell.value;
}

export async function tursoQuery(env, sql, args = []) {
  const url = String(env.TURSO_DATABASE_URL || '').replace(/^libsql:\/\//, 'https://').replace(/\/$/, '');
  if (!url.startsWith('https://') || !env.TURSO_AUTH_TOKEN) throw new Error('Missing Turso settings');
  const response = await fetch(`${url}/v2/pipeline`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${env.TURSO_AUTH_TOKEN}`,
      'Content-Type': 'application/json' },
    body: JSON.stringify({ baton: null, requests: [
      { type: 'execute', stmt: { sql, args: args.map(tursoArg), want_rows: true } },
      { type: 'close' },
    ] }),
  });
  if (!response.ok) throw new Error(`Turso HTTP ${response.status}`);
  const document = await response.json();
  const result = document.results?.[0];
  if (result?.type !== 'ok') throw new Error('Turso query failed');
  const data = result.response.result;
  return data.rows.map(row => Object.fromEntries(row.map((cell, i) =>
    [data.cols[i].name, tursoValue(cell)])));
}

function cleanName(value) {
  if (typeof value !== 'string') fail('Naam ontbreekt');
  const name = value.trim();
  if (!name || [...name].length > 24 || /[\x00-\x1f\x7f]/.test(name))
    fail('Naam moet 1 tot 24 leesbare tekens hebben');
  return name;
}

function boundedInt(value, label, min, max) {
  if (!Number.isInteger(value) || value < min || value > max)
    fail(`${label} moet tussen ${min} en ${max} liggen`);
  return value;
}

async function registerPlayer(query, input) {
  const name = cleanName(input);
  const key = name.toLocaleLowerCase('und');
  const bytes = new TextEncoder().encode(key);
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  const id = [...new Uint8Array(hash)].map(x => x.toString(16).padStart(2, '0')).join('').slice(0, 32);
  await query('INSERT OR IGNORE INTO players(id, name, name_key, created_at) VALUES (?, ?, ?, ?)',
    [id, name, key, new Date().toISOString()]);
  const rows = await query('SELECT id, name FROM players WHERE id = ?', [id]);
  return rows[0];
}

async function addRound(query, body) {
  if (typeof body.id !== 'string' || !ID.test(body.id)) fail('Ongeldig ronde-ID');
  const name = cleanName(body.name);
  const route = boundedInt(body.route, 'Route', 1, 3);
  const seconds = body.time_seconds;
  if (typeof seconds !== 'number' || !Number.isFinite(seconds) || seconds <= 0 || seconds > 7200)
    fail('Ongeldige rondetijd');
  const building = boundedInt(body.building_hits, 'Gebouwbotsingen', 0, 1000);
  const cars = boundedInt(body.car_hits, 'Autobotsingen', 0, 1000);
  const red = boundedInt(body.red_light_hits, 'Roodlichtovertredingen', 0, 1000);
  const score = Math.max(0, BASE_SCORE - Math.ceil(seconds) * 2
    - building * 400 - cars * 700 - red * 500);
  const player = await registerPlayer(query, name);
  const existing = await query('SELECT * FROM rounds WHERE id = ?', [body.id]);
  if (!existing.length) {
    await query('INSERT OR IGNORE INTO rounds(id, player_id, route, time_seconds, building_hits, car_hits, red_light_hits, score, completed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [body.id, player.id, route, seconds, building, cars, red, score, new Date().toISOString()]);
  }
  const saved = (await query('SELECT * FROM rounds WHERE id = ?', [body.id]))[0];
  if (!saved) throw new Error('Round insert failed');
  if (saved.player_id !== player.id || saved.route !== route ||
      saved.time_seconds !== seconds || saved.building_hits !== building ||
      saved.car_hits !== cars || saved.red_light_hits !== red)
    fail('Ronde-ID is al gebruikt met andere gegevens');
  return { id: body.id, score: saved.score, saved: true, duplicate: existing.length > 0 };
}

const LEADERBOARD_SQL = 'SELECT name, route, time_seconds, building_hits, car_hits, red_light_hits, score '
  + 'FROM (SELECT p.name, r.route, r.time_seconds, r.building_hits, r.car_hits, '
  + 'r.red_light_hits, r.score, ROW_NUMBER() OVER '
  + '(PARTITION BY r.player_id ORDER BY r.score DESC, r.time_seconds ASC) AS place '
  + 'FROM rounds r JOIN players p ON p.id = r.player_id) '
  + 'WHERE place = 1 ORDER BY score DESC, time_seconds ASC LIMIT ?';

async function bodyJson(request) {
  const declared = Number(request.headers.get('Content-Length'));
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) fail('Ongeldige verzoekgrootte');
  const text = await request.text();
  if (!text || new TextEncoder().encode(text).length > MAX_BODY_BYTES) fail('Ongeldige verzoekgrootte');
  let body;
  try { body = JSON.parse(text); } catch { fail('Ongeldige JSON'); }
  if (typeof body !== 'object' || body === null || Array.isArray(body)) fail('JSON-object verwacht');
  return body;
}

export function createHandler(queryFactory) {
  return async (request, env) => {
    const cors = corsHeaders(request, env);
    const origin = request.headers.get('Origin');
    if (origin && !cors['Access-Control-Allow-Origin'])
      return json({ error: 'Herkomst niet toegestaan' }, 403);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    const query = (sql, args = []) => queryFactory(env, sql, args);
    const url = new URL(request.url);
    try {
      if (request.method === 'GET' && url.pathname === '/health')
        return json({ ok: true }, 200, cors);
      if (request.method === 'POST' && url.pathname === '/api/players') {
        const body = await bodyJson(request);
        return json(await registerPlayer(query, body.name), 200, cors);
      }
      if (request.method === 'POST' && url.pathname === '/api/rounds')
        return json(await addRound(query, await bodyJson(request)), 200, cors);
      if (request.method === 'GET' && url.pathname === '/api/leaderboard') {
        const raw = url.searchParams.get('limit') ?? '10';
        if (!/^\d+$/.test(raw)) fail('Ongeldige limiet');
        const limit = Math.max(1, Math.min(Number(raw), 50));
        return json({ scores: await query(LEADERBOARD_SQL, [limit]) }, 200, cors);
      }
      const match = /^\/api\/players\/([0-9a-f]{32})$/.exec(url.pathname);
      if (request.method === 'GET' && match) {
        const player = (await query('SELECT id, name FROM players WHERE id = ?', [match[1]]))[0];
        return player ? json(player, 200, cors) : json({ error: 'Speler niet gevonden' }, 404, cors);
      }
      return json({ error: 'Niet gevonden' }, 404, cors);
    } catch (error) {
      if (error.status === 400) return json({ error: error.message }, 400, cors);
      console.error('Score API failed', error);
      return json({ error: 'Database tijdelijk niet beschikbaar' }, 503, cors);
    }
  };
}

export default { fetch: createHandler(tursoQuery) };
