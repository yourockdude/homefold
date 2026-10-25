import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { addMember, createReadyDoc, makeApp, prisma, signIn, signInWithFamily, uid } from './helpers';

describe('Семья, приглашения, роли', () => {
  let app: INestApplication;
  beforeAll(async () => (app = await makeApp()));
  afterAll(() => app.close());

  it('создатель семьи — администратор; без семьи данные недоступны (NO_FAMILY)', async () => {
    const c = await signIn(app);
    const denied = await c.get('/shopping/lists').expect(403);
    expect(denied.body.error.code).toBe('NO_FAMILY');
    const res = await c.post('/families', { name: 'Смирновы', displayName: 'Анна' }).expect(201);
    expect(res.body.myRole).toBe('admin');
    expect(res.body.members).toHaveLength(1);
    await c.post('/families', { name: 'Ещё', displayName: 'Анна' }).expect(409);
  });

  it('валидация названия семьи и имени', async () => {
    const c = await signIn(app);
    const res = await c.post('/families', { name: '  ', displayName: '' }).expect(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('приглашение: предпросмотр показывает семью и пригласившего, принятие добавляет участника', async () => {
    const admin = await signInWithFamily(app, 'Смирновы', 'Анна');
    const inv = await admin.post('/invitations').expect(201);
    expect(inv.body.url).toContain(inv.body.token);

    const preview = await request(app.getHttpServer()).get('/invitations/preview').query({ token: inv.body.token }).expect(200);
    expect(preview.body).toMatchObject({ familyName: 'Смирновы', invitedBy: 'Анна' });

    const guest = await signIn(app);
    await guest.post('/invitations/accept', { token: inv.body.token, displayName: 'Михаил' }).expect(200);
    const fam = await guest.get('/families/me').expect(200);
    expect(fam.body.myRole).toBe('member');
    expect(fam.body.members.map((m: any) => m.displayName)).toEqual(['Анна', 'Михаил']);
  });

  it('приглашение одноразовое', async () => {
    const admin = await signInWithFamily(app);
    const inv = await admin.post('/invitations').expect(201);
    await (await signIn(app)).post('/invitations/accept', { token: inv.body.token, displayName: 'А' }).expect(200);
    const second = await (await signIn(app)).post('/invitations/accept', { token: inv.body.token, displayName: 'Б' }).expect(410);
    expect(second.body.error.code).toBe('INVITATION_INVALID');
  });

  it('отозванное приглашение не работает ни для предпросмотра, ни для принятия', async () => {
    const admin = await signInWithFamily(app);
    const inv = await admin.post('/invitations').expect(201);
    await admin.del(`/invitations/${inv.body.id}`).expect(204);
    await request(app.getHttpServer()).get('/invitations/preview').query({ token: inv.body.token }).expect(410);
    await (await signIn(app)).post('/invitations/accept', { token: inv.body.token, displayName: 'Б' }).expect(410);
    expect((await admin.get('/invitations').expect(200)).body.items).toHaveLength(0);
  });

  it('просроченное приглашение → 410', async () => {
    const admin = await signInWithFamily(app);
    const inv = await admin.post('/invitations').expect(201);
    const { PrismaService } = await import('../src/prisma/prisma.service');
    await app.get(PrismaService).invitation.update({ where: { id: inv.body.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
    await request(app.getHttpServer()).get('/invitations/preview').query({ token: inv.body.token }).expect(410);
  });

  it('создавать и отзывать приглашения может только администратор', async () => {
    const admin = await signInWithFamily(app);
    const member = await addMember(admin);
    await member.post('/invitations').expect(403);
    const inv = await admin.post('/invitations').expect(201);
    await member.del(`/invitations/${inv.body.id}`).expect(403);
  });

  it('пользователь уже в семье не может принять другое приглашение', async () => {
    const a = await signInWithFamily(app);
    const b = await signInWithFamily(app);
    const inv = await a.post('/invitations').expect(201);
    const res = await b.post('/invitations/accept', { token: inv.body.token, displayName: 'X' }).expect(409);
    expect(res.body.error.code).toBe('ALREADY_IN_FAMILY');
  });

  it('бесплатный тариф: четвёртый участник → 402 PREMIUM_REQUIRED (members)', async () => {
    const admin = await signInWithFamily(app);
    await addMember(admin, 'Второй');
    await addMember(admin, 'Третий');
    const res = await admin.post('/invitations').expect(402);
    expect(res.body.error).toMatchObject({ code: 'PREMIUM_REQUIRED', details: { feature: 'members' } });
    await admin.post('/billing/dev/mock-purchase', {}).expect(200);
    await admin.post('/invitations').expect(201);
  });

  it('последнего администратора нельзя разжаловать, он не может выйти или удалить аккаунт без передачи роли', async () => {
    const admin = await signInWithFamily(app);
    const member = await addMember(admin);
    let res = await admin.patch(`/families/me/members/${admin.userId}`, { role: 'member' }).expect(409);
    expect(res.body.error.code).toBe('LAST_ADMIN');
    res = await admin.post('/families/me/leave').expect(409);
    expect(res.body.error.code).toBe('LAST_ADMIN');
    res = await admin.del('/account').expect(409);
    expect(res.body.error.code).toBe('LAST_ADMIN');

    await admin.patch(`/families/me/members/${member.userId}`, { role: 'admin' }).expect(200);
    await admin.post('/families/me/leave').expect(204);
    const fam = await member.get('/families/me').expect(200);
    expect(fam.body.members).toHaveLength(1);
    await admin.get('/families/me').expect(403); // больше не в семье
  });

  it('участник не может менять роли и удалять других; админ может удалить участника', async () => {
    const admin = await signInWithFamily(app);
    const member = await addMember(admin);
    await member.patch(`/families/me/members/${admin.userId}`, { role: 'member' }).expect(403);
    await member.del(`/families/me/members/${admin.userId}`).expect(403);
    await admin.del(`/families/me/members/${member.userId}`).expect(204);
    await member.get('/shopping/lists').expect(403);
  });

  it('участник может сменить собственное имя и цвет', async () => {
    const admin = await signInWithFamily(app);
    const member = await addMember(admin);
    const res = await member.patch(`/families/me/members/${member.userId}`, { displayName: 'Миша', color: 3 }).expect(200);
    expect(res.body.members.find((m: any) => m.userId === member.userId)).toMatchObject({ displayName: 'Миша', color: 3 });
  });

  it('удаление аккаунта: сессия закрыта, email освобождён, семья остаётся', async () => {
    const admin = await signInWithFamily(app);
    const member = await addMember(admin);
    await member.del('/account').expect(204);
    await member.get('/me').expect(401);
    const fam = await admin.get('/families/me').expect(200);
    expect(fam.body.members).toHaveLength(1);
    await prisma(app).loginCode.deleteMany({ where: { email: member.email } }); // снимаем таймер повторной отправки
    const again = await signIn(app, member.email); // тот же email — новый пустой аккаунт
    expect(again.userId).not.toBe(member.userId);
  });

  it('при выходе участника его приватные документы удаляются, назначения сбрасываются', async () => {
    const admin = await signInWithFamily(app);
    const member = await addMember(admin);
    const doc = await createReadyDoc(member, { access: 'author_only' });
    const itemList = uid();
    await admin.put(`/shopping/lists/${itemList}`, { name: 'Список' }).expect(200);
    const itemId = uid();
    await admin.put(`/shopping/items/${itemId}`, { listId: itemList, name: 'Молоко', assigneeId: member.userId }).expect(200);
    await member.post('/families/me/leave').expect(204);
    const item = await admin.get(`/shopping/lists/${itemList}`).expect(200);
    expect(item.body.items[0].assigneeId).toBeNull();
    // приватный документ вышедшего удалён
    const { PrismaService } = await import('../src/prisma/prisma.service');
    const row = await app.get(PrismaService).document.findUnique({ where: { id: doc.id } });
    expect(row!.deletedAt).not.toBeNull();
  });

  describe('изоляция семей', () => {
    it('чужая семья не видит и не меняет данные по прямым id', async () => {
      const a = await signInWithFamily(app, 'А', 'Аня');
      const b = await signInWithFamily(app, 'Б', 'Боря');
      const listId = uid();
      const itemId = uid();
      const occId = uid();
      await a.put(`/shopping/lists/${listId}`, { name: 'Покупки А' }).expect(200);
      await a.put(`/shopping/items/${itemId}`, { listId, name: 'Секрет' }).expect(200);
      await a.put(`/tasks/occurrences/${occId}`, { title: 'Дело А', date: '2026-10-22' }).expect(200);
      const doc = await createReadyDoc(a, { access: 'family' });

      await b.get(`/shopping/lists/${listId}`).expect(404);
      await b.put(`/shopping/items/${itemId}`, { name: 'Взлом' }).expect(404);
      await b.del(`/shopping/items/${itemId}`).expect(404);
      await b.put(`/shopping/lists/${listId}`, { name: 'Взлом' }).expect(404);
      await b.get(`/tasks/occurrences/${occId}`).expect(404);
      await b.post(`/tasks/occurrences/${occId}/complete`).expect(404);
      await b.get(`/documents/${doc.id}`).expect(404);
      await b.get(`/documents/${doc.id}/download-url`).expect(404);
      await b.patch(`/documents/${doc.id}`, { title: 'Взлом' }).expect(404);
      await b.del(`/documents/${doc.id}`).expect(404);
      await a.get(`/documents/${doc.id}`).expect(200);

      expect((await b.get('/shopping/lists').expect(200)).body.items).toHaveLength(0);
      expect((await b.get('/tasks').expect(200)).body.items).toHaveLength(0);
      expect((await b.get('/documents').expect(200)).body.items).toHaveLength(0);
      const pull = await b.get('/sync/pull').expect(200);
      expect(JSON.stringify(pull.body)).not.toContain('Секрет');
      expect(pull.body.changes.filter((c: any) => c.entity !== 'family')).toHaveLength(0);

      // id чужой записи нельзя «захватить» через sync push
      const res = await b.post('/sync/push', {
        operations: [{ opId: uid(), entity: 'shoppingItem', entityId: itemId, type: 'upsert', payload: { name: 'Взлом' } }],
      }).expect(200);
      expect(res.body.results[0].status).toBe('rejected');
      expect(res.body.results[0].error.code).toBe('NOT_FOUND');
      // чужой ответственный
      await b.put(`/shopping/items/${uid()}`, { listId: (await b.post('/shopping/lists/new', { id: uid() })).body.list.id, name: 'x', assigneeId: a.userId }).expect(400);
    });
  });
});
