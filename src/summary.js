// Сводка за день по списку поездок.
import { fromMinor, parseTimestamp, toMinor } from './trips.js';

function bucket() {
  return { trips: 0, revenue: 0, commission: 0 };
}

function present(b) {
  return {
    trips: b.trips,
    revenue: fromMinor(b.revenue),
    commission: fromMinor(b.commission),
    net: fromMinor(b.revenue - b.commission),
  };
}

/**
 * revenue    — выручка (сумма всех поездок)
 * commission — комиссия сервиса
 * net        — «на руки»: выручка минус комиссия
 * byPayment  — то же отдельно по наличным и карте
 * serviceBalance — расчёт с сервисом: карта приходит через сервис, а комиссия
 *                  удерживается со всех поездок; отрицательное значение — водитель должен сервису
 */
export function summarize(trips) {
  const total = bucket();
  const byPayment = { cash: bucket(), card: bucket() };
  let driveMs = 0;

  for (const trip of trips) {
    const amount = toMinor(trip.amount);
    const commission = toMinor(trip.commission);
    for (const b of [total, byPayment[trip.payment]]) {
      b.trips += 1;
      b.revenue += amount;
      b.commission += commission;
    }
    driveMs += parseTimestamp(trip.end) - parseTimestamp(trip.start);
  }

  return {
    ...present(total),
    byPayment: { cash: present(byPayment.cash), card: present(byPayment.card) },
    serviceBalance: fromMinor(byPayment.card.revenue - total.commission),
    driveMinutes: Math.round(driveMs / 60_000),
  };
}
