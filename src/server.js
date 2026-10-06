// HTTP API и раздача статики клиента. Без фреймворков — только node:http.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { ConflictError } from './store.js';
import { summarize } from './summary.js';
import { fromMinor, isValidDate, localDate, parseTimestamp, toMinor, ValidationError } from './trips.js';

const MAX_BODY_BYTES = 64 * 1024;
const CONTENT_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
};

// Flutter-клиент (сборка flutter build web --base-href /app/) отдаётся по /app/.
const APP_PREFIX = '/app/';

class HttpError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

// API открыт для других источников: Flutter Web во время разработки работает на своём порту.
// Авторизации нет, cookies не используются, поэтому «*» здесь безопасен.
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
};

function sendJson(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...CORS_HEADERS });
  res.end(JSON.stringify(body));
}

async function readJsonBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new HttpError(413, 'too_large', 'Слишком большое тело запроса');
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HttpError(400, 'invalid_json', 'Тело запроса — не корректный JSON');
  }
}

/** Поездка для ответа API: исходные поля + вычисленные (день, длительность, «на руки»). */
function tripView(trip, utcOffset) {
  const startMs = parseTimestamp(trip.start);
  return {
    ...trip,
    date: localDate(startMs, utcOffset),
    durationMinutes: Math.round((parseTimestamp(trip.end) - startMs) / 60_000),
    net: fromMinor(toMinor(trip.amount) - toMinor(trip.commission)),
  };
}

function requestedDate(url, store) {
  const date = url.searchParams.get('date') ?? localDate(Date.now(), store.utcOffset);
  if (!isValidDate(date)) throw new HttpError(400, 'invalid_date', 'Параметр date — дата в формате YYYY-MM-DD');
  return date;
}

export function createApp(store, { publicDir, appDir } = {}) {
  const routes = {
    'GET /api/trips': (req, url) => {
      const date = requestedDate(url, store);
      const trips = store.byDate(date);
      return [200, {
        date,
        utcOffset: store.utcOffset,
        summary: summarize(trips),
        trips: trips.map((t) => tripView(t, store.utcOffset)),
      }];
    },

    'GET /api/summary': (req, url) => {
      const date = requestedDate(url, store);
      return [200, { date, utcOffset: store.utcOffset, summary: summarize(store.byDate(date)) }];
    },

    'GET /api/days': () => [200, { utcOffset: store.utcOffset, days: store.days() }],

    'POST /api/trips': async (req) => {
      const body = await readJsonBody(req);
      try {
        const { created, trip } = await store.add(body);
        return [created ? 201 : 200, { created, duplicate: !created, trip: tripView(trip, store.utcOffset) }];
      } catch (err) {
        if (err instanceof ValidationError) {
          throw new HttpError(400, 'validation', err.message, { details: err.details });
        }
        if (err instanceof ConflictError) {
          throw new HttpError(409, err.code, err.message, { existing: tripView(err.existing, store.utcOffset) });
        }
        throw err;
      }
    },
  };

  async function serveStatic(url, res) {
    if (url.pathname === '/app') {
      res.writeHead(301, { Location: APP_PREFIX });
      res.end();
      return true;
    }
    const inApp = url.pathname.startsWith(APP_PREFIX);
    const dir = inApp ? appDir : publicDir;
    if (!dir) return false;
    const pathname = inApp ? url.pathname.slice(APP_PREFIX.length - 1) : url.pathname;
    const rel = pathname === '/' ? 'index.html' : decodeURIComponent(pathname.slice(1));
    const file = path.resolve(dir, rel);
    if (!file.startsWith(path.resolve(dir) + path.sep)) return false;
    try {
      const body = await readFile(file);
      res.writeHead(200, { 'Content-Type': CONTENT_TYPES[path.extname(file)] ?? 'application/octet-stream' });
      res.end(body);
      return true;
    } catch {
      return false;
    }
  }

  return createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    try {
      if (req.method === 'OPTIONS' && url.pathname.startsWith('/api/')) {
        res.writeHead(204, CORS_HEADERS);
        return res.end();
      }
      const handler = routes[`${req.method} ${url.pathname}`];
      if (handler) {
        const [status, body] = await handler(req, url);
        return sendJson(res, status, body);
      }
      if (url.pathname.startsWith('/api/')) {
        const known = Object.keys(routes).some((r) => r.endsWith(' ' + url.pathname));
        throw known
          ? new HttpError(405, 'method_not_allowed', 'Метод не поддерживается')
          : new HttpError(404, 'not_found', 'Нет такого метода API');
      }
      if (req.method === 'GET' && (await serveStatic(url, res))) return;
      if (url.pathname.startsWith(APP_PREFIX)) {
        throw new HttpError(404, 'app_not_built', 'Flutter-клиент не собран: cd mobile && flutter build web --base-href /app/');
      }
      throw new HttpError(404, 'not_found', 'Не найдено');
    } catch (err) {
      if (err instanceof HttpError) {
        return sendJson(res, err.status, { error: { code: err.code, message: err.message, ...err.extra } });
      }
      console.error(err);
      return sendJson(res, 500, { error: { code: 'internal', message: 'Внутренняя ошибка сервера' } });
    }
  });
}
