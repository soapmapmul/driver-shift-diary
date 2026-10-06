// Хранилище поездок: в памяти + JSON-файл на диске.
import { readFile, rename, writeFile } from 'node:fs/promises';
import { fingerprint, localDate, parseTimestamp, validateTrip } from './trips.js';

export class ConflictError extends Error {
  constructor(code, message, existing) {
    super(message);
    this.code = code;
    this.existing = existing;
  }
}

export class TripStore {
  #file;
  #records = []; // { trip, startMs, endMs, date, fp }
  #byId = new Map();
  #byFingerprint = new Map();
  #writing = Promise.resolve();

  constructor({ file = null, utcOffset = '+05:00', trips = [] } = {}) {
    this.#file = file;
    this.utcOffset = utcOffset;
    for (const raw of trips) {
      const trip = validateTrip(raw);
      if (this.#byId.has(trip.id)) throw new Error(`Повторяющийся id в данных: ${trip.id}`);
      this.#insert(trip);
    }
  }

  static async open(file, options = {}) {
    let trips = [];
    try {
      trips = JSON.parse(await readFile(file, 'utf8'));
    } catch (err) {
      if (err.code !== 'ENOENT') throw err;
    }
    return new TripStore({ ...options, file, trips });
  }

  list() {
    return this.#sorted(this.#records);
  }

  byDate(date) {
    return this.#sorted(this.#records.filter((r) => r.date === date));
  }

  /** Дни, в которых есть поездки, с их количеством. */
  days() {
    const counts = new Map();
    for (const r of this.#records) counts.set(r.date, (counts.get(r.date) ?? 0) + 1);
    return [...counts].sort(([a], [b]) => a.localeCompare(b)).map(([date, trips]) => ({ date, trips }));
  }

  dateOf(trip) {
    return localDate(parseTimestamp(trip.start), this.utcOffset);
  }

  /**
   * Добавляет поездку идемпотентно:
   *  - тот же id и те же данные        → { created: false } (дубль, ничего не меняем)
   *  - тот же id, но другие данные     → ConflictError('id_conflict')
   *  - другой id, но те же данные      → { created: false } (повтор с новым id)
   *  - пересечение по времени с другой → ConflictError('overlap'): водитель не может
   *    везти две поездки одновременно
   * Все проверки и вставка выполняются синхронно, до первого await, поэтому два
   * одновременных запроса не могут оба пройти проверку на дубль.
   */
  async add(input) {
    const trip = validateTrip(input);
    const fp = fingerprint(trip);

    const sameId = this.#byId.get(trip.id);
    if (sameId) {
      if (sameId.fp === fp) return { created: false, trip: sameId.trip };
      throw new ConflictError('id_conflict', `Поездка с id «${trip.id}» уже есть, и её данные отличаются`, sameId.trip);
    }

    const sameContent = this.#byFingerprint.get(fp);
    if (sameContent) return { created: false, trip: sameContent.trip };

    const record = this.#insert(trip);
    const overlap = this.#records.find((r) => r !== record && r.startMs < record.endMs && record.startMs < r.endMs);
    if (overlap) {
      this.#remove(record);
      throw new ConflictError('overlap', `Поездка пересекается по времени с поездкой «${overlap.trip.id}»`, overlap.trip);
    }

    try {
      await this.#persist();
    } catch (err) {
      this.#remove(record);
      throw err;
    }
    return { created: true, trip };
  }

  #insert(trip) {
    const startMs = parseTimestamp(trip.start);
    const record = {
      trip,
      startMs,
      endMs: parseTimestamp(trip.end),
      date: localDate(startMs, this.utcOffset),
      fp: fingerprint(trip),
    };
    this.#records.push(record);
    this.#byId.set(trip.id, record);
    this.#byFingerprint.set(record.fp, record);
    return record;
  }

  #remove(record) {
    this.#records = this.#records.filter((r) => r !== record);
    this.#byId.delete(record.trip.id);
    this.#byFingerprint.delete(record.fp);
  }

  #sorted(records) {
    return [...records].sort((a, b) => a.startMs - b.startMs).map((r) => r.trip);
  }

  // Записи идут строго по очереди; файл пишется во временный и атомарно переименовывается.
  #persist() {
    if (!this.#file) return Promise.resolve();
    const write = async () => {
      const tmp = `${this.#file}.tmp`;
      await writeFile(tmp, JSON.stringify(this.list(), null, 2) + '\n');
      await rename(tmp, this.#file);
    };
    const result = this.#writing.then(write);
    this.#writing = result.catch(() => {});
    return result;
  }
}
