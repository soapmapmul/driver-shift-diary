const $ = (id) => document.getElementById(id);

const state = {
  date: null,
  utcOffset: '+05:00',
  days: [],
  trips: [],
  requestSeq: 0,
  highlightId: null,
};

// ---------- форматирование ----------

const money = new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 2 });
const fmtMoney = (v) => `${money.format(v)} ₸`; // неразрывный пробел: ₸ не уезжает на новую строку
const dayLabel = new Intl.DateTimeFormat('ru-RU', { weekday: 'short', day: 'numeric', month: 'long', timeZone: 'UTC' });
const chipLabel = new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'short', timeZone: 'UTC' });

function plural(n, one, few, many) {
  const m10 = n % 10, m100 = n % 100;
  if (m10 === 1 && m100 !== 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

function fmtDuration(min) {
  const h = Math.floor(min / 60), m = min % 60;
  return h ? `${h} ч ${String(m).padStart(2, '0')} мин` : `${m} мин`;
}

const dateUtc = (date) => Date.UTC(+date.slice(0, 4), +date.slice(5, 7) - 1, +date.slice(8, 10));
const shiftDate = (date, days) => new Date(dateUtc(date) + days * 86_400_000).toISOString().slice(0, 10);
const isDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s) && new Date(dateUtc(s)).toISOString().slice(0, 10) === s;

function offsetMs(offset = state.utcOffset) {
  if (offset === 'Z') return 0;
  const sign = offset[0] === '-' ? -1 : 1;
  return sign * (+offset.slice(1, 3) * 60 + +offset.slice(4, 6)) * 60_000;
}

/** Время в поясе водителя как «стенные часы» в UTC-представлении. */
const wall = (iso) => new Date(Date.parse(iso) + offsetMs());
const hhmm = (iso) => wall(iso).toISOString().slice(11, 16);
const todayLocal = () => new Date(Date.now() + offsetMs()).toISOString().slice(0, 10);

// ---------- загрузка ----------

async function api(path, options) {
  const res = await fetch(path, options);
  const body = await res.json().catch(() => ({}));
  return { status: res.status, body };
}

async function loadDays() {
  const { body } = await api('/api/days');
  state.days = body.days ?? [];
  state.utcOffset = body.utcOffset ?? state.utcOffset;
}

async function loadDay(date) {
  state.date = date;
  renderNav();
  const seq = ++state.requestSeq;
  const { status, body } = await api(`/api/trips?date=${date}`);
  if (seq !== state.requestSeq) return; // пока грузили, переключили день
  if (status !== 200) return toast(body.error?.message ?? 'Не удалось загрузить день');
  state.trips = body.trips;
  renderSummary(body.summary);
  renderTimeline(body.trips);
  renderTrips(body.trips);
}

function go(date) {
  if (location.hash.slice(1) === date) loadDay(date);
  else location.hash = date;
}

// ---------- отрисовка ----------

function renderNav() {
  $('date-label').textContent = dayLabel.format(dateUtc(state.date));
  $('date-input').value = state.date;
  const chips = $('day-chips');
  chips.replaceChildren(
    ...state.days.map(({ date, trips }) => {
      const b = document.createElement('button');
      b.textContent = `${chipLabel.format(dateUtc(date))} · ${trips}`;
      b.setAttribute('aria-label', `${dayLabel.format(dateUtc(date))}: ${trips} ${plural(trips, 'поездка', 'поездки', 'поездок')}`);
      if (date === state.date) b.setAttribute('aria-current', 'date');
      b.onclick = () => go(date);
      return b;
    }),
  );
  chips.querySelector('[aria-current]')?.scrollIntoView({ block: 'nearest', inline: 'center' });
}

function renderSummary(s) {
  $('s-net').textContent = fmtMoney(s.net);
  $('s-sub').textContent = s.trips
    ? `выручка ${fmtMoney(s.revenue)} минус комиссия ${fmtMoney(s.commission)}`
    : 'поездок нет';
  $('s-trips').textContent = s.trips;
  $('s-revenue').textContent = fmtMoney(s.revenue);
  $('s-commission').textContent = fmtMoney(s.commission);
  $('s-drive').textContent = fmtDuration(s.driveMinutes);

  const { cash, card } = s.byPayment;
  $('s-cash').textContent = fmtMoney(cash.revenue);
  $('s-card').textContent = fmtMoney(card.revenue);
  $('s-cash-n').textContent = cash.trips ? `${cash.trips} шт.` : '';
  $('s-card-n').textContent = card.trips ? `${card.trips} шт.` : '';
  const [cashBar, cardBar] = $('split-bar').children;
  cashBar.style.width = s.revenue ? `${(cash.revenue / s.revenue) * 100}%` : '0';
  cardBar.style.width = s.revenue ? `${(card.revenue / s.revenue) * 100}%` : '0';

  $('s-balance').textContent = !s.trips
    ? ''
    : s.serviceBalance >= 0
      ? `Наличные ${fmtMoney(cash.revenue)} уже у вас, сервис доплатит ${fmtMoney(s.serviceBalance)} (карта минус вся комиссия).`
      : `Наличные ${fmtMoney(cash.revenue)} у вас, сервису нужно вернуть ${fmtMoney(-s.serviceBalance)} комиссии.`;
}

function renderTimeline(trips) {
  const dayStart = dateUtc(state.date);
  $('timeline-track').replaceChildren(
    ...trips.map((t) => {
      const from = (wall(t.start) - dayStart) / 60_000;
      const to = Math.min((wall(t.end) - dayStart) / 60_000, 1440); // ночная поездка обрезается полуночью
      const span = document.createElement('span');
      span.className = t.payment;
      span.style.left = `${(from / 1440) * 100}%`;
      span.style.width = `${((to - from) / 1440) * 100}%`;
      span.title = `${hhmm(t.start)}–${hhmm(t.end)} · ${fmtMoney(t.amount)}`;
      return span;
    }),
  );
}

function renderTrips(trips) {
  $('empty').hidden = trips.length > 0;
  $('trips').replaceChildren(
    ...trips.map((t) => {
      const li = document.createElement('li');
      li.className = 'trip' + (t.id === state.highlightId ? ' fresh' : '');
      const nextDay = wall(t.end).toISOString().slice(0, 10) !== t.date ? ' (+1 день)' : '';
      li.innerHTML = `
        <span class="trip-time"></span><span class="trip-amount"></span>
        <span class="trip-meta"><span class="badge ${t.payment}"></span></span><span class="trip-net"></span>`;
      li.querySelector('.trip-time').textContent = `${hhmm(t.start)}–${hhmm(t.end)}${nextDay}`;
      li.querySelector('.trip-amount').textContent = fmtMoney(t.amount);
      li.querySelector('.badge').textContent = t.payment === 'cash' ? 'Наличные' : 'Карта';
      li.querySelector('.trip-meta').append(`${fmtDuration(t.durationMinutes)} · комиссия ${fmtMoney(t.commission)}`);
      li.querySelector('.trip-net').textContent = `на руки ${fmtMoney(t.net)}`;
      return li;
    }),
  );
  state.highlightId = null;
}

let toastTimer;
function toast(text) {
  const el = $('toast');
  el.textContent = text;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (el.hidden = true), 3500);
}

