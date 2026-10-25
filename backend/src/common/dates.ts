/** Локальные «календарные» даты YYYY-MM-DD обрабатываем в UTC, чтобы смена часового пояса их не сдвигала. */
export const toDate = (s: string) => new Date(`${s}T00:00:00Z`);
export const fmt = (d: Date) => d.toISOString().slice(0, 10);
export const addDays = (s: string, n: number) => fmt(new Date(toDate(s).getTime() + n * 86400_000));
export const todayUtc = () => fmt(new Date());

export function isValidDate(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = toDate(s);
  return !Number.isNaN(d.getTime()) && fmt(d) === s;
}

const daysInMonth = (y: number, m: number) => new Date(Date.UTC(y, m + 1, 0)).getUTCDate();

/** Даты серии в [from, to]. Ежемесячное: число месяца стартовой даты, с клампом к концу короткого месяца. */
export function occurrenceDates(repeat: 'daily' | 'weekly' | 'monthly' | 'none', startDate: string, from: string, to: string): string[] {
  const out: string[] = [];
  if (repeat === 'none') return startDate >= from && startDate <= to ? [startDate] : [];
  if (repeat === 'monthly') {
    const start = toDate(startDate);
    const dom = start.getUTCDate();
    let y = start.getUTCFullYear();
    let m = start.getUTCMonth();
    for (let i = 0; i < 1200; i++) {
      const d = fmt(new Date(Date.UTC(y, m, Math.min(dom, daysInMonth(y, m)))));
      if (d > to) break;
      if (d >= from && d >= startDate) out.push(d);
      m++;
      if (m > 11) {
        m = 0;
        y++;
      }
    }
    return out;
  }
  const step = repeat === 'daily' ? 1 : 7;
  let d = startDate;
  if (d < from) {
    const skip = Math.floor((toDate(from).getTime() - toDate(d).getTime()) / 86400_000 / step) * step;
    d = addDays(d, skip);
    if (d < from) d = addDays(d, step);
  }
  for (; d <= to; d = addDays(d, step)) out.push(d);
  return out;
}
