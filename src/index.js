import { copyFile, mkdir, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from './server.js';
import { TripStore } from './store.js';
import { isValidOffset } from './trips.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.env.PORT ?? 3000);
const dataFile = path.resolve(process.env.DATA_FILE ?? path.join(root, 'data', 'trips.json'));
const seedFile = path.join(root, 'data', 'trips.seed.json');
// Часовой пояс водителя: по нему поездка относится к дню (по времени начала).
const utcOffset = process.env.UTC_OFFSET ?? '+05:00';

if (!isValidOffset(utcOffset)) {
  console.error(`UTC_OFFSET должен быть вида +05:00, получено: ${utcOffset}`);
  process.exit(1);
}

// При первом запуске копируем пример данных, чтобы было что посмотреть.
try {
  await access(dataFile);
} catch {
  await mkdir(path.dirname(dataFile), { recursive: true });
  await copyFile(seedFile, dataFile);
  console.log(`Создан ${path.relative(root, dataFile)} из примера данных`);
}

const store = await TripStore.open(dataFile, { utcOffset });
const server = createApp(store, { publicDir: path.join(root, 'public') });
server.listen(port, () => {
  console.log(`Дневник смен: http://localhost:${port}  (данные: ${dataFile}, пояс UTC${utcOffset})`);
});
