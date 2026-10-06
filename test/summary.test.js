import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { summarize } from '../src/summary.js';
import { TripStore } from '../src/store.js';

const seed = JSON.parse(readFileSync(new URL('../data/trips.seed.json', import.meta.url), 'utf8'));

const trip = (over) => ({
  id: 'x',
  start: '2026-10-01T08:00:00+05:00',
  end: '2026-10-01T08:30:00+05:00',
  amount: 1000,
  payment: 'card',
  commission: 150,
  ...over,
});

test('сводка по двум поездкам из примера в задании', () => {
  const s = summarize([
    trip({ id: 't1', start: '2026-10-01T08:10:00+05:00', end: '2026-10-01T08:32:00+05:00', amount: 2400, payment: 'card', commission: 360 }),
    trip({ id: 't2', start: '2026-10-01T09:05:00+05:00', end: '2026-10-01T09:20:00+05:00', amount: 1500, payment: 'cash', commission: 225 }),
  ]);
  assert.deepEqual(s, {
    trips: 2,
    revenue: 3900,
    commission: 585,
    net: 3315,
    byPayment: {
      cash: { trips: 1, revenue: 1500, commission: 225, net: 1275 },
      card: { trips: 1, revenue: 2400, commission: 360, net: 2040 },
    },
    serviceBalance: 1815, // 2400 по карте − 585 комиссии
    driveMinutes: 37,
  });
});

test('пустой день — нули, а не NaN', () => {
  const zero = { trips: 0, revenue: 0, commission: 0, net: 0 };
  assert.deepEqual(summarize([]), {
    ...zero,
    byPayment: { cash: zero, card: zero },
    serviceBalance: 0,
    driveMinutes: 0,
  });
});

test('копейки складываются без ошибок плавающей точки', () => {
  const s = summarize([
    trip({ amount: 0.1, commission: 0.01 }),
    trip({ amount: 0.2, commission: 0.02 }),
  ]);
  assert.equal(s.revenue, 0.3); // а не 0.30000000000000004
  assert.equal(s.commission, 0.03);
  assert.equal(s.net, 0.27);
});

test('только наличные: сервису должны комиссию, баланс отрицательный', () => {
  const s = summarize([trip({ payment: 'cash', amount: 2000, commission: 300 })]);
  assert.equal(s.byPayment.card.trips, 0);
  assert.equal(s.byPayment.cash.net, 1700);
  assert.equal(s.serviceBalance, -300);
});

test('сводка за 1 октября по данным из примера, ночная поездка относится к дню начала', () => {
  const store = new TripStore({ trips: seed, utcOffset: '+05:00' });
  const s = summarize(store.byDate('2026-10-01'));
  assert.equal(s.trips, 8); // включая t8 23:40–00:05
  assert.equal(s.revenue, 19550);
  assert.equal(s.commission, 2932.5);
  assert.equal(s.net, 16617.5);
  assert.deepEqual(s.byPayment.cash, { trips: 4, revenue: 7050, commission: 1057.5, net: 5992.5 });
  assert.deepEqual(s.byPayment.card, { trips: 4, revenue: 12500, commission: 1875, net: 10625 });
  assert.equal(s.serviceBalance, 9567.5);
  assert.equal(s.driveMinutes, 213);

  assert.ok(store.byDate('2026-10-02').every((t) => t.id !== 't8'));
});

test('день определяется в поясе водителя, а не по UTC', () => {
  // 01:30 по Алматы = 20:30 UTC предыдущего дня
  const store = new TripStore({
    utcOffset: '+05:00',
    trips: [trip({ id: 'night', start: '2026-10-01T01:30:00+05:00', end: '2026-10-01T01:50:00+05:00' })],
  });
  assert.equal(store.byDate('2026-10-01').length, 1);
  assert.equal(store.byDate('2026-09-30').length, 0);

  // то же время, записанное в UTC, попадает в тот же день
  const utc = new TripStore({
    utcOffset: '+05:00',
    trips: [trip({ id: 'night', start: '2026-09-30T20:30:00Z', end: '2026-09-30T20:50:00Z' })],
  });
  assert.equal(utc.byDate('2026-10-01').length, 1);
});
