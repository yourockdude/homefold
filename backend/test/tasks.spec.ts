import { INestApplication } from '@nestjs/common';
import { TasksService } from '../src/tasks/tasks.service';
import { addDays, occurrenceDates, todayUtc } from '../src/common/dates';
import { addMember, makeApp, makePremium, prisma, signInWithFamily, uid } from './helpers';

describe('Семейные дела', () => {
  let app: INestApplication;
  beforeAll(async () => (app = await makeApp()));
  afterAll(() => app.close());
  const today = todayUtc();

  it('разовое дело: создание, чек-лист, завершение с автором и временем, возврат, перенос, удаление', async () => {
    const c = await signInWithFamily(app);
    const m = await addMember(c);
    const id = uid();
    const res = await c.put(`/tasks/occurrences/${id}`, { title: 'Забрать Соню с танцев', assigneeId: m.userId, date: today, time: '18:30', place: 'Студия', note: 'Взять сменку' }).expect(200);
    expect(res.body).toMatchObject({ status: 'open', reminderMinutes: 30, seriesId: null });

    const cl = uid();
    await c.put(`/tasks/checklist/${cl}`, { occurrenceId: id, title: 'Сменка' }).expect(200);
    await m.put(`/tasks/checklist/${cl}`, { done: true }).expect(200);

    const done = await m.post(`/tasks/occurrences/${id}/complete`).expect(200);
    expect(done.body).toMatchObject({ status: 'done', completedById: m.userId });
    expect(done.body.completedAt).toBeTruthy();
    const reopened = await c.post(`/tasks/occurrences/${id}/reopen`).expect(200);
    expect(reopened.body).toMatchObject({ status: 'open', completedById: null, completedAt: null });

    const moved = await c.post(`/tasks/occurrences/${id}/postpone`, { date: addDays(today, 2), time: '19:00' }).expect(200);
    expect(moved.body).toMatchObject({ date: addDays(today, 2), time: '19:00' });

    const full = await c.get(`/tasks/occurrences/${id}`).expect(200);
    expect(full.body.checklist).toEqual([expect.objectContaining({ id: cl, done: true })]);

    await c.del(`/tasks/occurrences/${id}`).expect(204);
    await c.get(`/tasks/occurrences/${id}`).expect(404);
  });

  it('валидация: название, дата, время, ответственный', async () => {
    const c = await signInWithFamily(app);
    await c.put(`/tasks/occurrences/${uid()}`, { date: today }).expect(400);
    await c.put(`/tasks/occurrences/${uid()}`, { title: 'x' }).expect(400);
    await c.put(`/tasks/occurrences/${uid()}`, { title: 'x', date: '2026-13-45' }).expect(400);
    await c.put(`/tasks/occurrences/${uid()}`, { title: 'x', date: today, time: '25:99' }).expect(400);
    await c.put(`/tasks/occurrences/${uid()}`, { title: 'x', date: today, assigneeId: uid() }).expect(400);
  });

  it('список: фильтр по дню и ответственному, признак просрочки считается от today клиента', async () => {
    const c = await signInWithFamily(app);
    const m = await addMember(c);
    await c.put(`/tasks/occurrences/${uid()}`, { title: 'Вчера', date: addDays(today, -1) }).expect(200);
    await c.put(`/tasks/occurrences/${uid()}`, { title: 'Сегодня М', date: today, assigneeId: m.userId }).expect(200);
    await c.put(`/tasks/occurrences/${uid()}`, { title: 'Сегодня', date: today }).expect(200);
    const all = await c.get(`/tasks?from=${addDays(today, -3)}&to=${today}&today=${today}`).expect(200);
    expect(all.body.items.map((i: any) => [i.title, i.overdue])).toEqual([['Вчера', true], expect.any(Array), expect.any(Array)]);
    const mine = await c.get(`/tasks?from=${today}&to=${today}&assigneeId=${m.userId}`).expect(200);
    expect(mine.body.items.map((i: any) => i.title)).toEqual(['Сегодня М']);
    const empty = await c.get(`/tasks?from=${addDays(today, 5)}&to=${addDays(today, 5)}`).expect(200);
    expect(empty.body.items).toEqual([]);
  });

  describe('повторяющиеся дела', () => {
    it('бесплатный тариф: создание серии → 402 PREMIUM_REQUIRED', async () => {
      const c = await signInWithFamily(app);
      const res = await c.put(`/tasks/series/${uid()}`, { title: 'Полить цветы', startDate: today, repeat: 'daily' }).expect(402);
      expect(res.body.error.details.feature).toBe('recurring_tasks');
    });

    it('серия материализуется в отдельные выполнения; завершение одного не завершает серию', async () => {
      const c = await signInWithFamily(app);
      await makePremium(c);
      const sid = uid();
      await c.put(`/tasks/series/${sid}`, { title: 'Полить растения', startDate: today, time: '19:00', repeat: 'daily', checklist: ['Фикус', 'Монстера'] }).expect(200);
      const list = await c.get(`/tasks?from=${today}&to=${addDays(today, 59)}&limit=200`).expect(200);
      const occ = list.body.items.filter((i: any) => i.seriesId === sid);
      expect(occ.length).toBeGreaterThanOrEqual(58);
      expect(occ[0].checklist.map((x: any) => x.title)).toEqual(['Фикус', 'Монстера']);
      const first = occ.find((o: any) => o.originalDate === today)!;
      await c.post(`/tasks/occurrences/${first.id}/complete`).expect(200);
      const after = await c.get(`/tasks?from=${today}&to=${addDays(today, 59)}&limit=200`).expect(200);
      expect(after.body.items.filter((i: any) => i.seriesId === sid && i.status === 'done')).toHaveLength(1);
      expect(after.body.items.filter((i: any) => i.seriesId === sid && i.status === 'open').length).toBe(occ.length - 1);
    });

    it('правка/перенос выполнения меняет только его; правка серии его не затрагивает, но меняет остальные', async () => {
      const c = await signInWithFamily(app);
      await makePremium(c);
      const sid = uid();
      await c.put(`/tasks/series/${sid}`, { title: 'Уборка', startDate: today, repeat: 'daily' }).expect(200);
      const occs = (await c.get(`/tasks?from=${addDays(today, 1)}&to=${addDays(today, 5)}`).expect(200)).body.items;
      const target = occs[0];
      await c.put(`/tasks/occurrences/${target.id}`, { title: 'Генеральная уборка' }).expect(200);
      await c.post(`/tasks/occurrences/${occs[1].id}/postpone`, { date: addDays(today, 20) }).expect(200);

      await c.put(`/tasks/series/${sid}`, { title: 'Лёгкая уборка', time: '10:00' }).expect(200);
      const get = async (id: string) => (await c.get(`/tasks/occurrences/${id}`).expect(200)).body;
      expect(await get(target.id)).toMatchObject({ title: 'Генеральная уборка', overridden: true });
      expect(await get(occs[1].id)).toMatchObject({ date: addDays(today, 20), title: 'Уборка' }); // перенесённое — тоже личное
      expect(await get(occs[2].id)).toMatchObject({ title: 'Лёгкая уборка', time: '10:00' });
    });

    it('удалённое вручную выполнение не воскресает при пересборке серии', async () => {
      const c = await signInWithFamily(app);
      await makePremium(c);
      const sid = uid();
      await c.put(`/tasks/series/${sid}`, { title: 'Мусор', startDate: today, repeat: 'daily' }).expect(200);
      const victim = (await c.get(`/tasks?from=${addDays(today, 3)}&to=${addDays(today, 3)}`).expect(200)).body.items[0];
      await c.del(`/tasks/occurrences/${victim.id}`).expect(204);
      await c.put(`/tasks/series/${sid}`, { note: 'Баки у подъезда' }).expect(200);
      await app.get(TasksService).materializeAll();
      await c.get(`/tasks/occurrences/${victim.id}`).expect(404);
    });

    it('смена правила повторения заменяет будущие невыполненные выполнения, выполненные остаются', async () => {
      const c = await signInWithFamily(app);
      await makePremium(c);
      const sid = uid();
      await c.put(`/tasks/series/${sid}`, { title: 'Зарядка', startDate: today, repeat: 'daily' }).expect(200);
      const first = (await c.get(`/tasks?from=${today}&to=${today}`).expect(200)).body.items[0];
      await c.post(`/tasks/occurrences/${first.id}/complete`).expect(200);
      await c.put(`/tasks/series/${sid}`, { repeat: 'weekly' }).expect(200);
      const items = (await c.get(`/tasks?from=${today}&to=${addDays(today, 59)}&limit=200`).expect(200)).body.items.filter((i: any) => i.seriesId === sid);
      expect(items.filter((i: any) => i.status === 'open').length).toBeLessThanOrEqual(9);
      expect(items.filter((i: any) => i.status === 'done')).toHaveLength(1);
    });

    it('окончание подписки: повторы приостанавливаются, история и существующие выполнения не удаляются', async () => {
      const c = await signInWithFamily(app);
      await makePremium(c);
      const sid = uid();
      await c.put(`/tasks/series/${sid}`, { title: 'Полив', startDate: today, repeat: 'daily' }).expect(200);
      const count = async () => (await prisma(app).taskOccurrence.count({ where: { seriesId: sid, deletedAt: null } }));
      const before = await count();
      await c.post('/billing/dev/mock-expire', {}).expect(200);
      // правка серии запрещена, пересборка ничего не создаёт и не удаляет
      await c.put(`/tasks/series/${sid}`, { title: 'Другое' }).expect(402);
      await prisma(app).taskOccurrence.deleteMany({ where: { seriesId: sid, date: { gt: addDays(today, 10) } } });
      const mid = await count();
      await app.get(TasksService).materializeAll();
      expect(await count()).toBe(mid);
      expect(mid).toBeLessThan(before);
      // разовые дела по-прежнему без ограничений, серию можно удалить
      await c.put(`/tasks/occurrences/${uid()}`, { title: 'Разовое', date: today }).expect(200);
      await c.del(`/tasks/series/${sid}`).expect(204);
    });

    it('удаление серии сохраняет выполненные выполнения', async () => {
      const c = await signInWithFamily(app);
      await makePremium(c);
      const sid = uid();
      await c.put(`/tasks/series/${sid}`, { title: 'Йога', startDate: today, repeat: 'daily' }).expect(200);
      const first = (await c.get(`/tasks?from=${today}&to=${today}`).expect(200)).body.items[0];
      await c.post(`/tasks/occurrences/${first.id}/complete`).expect(200);
      await c.del(`/tasks/series/${sid}`).expect(204);
      const left = (await c.get(`/tasks?from=${today}&to=${addDays(today, 59)}&limit=200`).expect(200)).body.items.filter((i: any) => i.seriesId === sid);
      expect(left.map((i: any) => i.status)).toEqual(['done']);
    });
  });

  describe('правила повторения (даты)', () => {
    it('ежедневное и еженедельное', () => {
      expect(occurrenceDates('daily', '2026-10-01', '2026-10-03', '2026-10-05')).toEqual(['2026-10-03', '2026-10-04', '2026-10-05']);
      expect(occurrenceDates('weekly', '2026-10-01', '2026-10-10', '2026-10-30')).toEqual(['2026-10-15', '2026-10-22', '2026-10-29']);
    });
    it('ежемесячное: 31 число переживает короткие месяцы, високосный год', () => {
      expect(occurrenceDates('monthly', '2026-01-31', '2026-01-01', '2026-05-01')).toEqual(['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
      expect(occurrenceDates('monthly', '2028-01-31', '2028-02-01', '2028-03-01')).toEqual(['2028-02-29']);
    });
    it('смена года и серия, начинающаяся в будущем', () => {
      expect(occurrenceDates('daily', '2026-12-30', '2026-12-30', '2027-01-02')).toEqual(['2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02']);
      expect(occurrenceDates('daily', '2027-01-01', '2026-12-01', '2026-12-31')).toEqual([]);
    });
  });
});
