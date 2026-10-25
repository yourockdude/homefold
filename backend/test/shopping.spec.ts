import { INestApplication } from '@nestjs/common';
import { addMember, makeApp, makePremium, prisma, signInWithFamily, uid } from './helpers';

describe('Покупки', () => {
  let app: INestApplication;
  beforeAll(async () => (app = await makeApp()));
  afterAll(() => app.close());

  it('добавление, редактирование, покупка и возврат товара', async () => {
    const c = await signInWithFamily(app);
    const m = await addMember(c);
    const listId = uid();
    await c.put(`/shopping/lists/${listId}`, { name: 'Покупки' }).expect(200);
    const id = uid();
    const created = await c.put(`/shopping/items/${id}`, { listId, name: ' Молоко ', quantity: 2, unit: 'л', category: 'Молочное', assigneeId: m.userId, note: 'Без лактозы' }).expect(200);
    expect(created.body).toMatchObject({ name: 'Молоко', quantity: 2, unit: 'л', assigneeId: m.userId, purchased: false, version: 1 });

    const bought = await m.put(`/shopping/items/${id}`, { purchased: true }).expect(200);
    expect(bought.body).toMatchObject({ purchased: true, purchasedById: m.userId, version: 2 });
    expect(bought.body.purchasedAt).toBeTruthy();

    const back = await c.put(`/shopping/items/${id}`, { purchased: false, assigneeId: null }).expect(200);
    expect(back.body).toMatchObject({ purchased: false, purchasedById: null, purchasedAt: null, assigneeId: null });
  });

  it('валидация: пустое название, нулевое и отрицательное количество, чужой ответственный', async () => {
    const c = await signInWithFamily(app);
    const listId = uid();
    await c.put(`/shopping/lists/${listId}`, {}).expect(200);
    let res = await c.put(`/shopping/items/${uid()}`, { listId, name: '   ' }).expect(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    await c.put(`/shopping/items/${uid()}`, { listId }).expect(400);
    await c.put(`/shopping/items/${uid()}`, { listId, name: 'Хлеб', quantity: 0 }).expect(400);
    await c.put(`/shopping/items/${uid()}`, { listId, name: 'Хлеб', quantity: -1 }).expect(400);
    res = await c.put(`/shopping/items/${uid()}`, { listId, name: 'Хлеб', assigneeId: uid() }).expect(400);
    expect(res.body.error.message).toContain('участником');
    await c.put(`/shopping/items/not-a-uuid`, { listId, name: 'Хлеб' }).expect(400);
  });

  it('удаление скрывает товар из списка и порождает tombstone', async () => {
    const c = await signInWithFamily(app);
    const listId = uid();
    await c.put(`/shopping/lists/${listId}`, {}).expect(200);
    const id = uid();
    await c.put(`/shopping/items/${id}`, { listId, name: 'Яблоки' }).expect(200);
    await c.del(`/shopping/items/${id}`).expect(204);
    expect((await c.get(`/shopping/lists/${listId}`).expect(200)).body.items).toHaveLength(0);
    const pull = await c.get('/sync/pull').expect(200);
    const ch = pull.body.changes.find((x: any) => x.entity === 'shoppingItem' && x.id === id);
    expect(ch).toMatchObject({ deleted: true });
    // правка удалённого не воскрешает
    await c.put(`/shopping/items/${id}`, { name: 'Груши' }).expect(409);
  });

  it('повтор того же запроса не создаёт дубликатов', async () => {
    const c = await signInWithFamily(app);
    const listId = uid();
    const id = uid();
    await c.put(`/shopping/lists/${listId}`, {}).expect(200);
    await c.put(`/shopping/items/${id}`, { listId, name: 'Сыр' }).expect(200);
    await c.put(`/shopping/items/${id}`, { listId, name: 'Сыр' }).expect(200);
    expect((await c.get(`/shopping/lists/${listId}`).expect(200)).body.items).toHaveLength(1);
    const newId = uid();
    await c.post('/shopping/lists/new', { id: newId }).expect(200);
    await c.post('/shopping/lists/new', { id: newId }).expect(200);
    expect((await c.get('/shopping/lists?status=active').expect(200)).body.items).toHaveLength(1);
    expect((await c.get('/shopping/lists?status=archived').expect(200)).body.items).toHaveLength(1);
  });

  it('«Начать новый список»: старый уходит в историю с товарами, новый пуст', async () => {
    const c = await signInWithFamily(app);
    const listId = uid();
    await c.put(`/shopping/lists/${listId}`, { name: 'Неделя' }).expect(200);
    await c.put(`/shopping/items/${uid()}`, { listId, name: 'Рис', purchased: true }).expect(200);
    const res = await c.post('/shopping/lists/new', { id: uid(), name: 'Новая неделя' }).expect(200);
    expect(res.body.archivedIds).toEqual([listId]);
    const hist = await c.get('/shopping/lists?status=archived').expect(200);
    expect(hist.body.items[0]).toMatchObject({ id: listId, status: 'archived' });
    expect(hist.body.items[0].items).toHaveLength(1);
  });

  it('бесплатный тариф: второй активный список → 402, Plus снимает ограничение', async () => {
    const c = await signInWithFamily(app);
    await c.put(`/shopping/lists/${uid()}`, { name: 'Первый' }).expect(200);
    const res = await c.put(`/shopping/lists/${uid()}`, { name: 'Второй' }).expect(402);
    expect(res.body.error).toMatchObject({ code: 'PREMIUM_REQUIRED', details: { feature: 'multiple_lists' } });
    await makePremium(c);
    await c.put(`/shopping/lists/${uid()}`, { name: 'Второй' }).expect(200);
    expect((await c.get('/shopping/lists').expect(200)).body.items).toHaveLength(2);
  });

  it('история: в бесплатном тарифе только последние 30 дней, Plus — вся', async () => {
    const c = await signInWithFamily(app);
    const old = uid();
    await c.put(`/shopping/lists/${old}`, { name: 'Старый' }).expect(200);
    await c.post('/shopping/lists/new', { id: uid() }).expect(200);
    await prisma(app).shoppingList.update({ where: { id: old }, data: { archivedAt: new Date(Date.now() - 45 * 86400_000) } });
    const free = await c.get('/shopping/lists?status=archived').expect(200);
    expect(free.body.items).toHaveLength(0);
    expect(free.body).toMatchObject({ historyLimitDays: 30, hiddenByPlan: 1 });
    await makePremium(c);
    const plus = await c.get('/shopping/lists?status=archived').expect(200);
    expect(plus.body.items).toHaveLength(1);
    expect(plus.body.historyLimitDays).toBeNull();
  });

  it('пагинация списков курсором', async () => {
    const c = await signInWithFamily(app);
    await makePremium(c);
    for (let i = 0; i < 3; i++) await c.put(`/shopping/lists/${uid()}`, { name: `L${i}` }).expect(200);
    const p1 = await c.get('/shopping/lists?limit=2').expect(200);
    expect(p1.body.items).toHaveLength(2);
    expect(p1.body.nextCursor).toBeTruthy();
    const p2 = await c.get(`/shopping/lists?limit=2&cursor=${p1.body.nextCursor}`).expect(200);
    expect(p2.body.items).toHaveLength(1);
    expect(p2.body.nextCursor).toBeNull();
  });
});
