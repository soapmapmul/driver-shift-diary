import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { ConflictError, TripStore } from '../src/store.js';
import { ValidationError } from '../src/trips.js';

const t1 = {
  id: 't1',
  start: '2026-10-01T08:10:00+05:00',
  end: '2026-10-01T08:32:00+05:00',
  amount: 2400,
  payment: 'card',
  commission: 360,
};

test('повторная отправка той же поездки (тот же id) не создаёт дубль', async () => {
  const store = new TripStore();
  assert.equal((await store.add(t1)).created, true);
  const again = await store.add({ ...t1 });
  assert.equal(again.created, false);
  assert.equal(again.trip.id, 't1');
  assert.equal(store.list().length, 1);
});

test('повтор без id: id выводится из содержимого, дубля нет', async () => {
  const store = new TripStore();
  const { id, ...noId } = t1;
  const first = await store.add(noId);
  const second = await store.add(noId);
  assert.equal(first.created, true);
  assert.equal(second.created, false);
  assert.equal(second.trip.id, first.trip.id);
  assert.equal(store.list().length, 1);
});

test('та же поездка с новым id (клиент перегенерировал ключ) — тоже дубль', async () => {
  const store = new TripStore();
  await store.add(t1);
  const res = await store.add({ ...t1, id: 'other-id' });
  assert.equal(res.created, false);
  assert.equal(res.trip.id, 't1');
  assert.equal(store.list().length, 1);
});

test('то же время в другой записи смещения считается той же поездкой', async () => {
  const store = new TripStore();
  await store.add(t1);
  const res = await store.add({ ...t1, id: undefined, start: '2026-10-01T03:10:00Z', end: '2026-10-01T03:32:00Z' });
  assert.equal(res.created, false);
  assert.equal(store.list().length, 1);
});

test('тот же id с другими данными — конфликт, исходная поездка не меняется', async () => {
  const store = new TripStore();
  await store.add(t1);
  await assert.rejects(store.add({ ...t1, amount: 9999 }), (err) => {
    assert.ok(err instanceof ConflictError);
    assert.equal(err.code, 'id_conflict');
    assert.equal(err.existing.amount, 2400);
    return true;
  });
  assert.equal(store.list()[0].amount, 2400);
});

test('пересекающаяся по времени поездка отклоняется', async () => {
  const store = new TripStore();
  await store.add(t1);
  await assert.rejects(
    store.add({ ...t1, id: 't9', start: '2026-10-01T08:30:00+05:00', end: '2026-10-01T08:50:00+05:00' }),
    (err) => err instanceof ConflictError && err.code === 'overlap',
  );
  // встык — можно
  const res = await store.add({ ...t1, id: 't9', start: '2026-10-01T08:32:00+05:00', end: '2026-10-01T08:50:00+05:00' });
  assert.equal(res.created, true);
});

test('одновременные запросы с одной поездкой создают ровно одну запись', async () => {
  const dir = await mkdtemp(path.join(tmpdir(), 'trips-'));
  try {
    const file = path.join(dir, 'trips.json');
    const store = new TripStore({ file });
    const results = await Promise.all(Array.from({ length: 10 }, () => store.add({ ...t1 })));
    assert.equal(results.filter((r) => r.created).length, 1);
    assert.equal(store.list().length, 1);

    const saved = JSON.parse(await readFile(file, 'utf8'));
    assert.equal(saved.length, 1);

    // после перезапуска повтор тоже не создаёт дубль
    const reopened = await TripStore.open(file);
    assert.equal((await reopened.add(t1)).created, false);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('валидация: сумма > 0, окончание позже начала и остальные поля', async () => {
  const store = new TripStore();
  const fields = async (input) => {
    try {
      await store.add(input);
    } catch (err) {
      assert.ok(err instanceof ValidationError);
      return err.details.map((d) => d.field);
    }
    assert.fail('ожидалась ошибка валидации');
  };

  assert.deepEqual(await fields({ ...t1, amount: 0 }), ['amount']);
  assert.deepEqual(await fields({ ...t1, amount: -100 }), ['amount']);
  assert.deepEqual(await fields({ ...t1, amount: '2400' }), ['amount']);
  assert.deepEqual(await fields({ ...t1, amount: 10.005 }), ['amount']);
  assert.deepEqual(await fields({ ...t1, end: t1.start }), ['end']);
  assert.deepEqual(await fields({ ...t1, end: '2026-10-01T08:00:00+05:00' }), ['end']);
  assert.deepEqual(await fields({ ...t1, start: '2026-02-30T08:00:00+05:00' }), ['start']);
  assert.deepEqual(await fields({ ...t1, start: '2026-10-01T08:10:00' }), ['start']); // без смещения
  assert.deepEqual(await fields({ ...t1, payment: 'bitcoin' }), ['payment']);
  assert.deepEqual(await fields({ ...t1, commission: -1 }), ['commission']);
  assert.deepEqual(await fields({ ...t1, commission: 5000 }), ['commission']);
  assert.deepEqual(await fields({ ...t1, commission: undefined }), ['commission']);
  assert.deepEqual(await fields({ ...t1, id: '../etc' }), ['id']);
  assert.deepEqual(await fields([]), [null]);
  assert.equal(store.list().length, 0);
});
