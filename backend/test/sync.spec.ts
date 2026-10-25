import { INestApplication } from '@nestjs/common';
import { WebSocket } from 'ws';
import { addMember, makeApp, prisma, signInWithFamily, uid, Client } from './helpers';

const op = (entity: string, entityId: string, type: 'upsert' | 'delete', payload?: object, baseVersion?: number) => ({ opId: uid(), entity, entityId, type, payload, baseVersion });

describe('Синхронизация', () => {
  let app: INestApplication;
  beforeAll(async () => (app = await makeApp()));
  afterAll(() => app.close());

  it('оффлайн-пачка применяется по порядку: список → товары → дело', async () => {
    const c = await signInWithFamily(app);
    const list = uid(), item = uid(), task = uid();
    const res = await c.post('/sync/push', {
      operations: [
        op('shoppingList', list, 'upsert', { name: 'Оффлайн' }),
        op('shoppingItem', item, 'upsert', { listId: list, name: 'Хлеб', quantity: 1 }),
        op('taskOccurrence', task, 'upsert', { title: 'Позвонить', date: '2026-10-22' }),
      ],
    }).expect(200);
    expect(res.body.results.map((r: any) => r.status)).toEqual(['applied', 'applied', 'applied']);
    expect(res.body.results[1].record).toMatchObject({ id: item, version: 1, name: 'Хлеб' });
  });

  it('повтор операции с тем же opId не создаёт дублей и не меняет версию', async () => {
    const c = await signInWithFamily(app);
    const list = uid(), item = uid();
    await c.post('/sync/push', { operations: [op('shoppingList', list, 'upsert', { name: 'L' })] }).expect(200);
    const o = op('shoppingItem', item, 'upsert', { listId: list, name: 'Сыр' });
    const first = await c.post('/sync/push', { operations: [o] }).expect(200);
    const second = await c.post('/sync/push', { operations: [o] }).expect(200);
    const third = await c.post('/sync/push', { operations: [o, o] }).expect(200);
    expect(second.body.results[0]).toEqual(first.body.results[0]);
    expect(third.body.results[0]).toEqual(first.body.results[0]);
    expect(await prisma(app).shoppingItem.count({ where: { id: item } })).toBe(1);
    expect((await prisma(app).shoppingItem.findUnique({ where: { id: item } }))!.version).toBe(1);
    const changes = await prisma(app).change.count({ where: { entityId: item } });
    expect(changes).toBe(1); // повтор не пишет в журнал
  });

  it('после «перезапуска» сервера повтор той же очереди даёт тот же результат', async () => {
    const c = await signInWithFamily(app);
    const list = uid();
    const batch = [op('shoppingList', list, 'upsert', { name: 'До перезапуска' })];
    const before = await c.post('/sync/push', { operations: batch }).expect(200);
    const app2 = await makeApp(); // новый процесс приложения на той же БД
    try {
      const c2 = new Client(app2, c.email, c.accessToken, c.refreshToken, c.userId);
      const after = await c2.post('/sync/push', { operations: batch }).expect(200);
      expect(after.body).toEqual(before.body);
      expect(await prisma(app2).shoppingList.count({ where: { id: list } })).toBe(1);
    } finally {
      await app2.close();
    }
  });

  it('opId, уже использованный другим пользователем, не проходит', async () => {
    const a = await signInWithFamily(app);
    const b = await signInWithFamily(app);
    const o = op('shoppingList', uid(), 'upsert', { name: 'x' });
    await a.post('/sync/push', { operations: [o] }).expect(200);
    const res = await b.post('/sync/push', { operations: [{ ...o, entityId: uid() }] }).expect(200);
    expect(res.body.results[0]).toMatchObject({ status: 'rejected', error: { code: 'OP_ID_TAKEN' } });
  });

  it('pull по курсору: страницы, hasMore, только новое после курсора', async () => {
    const c = await signInWithFamily(app);
    const list = uid();
    await c.post('/sync/push', { operations: [op('shoppingList', list, 'upsert', { name: 'P' }), ...[1, 2, 3].map((i) => op('shoppingItem', uid(), 'upsert', { listId: list, name: `i${i}` }))] }).expect(200);
    const p1 = await c.get('/sync/pull?limit=2').expect(200);
    expect(p1.body.hasMore).toBe(true);
    expect(p1.body.changes.filter((x: any) => x.entity !== 'family')).toHaveLength(2 - p1.body.changes.filter((x: any) => x.entity === 'family').length);
    let cursor = p1.body.cursor;
    let seen = p1.body.changes.length;
    for (let guard = 0; guard < 10; guard++) {
      const p = await c.get(`/sync/pull?limit=2&cursor=${cursor}`).expect(200);
      seen += p.body.changes.length;
      cursor = p.body.cursor;
      if (!p.body.hasMore) break;
    }
    expect(seen).toBe(5); // family + list + 3 items
    const none = await c.get(`/sync/pull?cursor=${cursor}`).expect(200);
    expect(none.body.changes).toEqual([]);
    expect(none.body.cursor).toBe(cursor);
    // новое изменение появляется только после курсора
    await c.post('/sync/push', { operations: [op('shoppingList', list, 'upsert', { name: 'P2' })] }).expect(200);
    const delta = await c.get(`/sync/pull?cursor=${cursor}`).expect(200);
    expect(delta.body.changes).toHaveLength(1);
    expect(delta.body.changes[0].record.name).toBe('P2');
  });

  it('изменения другого участника видны через pull', async () => {
    const a = await signInWithFamily(app);
    const b = await addMember(a);
    const start = (await b.get('/sync/pull').expect(200)).body.cursor;
    const list = uid();
    await a.put(`/shopping/lists/${list}`, { name: 'От А' }).expect(200);
    const delta = await b.get(`/sync/pull?cursor=${start}`).expect(200);
    expect(delta.body.changes.map((c: any) => c.id)).toContain(list);
  });

  describe('конфликты', () => {
    it('удаление приоритетнее устаревшего редактирования', async () => {
      const a = await signInWithFamily(app);
      const b = await addMember(a);
      const list = uid(), item = uid();
      await a.post('/sync/push', { operations: [op('shoppingList', list, 'upsert', {}), op('shoppingItem', item, 'upsert', { listId: list, name: 'Молоко' })] }).expect(200);
      // А удаляет, Б (офлайн, версия 1) редактирует
      await a.post('/sync/push', { operations: [op('shoppingItem', item, 'delete')] }).expect(200);
      const res = await b.post('/sync/push', { operations: [op('shoppingItem', item, 'upsert', { name: 'Кефир' }, 1)] }).expect(200);
      expect(res.body.results[0]).toMatchObject({ status: 'rejected', error: { code: 'ENTITY_DELETED' } });
      expect(res.body.results[0].record.deletedAt).toBeTruthy(); // клиент получает актуальную запись-tombstone
      expect((await prisma(app).shoppingItem.findUnique({ where: { id: item } }))!.name).toBe('Молоко');
    });

    it('редактирование, затем удаление: удаление побеждает; повторное удаление идемпотентно', async () => {
      const a = await signInWithFamily(app);
      const list = uid(), item = uid();
      await a.post('/sync/push', { operations: [op('shoppingList', list, 'upsert', {}), op('shoppingItem', item, 'upsert', { listId: list, name: 'Яйца' })] }).expect(200);
      const r = await a.post('/sync/push', { operations: [op('shoppingItem', item, 'upsert', { name: 'Яйца С1' }, 1), op('shoppingItem', item, 'delete'), op('shoppingItem', item, 'delete')] }).expect(200);
      expect(r.body.results.map((x: any) => x.status)).toEqual(['applied', 'applied', 'applied']);
      expect(r.body.results[2].record.deletedAt).toBeTruthy();
    });

    it('устаревший baseVersion: правка принята (last-accepted-write-wins), conflict=true, возвращена актуальная запись', async () => {
      const a = await signInWithFamily(app);
      const b = await addMember(a);
      const list = uid(), item = uid();
      await a.post('/sync/push', { operations: [op('shoppingList', list, 'upsert', {}), op('shoppingItem', item, 'upsert', { listId: list, name: 'Хлеб', quantity: 1 })] }).expect(200);
      await a.post('/sync/push', { operations: [op('shoppingItem', item, 'upsert', { quantity: 3 }, 1)] }).expect(200); // → v2
      const res = await b.post('/sync/push', { operations: [op('shoppingItem', item, 'upsert', { note: 'Тёмный' }, 1)] }).expect(200);
      expect(res.body.results[0]).toMatchObject({ status: 'applied', conflict: true });
      expect(res.body.results[0].record).toMatchObject({ quantity: 3, note: 'Тёмный', version: 3 }); // чужие поля сохранены
    });

    it('невалидный payload отклоняется операцией, остальная пачка применяется', async () => {
      const c = await signInWithFamily(app);
      const res = await c.post('/sync/push', {
        operations: [op('shoppingList', uid(), 'upsert', { name: 'ok' }), op('shoppingItem', uid(), 'upsert', { listId: uid(), name: '' }), op('taskOccurrence', uid(), 'upsert', { title: 'x', date: 'вчера' })],
      }).expect(200);
      expect(res.body.results.map((r: any) => r.status)).toEqual(['applied', 'rejected', 'rejected']);
      expect(res.body.results[2].error.code).toBe('VALIDATION_ERROR');
    });

    it('неизвестная сущность и пустая пачка → 400', async () => {
      const c = await signInWithFamily(app);
      await c.post('/sync/push', { operations: [] }).expect(400);
      await c.post('/sync/push', { operations: [op('subscription', uid(), 'upsert', {})] }).expect(400);
    });
  });

  describe('WebSocket /ws', () => {
    let port: number;
    beforeAll(async () => {
      await app.listen(0);
      port = (app.getHttpServer().address() as any).port;
    });
    const connect = (token: string) =>
      new Promise<WebSocket>((resolve, reject) => {
        const ws = new WebSocket(`ws://localhost:${port}/ws?token=${token}`);
        ws.once('open', () => resolve(ws));
        ws.once('error', reject);
        ws.once('unexpected-response', (_req, res) => reject(new Error(`HTTP ${res.statusCode}`)));
      });
    const nextMessage = (ws: WebSocket, type: string) =>
      new Promise<any>((resolve, reject) => {
        const t = setTimeout(() => reject(new Error('нет сообщения')), 5000);
        ws.on('message', (d) => {
          const m = JSON.parse(d.toString());
          if (m.type === type) {
            clearTimeout(t);
            resolve(m);
          }
        });
      });

    it('без валидного токена соединение отклоняется', async () => {
      await expect(connect('bad')).rejects.toThrow(/401/);
    });

    it('участники семьи получают сигнал changed{cursor}; другая семья — нет; после сигнала данные берутся через pull', async () => {
      const a = await signInWithFamily(app);
      const b = await addMember(a);
      const other = await signInWithFamily(app);
      const wsB = await connect(b.accessToken);
      const wsOther = await connect(other.accessToken);
      let foreign = 0;
      wsOther.on('message', (d) => JSON.parse(d.toString()).type === 'changed' && foreign++);
      const changed = nextMessage(wsB, 'changed');
      const start = (await b.get('/sync/pull').expect(200)).body.cursor;
      const list = uid();
      await a.put(`/shopping/lists/${list}`, { name: 'Живой' }).expect(200);
      const msg = await changed;
      expect(Number(msg.cursor)).toBeGreaterThan(Number(start));
      const pull = await b.get(`/sync/pull?cursor=${start}`).expect(200);
      expect(pull.body.changes.some((c: any) => c.id === list)).toBe(true);
      await new Promise((r) => setTimeout(r, 200));
      expect(foreign).toBe(0);
      wsB.close();
      wsOther.close();
    });

    it('удалённый из семьи участник отключается от канала', async () => {
      const a = await signInWithFamily(app);
      const b = await addMember(a);
      const ws = await connect(b.accessToken);
      const closed = new Promise<number>((resolve) => ws.once('close', (code) => resolve(code)));
      await a.del(`/families/me/members/${b.userId}`).expect(204);
      expect(await closed).toBe(4001);
    });
  });
});
