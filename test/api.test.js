import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createApp } from '../src/server.js';
import { TripStore } from '../src/store.js';

const seed = JSON.parse(readFileSync(new URL('../data/trips.seed.json', import.meta.url), 'utf8'));
let server;
let base;

before(async () => {
  server = createApp(new TripStore({ trips: seed, utcOffset: '+05:00' }));
  await new Promise((resolve) => server.listen(0, resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

const get = (p) => fetch(base + p).then(async (r) => ({ status: r.status, body: await r.json() }));
const post = (body) =>
  fetch(base + '/api/trips', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  }).then(async (r) => ({ status: r.status, body: await r.json() }));

test('GET /api/trips?date= — поездки и сводка за день', async () => {
  const { status, body } = await get('/api/trips?date=2026-10-01');
  assert.equal(status, 200);
  assert.equal(body.date, '2026-10-01');
  assert.equal(body.trips.length, 8);
  assert.deepEqual(body.trips.slice(0, 2).map((t) => t.id), ['t1', 't2']);
  assert.equal(body.trips[0].net, 2040);
  assert.equal(body.trips[0].durationMinutes, 22);
  assert.equal(body.summary.revenue, 19550);
  assert.equal(body.summary.net, 16617.5);
});

test('GET /api/summary и /api/days', async () => {
  const summary = await get('/api/summary?date=2026-09-30');
  assert.equal(summary.body.summary.trips, 6);
  const days = await get('/api/days');
  assert.deepEqual(days.body.days.map((d) => d.date), ['2026-09-30', '2026-10-01', '2026-10-02']);
});

test('неверная дата — 400', async () => {
  for (const q of ['?date=2026-13-01', '?date=вчера']) {
    const { status, body } = await get('/api/trips' + q);
    assert.equal(status, 400);
    assert.equal(body.error.code, 'invalid_date');
  }
});

test('POST: создание, повтор — 200 без дубля, конфликт — 409', async () => {
  const trip = { id: 'api-1', start: '2026-10-05T10:00:00+05:00', end: '2026-10-05T10:20:00+05:00', amount: 1700, payment: 'cash', commission: 255 };

  const created = await post(trip);
  assert.equal(created.status, 201);
  assert.equal(created.body.created, true);

  const again = await post(trip);
  assert.equal(again.status, 200);
  assert.equal(again.body.duplicate, true);

  const day = await get('/api/trips?date=2026-10-05');
  assert.equal(day.body.trips.length, 1);
  assert.equal(day.body.summary.revenue, 1700);

  const conflict = await post({ ...trip, amount: 1800 });
  assert.equal(conflict.status, 409);
  assert.equal(conflict.body.error.code, 'id_conflict');
});

test('POST: ошибки валидации с перечнем полей', async () => {
  const { status, body } = await post({ start: '2026-10-05T12:00:00+05:00', end: '2026-10-05T11:00:00+05:00', amount: 0, payment: 'card', commission: 0 });
  assert.equal(status, 400);
  assert.equal(body.error.code, 'validation');
  assert.deepEqual(body.error.details.map((d) => d.field).sort(), ['amount', 'end']);

  const broken = await post('{"amount": ');
  assert.equal(broken.status, 400);
  assert.equal(broken.body.error.code, 'invalid_json');
});

test('CORS: preflight и заголовок в ответах API (для Flutter Web)', async () => {
  const preflight = await fetch(base + '/api/trips', {
    method: 'OPTIONS',
    headers: { Origin: 'http://localhost:5000', 'Access-Control-Request-Method': 'POST' },
  });
  assert.equal(preflight.status, 204);
  assert.match(preflight.headers.get('access-control-allow-methods'), /POST/);

  const res = await fetch(base + '/api/days');
  assert.equal(res.headers.get('access-control-allow-origin'), '*');
});