// ---------- форма добавления ----------

const form = $('trip-form');
const dialog = $('trip-dialog');
// Ключ идемпотентности: создаётся при открытии формы и живёт до успешного сохранения.
// Если ответ потерялся и водитель жмёт «Сохранить» ещё раз, сервер узнает ту же поездку.
let pendingId = null;
let commissionTouched = false;

const newId = () =>
  'c-' + (crypto.randomUUID?.() ?? `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`);
const localInput = (ms) => new Date(ms).toISOString().slice(0, 16);

function openForm() {
  form.reset();
  commissionTouched = false;
  pendingId = newId();
  showErrors([]);
  // начало — после последней поездки дня, иначе 09:00
  const last = state.trips.at(-1);
  const startMs = last ? wall(last.end).getTime() + 5 * 60_000 : dateUtc(state.date) + 9 * 3_600_000;
  form.start.value = localInput(startMs);
  form.end.value = localInput(startMs + 20 * 60_000);
  dialog.showModal();
  form.amount.focus();
}

function showErrors(errors) {
  for (const input of form.querySelectorAll('input')) input.removeAttribute('aria-invalid');
  for (const e of errors) form.elements[e.field]?.setAttribute?.('aria-invalid', 'true');
  $('form-errors').replaceChildren(
    ...errors.map((e) => Object.assign(document.createElement('li'), { textContent: e.message })),
  );
}

const numberOrNull = (input) => (input.value === '' ? null : Number(input.value));
const toIso = (local) => (local ? `${local}:00${state.utcOffset}` : null);

form.amount.addEventListener('input', () => {
  if (commissionTouched) return;
  const amount = numberOrNull(form.amount);
  form.commission.value = amount > 0 ? Math.round(amount * 15) / 100 : '';
});
form.commission.addEventListener('input', () => (commissionTouched = true));

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  const submit = $('submit');
  if (submit.disabled) return;
  submit.disabled = true;
  try {
    const payload = {
      id: pendingId,
      start: toIso(form.start.value),
      end: toIso(form.end.value),
      amount: numberOrNull(form.amount),
      payment: form.payment.value,
      commission: numberOrNull(form.commission),
    };
    const { status, body } = await api('/api/trips', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (status === 201 || status === 200) {
      pendingId = null;
      dialog.close();
      toast(body.duplicate ? 'Такая поездка уже есть — дубль не создан' : 'Поездка добавлена');
      state.highlightId = body.trip.id;
      await loadDays();
      go(body.trip.date);
    } else if (status === 400 && body.error?.details) {
      showErrors(body.error.details);
    } else {
      showErrors([{ field: null, message: body.error?.message ?? `Ошибка сервера (${status})` }]);
    }
  } catch {
    // сеть упала — pendingId сохраняем, повторная отправка не создаст дубль
    showErrors([{ field: null, message: 'Нет связи с сервером. Нажмите «Сохранить» ещё раз — дубля не будет.' }]);
  } finally {
    submit.disabled = false;
  }
});

$('cancel').onclick = () => dialog.close();
$('open-form').onclick = openForm;

// ---------- навигация ----------

$('prev').onclick = () => go(shiftDate(state.date, -1));
$('next').onclick = () => go(shiftDate(state.date, 1));
$('date-input').addEventListener('change', (e) => isDate(e.target.value) && go(e.target.value));
document.addEventListener('keydown', (e) => {
  if (dialog.open || e.target.closest('input')) return;
  if (e.key === 'ArrowLeft') $('prev').click();
  if (e.key === 'ArrowRight') $('next').click();
});
window.addEventListener('hashchange', () => {
  const date = location.hash.slice(1);
  if (isDate(date)) loadDay(date);
});

await loadDays();
const fromHash = location.hash.slice(1);
// по умолчанию — последний день, где есть поездки (или сегодня, если данных нет)
go(isDate(fromHash) ? fromHash : state.days.at(-1)?.date ?? todayLocal());
