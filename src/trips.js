// Валидация и нормализация поездок, разбор времени и денег.
import { createHash } from 'node:crypto';

export const PAYMENT_METHODS = ['cash', 'card'];
export const MAX_AMOUNT = 10_000_000;

// ISO 8601 с обязательным смещением: 2026-10-01T08:10:00+05:00 или ...Z
const TIMESTAMP_RE =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3})\d*)?)?(Z|[+-]\d{2}:\d{2})$/;
const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const OFFSET_RE = /^(Z|[+-](?:0\d|1[0-4]):[0-5]\d)$/;
const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

export class ValidationError extends Error {
  constructor(details) {
    super('Некорректные данные поездки');
    this.details = details;
  }
}

export function isValidOffset(value) {
  return typeof value === 'string' && OFFSET_RE.test(value);
}

export function offsetMinutes(offset) {
  if (offset === 'Z') return 0;
  const sign = offset[0] === '-' ? -1 : 1;
  return sign * (Number(offset.slice(1, 3)) * 60 + Number(offset.slice(4, 6)));
}

/**
 * Разбирает время с явным смещением в миллисекунды epoch.
 * Возвращает null для неверного формата и несуществующих дат (2026-02-30, 25:00):
 * Date.parse такие значения не всегда отбрасывает, поэтому проверяем поля сами.
 */
export function parseTimestamp(value) {
  if (typeof value !== 'string') return null;
  const m = TIMESTAMP_RE.exec(value);
  if (!m || !isValidOffset(m[8])) return null;
  const [y, mo, d, h, mi, s] = m.slice(1, 7).map((x) => Number(x ?? 0));
  const ms = Number((m[7] ?? '0').padEnd(3, '0'));
  const wall = new Date(Date.UTC(y, mo - 1, d, h, mi, s, ms));
  if (
    wall.getUTCFullYear() !== y || wall.getUTCMonth() !== mo - 1 || wall.getUTCDate() !== d ||
    wall.getUTCHours() !== h || wall.getUTCMinutes() !== mi || wall.getUTCSeconds() !== s
  ) {
    return null;
  }
  return wall.getTime() - offsetMinutes(m[8]) * 60_000;
}

export function isValidDate(value) {
  const m = typeof value === 'string' && DATE_RE.exec(value);
  if (!m) return false;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return d.toISOString().slice(0, 10) === value;
}

/** Календарная дата момента времени в часовом поясе водителя. */
export function localDate(epochMs, utcOffset) {
  return new Date(epochMs + offsetMinutes(utcOffset) * 60_000).toISOString().slice(0, 10);
}

/** Деньги считаем в целых тиынах (сотых), чтобы 0.1 + 0.2 не давало 0.30000000000000004. */
export function toMinor(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  const minor = Math.round(value * 100);
  if (Math.abs(value * 100 - minor) > 1e-6) return null; // больше двух знаков после запятой
  return minor;
}

export function fromMinor(minor) {
  return minor / 100;
}

/**
 * Проверяет входные данные и возвращает нормализованную поездку.
 * Если id не передан, он выводится из содержимого: повторная отправка той же
 * поездки без id даст тот же id.
 */
export function validateTrip(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new ValidationError([{ field: null, message: 'Ожидается JSON-объект поездки' }]);
  }
  const errors = [];
  const fail = (field, message) => errors.push({ field, message });

  const { id, start, end, amount, payment, commission } = input;

  if (id !== undefined && id !== null && (typeof id !== 'string' || !ID_RE.test(id))) {
    fail('id', 'id — строка из латиницы, цифр, «-» и «_», до 64 символов');
  }

  const startMs = parseTimestamp(start);
  const endMs = parseTimestamp(end);
  if (startMs === null) fail('start', 'Время начала — дата в ISO 8601 со смещением, например 2026-10-01T08:10:00+05:00');
  if (endMs === null) fail('end', 'Время окончания — дата в ISO 8601 со смещением, например 2026-10-01T08:32:00+05:00');
  if (startMs !== null && endMs !== null && endMs <= startMs) {
    fail('end', 'Окончание поездки должно быть позже начала');
  }

  const amountMinor = toMinor(amount);
  if (amount === undefined || amount === null) fail('amount', 'Укажите сумму поездки');
  else if (amountMinor === null) fail('amount', 'Сумма — число, не более двух знаков после запятой');
  else if (amountMinor <= 0) fail('amount', 'Сумма должна быть больше нуля');
  else if (amountMinor > MAX_AMOUNT * 100) fail('amount', `Сумма не может превышать ${MAX_AMOUNT}`);

  if (!PAYMENT_METHODS.includes(payment)) fail('payment', 'Способ оплаты: "cash" или "card"');

  const commissionMinor = toMinor(commission);
  if (commission === undefined || commission === null) fail('commission', 'Укажите комиссию (0, если её нет)');
  else if (commissionMinor === null) fail('commission', 'Комиссия — число, не более двух знаков после запятой');
  else if (commissionMinor < 0) fail('commission', 'Комиссия не может быть отрицательной');
  else if (amountMinor !== null && amountMinor > 0 && commissionMinor > amountMinor) {
    fail('commission', 'Комиссия не может быть больше суммы поездки');
  }

  if (errors.length) throw new ValidationError(errors);

  const trip = {
    id: id ?? null,
    start,
    end,
    amount: fromMinor(amountMinor),
    payment,
    commission: fromMinor(commissionMinor),
  };
  if (!trip.id) trip.id = 't-' + createHash('sha256').update(fingerprint(trip)).digest('hex').slice(0, 16);
  return trip;
}

/** Отпечаток содержимого: одинаковые моменты времени в разных смещениях считаются равными. */
export function fingerprint(trip) {
  return [
    parseTimestamp(trip.start),
    parseTimestamp(trip.end),
    toMinor(trip.amount),
    trip.payment,
    toMinor(trip.commission),
  ].join('|');
}
