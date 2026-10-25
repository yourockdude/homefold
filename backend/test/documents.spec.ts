import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { DocumentsService } from '../src/documents/documents.service';
import { PNG, PDF, addMember, createReadyDoc, makeApp, makePremium, prisma, signInWithFamily, uid, uploadTo } from './helpers';

describe('Документы', () => {
  let app: INestApplication;
  beforeAll(async () => (app = await makeApp()));
  afterAll(() => app.close());

  it('полный цикл: метаданные → прямая загрузка по подписанной ссылке → подтверждение → скачивание', async () => {
    const c = await signInWithFamily(app);
    const id = uid();
    const created = await c.post('/documents', {
      id, title: 'Полис ДМС · Соня', category: 'health', number: 'ДМС-000-000', expiresAt: '2027-08-31', access: 'family',
      fileName: 'polis.pdf', mimeType: 'application/pdf', sizeBytes: PDF.length,
    }).expect(201);
    expect(created.body.document).toMatchObject({ status: 'pending_upload', category: 'health', access: 'family', ownerId: c.userId });
    expect(created.body.document.objectKey).toBeUndefined(); // внутренний ключ не раскрываем
    expect(created.body.upload.url).toContain('/storage/upload/');

    await c.post(`/documents/${id}/confirm`).expect(409); // ещё не загружено
    await uploadTo(app, created.body.upload, PDF).expect(200);
    const conf = await c.post(`/documents/${id}/confirm`).expect(200);
    expect(conf.body.status).toBe('ready');
    await c.post(`/documents/${id}/confirm`).expect(200); // идемпотентно

    const dl = await c.get(`/documents/${id}/download-url`).expect(200);
    expect(dl.body.expiresInSeconds).toBeLessThanOrEqual(300);
    const file = await request(app.getHttpServer()).get(new URL(dl.body.url).pathname).buffer(true).parse((res, cb) => {
      const chunks: Buffer[] = [];
      res.on('data', (d: Buffer) => chunks.push(d));
      res.on('end', () => cb(null, Buffer.concat(chunks)));
    }).expect(200);
    expect((file.body as Buffer).equals(PDF)).toBe(true);
  });

  it('повтор создания с тем же id не плодит дубликатов', async () => {
    const c = await signInWithFamily(app);
    const body = { id: uid(), title: 'Паспорт', fileName: 'p.pdf', mimeType: 'application/pdf', sizeBytes: 100 };
    await c.post('/documents', body).expect(201);
    await c.post('/documents', body).expect(201);
    expect((await c.get('/documents').expect(200)).body.items).toHaveLength(1);
  });

  it('сервер проверяет тип и размер: чужой тип, несовпадение размера, >25 МБ, не-PDF содержимое', async () => {
    const c = await signInWithFamily(app);
    await c.post('/documents', { id: uid(), title: 'x', fileName: 'x.exe', mimeType: 'application/x-msdownload', sizeBytes: 10 }).expect(400);
    await c.post('/documents', { id: uid(), title: 'x', fileName: 'x.pdf', mimeType: 'application/pdf', sizeBytes: 26 * 1024 * 1024 }).expect(400);
    await c.post('/documents', { id: uid(), title: '', fileName: 'x.pdf', mimeType: 'application/pdf', sizeBytes: 10 }).expect(400);

    const id1 = uid();
    const r1 = await c.post('/documents', { id: id1, title: 'Размер', fileName: 'a.pdf', mimeType: 'application/pdf', sizeBytes: PDF.length + 5 }).expect(201);
    await uploadTo(app, r1.body.upload, PDF).expect(200);
    const bad = await c.post(`/documents/${id1}/confirm`).expect(422);
    expect(bad.body.error.code).toBe('UPLOAD_SIZE_MISMATCH');

    const id2 = uid();
    const exe = Buffer.from('MZ\u0090\u0000 это не PDF');
    const r2 = await c.post('/documents', { id: id2, title: 'Тип', fileName: 'b.pdf', mimeType: 'application/pdf', sizeBytes: exe.length }).expect(201);
    await uploadTo(app, r2.body.upload, exe).expect(200);
    expect((await c.post(`/documents/${id2}/confirm`).expect(422)).body.error.code).toBe('UPLOAD_TYPE_MISMATCH');
    // после отказа файл удалён из хранилища — подтвердить нельзя
    await c.post(`/documents/${id2}/confirm`).expect(409);
  });

  it('просроченная или поддельная ссылка загрузки отклоняется', async () => {
    const c = await signInWithFamily(app);
    const r = await c.post('/documents', { id: uid(), title: 'x', fileName: 'x.pdf', mimeType: 'application/pdf', sizeBytes: PDF.length }).expect(201);
    const path = new URL(r.body.upload.url).pathname;
    await request(app.getHttpServer()).put(path + 'x').send(PDF).expect(403);
    await request(app.getHttpServer()).get(path.replace('upload', 'download')).expect(403); // токен «put» не годится для скачивания
  });

  describe('права доступа', () => {
    it('«только автор»: другие участники (и админ) не видят документ ни в списке, ни по id, ни в sync', async () => {
      const admin = await signInWithFamily(app);
      const author = await addMember(admin, 'Автор');
      const doc = await createReadyDoc(author, { access: 'author_only', title: 'Личное' });
      for (const viewer of [admin]) {
        expect((await viewer.get('/documents').expect(200)).body.items).toHaveLength(0);
        await viewer.get(`/documents/${doc.id}`).expect(404);
        await viewer.get(`/documents/${doc.id}/download-url`).expect(404);
        await viewer.patch(`/documents/${doc.id}`, { access: 'family' }).expect(404);
        await viewer.del(`/documents/${doc.id}`).expect(404);
        const pull = await viewer.get('/sync/pull').expect(200);
        expect(JSON.stringify(pull.body)).not.toContain('Личное');
      }
      await author.get(`/documents/${doc.id}`).expect(200);
    });

    it('«выбранные участники»: видят только выбранные; «вся семья»: все', async () => {
      const admin = await signInWithFamily(app);
      const a = await addMember(admin, 'А');
      const b = await addMember(admin, 'Б');
      const sel = await createReadyDoc(admin, { access: 'selected', selectedUserIds: [a.userId], title: 'Для А' });
      await a.get(`/documents/${sel.id}`).expect(200);
      await a.get(`/documents/${sel.id}/download-url`).expect(200);
      await b.get(`/documents/${sel.id}`).expect(404);
      const fam = await createReadyDoc(admin, { access: 'family', title: 'Всем' });
      expect((await b.get('/documents').expect(200)).body.items.map((d: any) => d.id)).toEqual([fam.id]);
    });

    it('«выбранные» требуют участников семьи; чужого пользователя выбрать нельзя', async () => {
      const admin = await signInWithFamily(app);
      const stranger = await signInWithFamily(app);
      const base = { fileName: 'x.pdf', mimeType: 'application/pdf', sizeBytes: 10, title: 'x', access: 'selected' };
      await admin.post('/documents', { id: uid(), ...base, selectedUserIds: [stranger.userId] }).expect(400);
      await admin.post('/documents', { id: uid(), ...base, selectedUserIds: [] }).expect(400);
    });

    it('владелец документа ≠ доступ: ownerId меняется независимо от прав', async () => {
      const admin = await signInWithFamily(app);
      const kid = await addMember(admin, 'Соня');
      const doc = await createReadyDoc(admin, { access: 'author_only', ownerId: kid.userId });
      expect((await admin.get(`/documents/${doc.id}`).expect(200)).body).toMatchObject({ ownerId: kid.userId, authorId: admin.userId, access: 'author_only' });
      await kid.get(`/documents/${doc.id}`).expect(404); // владелец, но доступа нет
    });

    it('менять и удалять может только автор, даже при доступе «вся семья»', async () => {
      const admin = await signInWithFamily(app);
      const m = await addMember(admin);
      const doc = await createReadyDoc(m, { access: 'family' });
      await admin.patch(`/documents/${doc.id}`, { title: 'Чужое' }).expect(403);
      await admin.del(`/documents/${doc.id}`).expect(403);
      await m.patch(`/documents/${doc.id}`, { title: 'Моё' }).expect(200);
    });

    it('отзыв доступа: у потерявшего доступ sync pull отдаёт tombstone (revoked), прямой доступ закрыт', async () => {
      const admin = await signInWithFamily(app);
      const m = await addMember(admin);
      const doc = await createReadyDoc(admin, { access: 'family' });
      const first = await m.get('/sync/pull').expect(200);
      expect(first.body.changes.find((c: any) => c.id === doc.id)).toMatchObject({ deleted: false });
      await admin.patch(`/documents/${doc.id}`, { access: 'author_only' }).expect(200);
      const second = await m.get(`/sync/pull?cursor=${first.body.cursor}`).expect(200);
      expect(second.body.changes.find((c: any) => c.id === doc.id)).toMatchObject({ deleted: true, revoked: true, record: null });
      await m.get(`/documents/${doc.id}/download-url`).expect(404);
    });

    it('отозванный доступ нельзя вернуть операцией из локальной очереди', async () => {
      const admin = await signInWithFamily(app);
      const m = await addMember(admin);
      const doc = await createReadyDoc(admin, { access: 'selected', selectedUserIds: [m.userId] });
      await admin.patch(`/documents/${doc.id}`, { access: 'author_only' }).expect(200);
      const res = await m.post('/sync/push', { operations: [{ opId: uid(), entity: 'document', entityId: doc.id, type: 'upsert', payload: { access: 'family', title: 'Верни' } }] }).expect(200);
      expect(res.body.results[0]).toMatchObject({ status: 'rejected', error: { code: 'NOT_FOUND' } });
    });
  });

  describe('поиск, категории, пагинация', () => {
    it('поиск по названию/номеру, категория, «ничего не найдено»', async () => {
      const c = await signInWithFamily(app);
      await createReadyDoc(c, { title: 'Паспорт Анны', category: 'personal', number: '45 12 345678' });
      await createReadyDoc(c, { title: 'Полис ДМС', category: 'health' });
      expect((await c.get('/documents?q=паспорт').expect(200)).body.items).toHaveLength(1);
      expect((await c.get('/documents?q=345678').expect(200)).body.items).toHaveLength(1);
      expect((await c.get('/documents?category=health').expect(200)).body.items).toHaveLength(1);
      expect((await c.get('/documents?q=несуществующее').expect(200)).body.items).toEqual([]);
      const page = await c.get('/documents?limit=1').expect(200);
      expect(page.body.nextCursor).toBeTruthy();
    });
  });

  describe('лимиты тарифов', () => {
    it('бесплатный: 11-й файл → 402; Plus снимает лимит; размер одного файла ≤25 МБ на обоих', async () => {
      const c = await signInWithFamily(app);
      for (let i = 0; i < 10; i++) await c.post('/documents', { id: uid(), title: `Д${i}`, fileName: 'a.pdf', mimeType: 'application/pdf', sizeBytes: 1000 }).expect(201);
      const res = await c.post('/documents', { id: uid(), title: 'Лишний', fileName: 'a.pdf', mimeType: 'application/pdf', sizeBytes: 1000 }).expect(402);
      expect(res.body.error).toMatchObject({ code: 'PREMIUM_REQUIRED', details: { feature: 'documents' } });
      await makePremium(c);
      await c.post('/documents', { id: uid(), title: 'Лишний', fileName: 'a.pdf', mimeType: 'application/pdf', sizeBytes: 1000 }).expect(201);
      await c.post('/documents', { id: uid(), title: 'Огромный', fileName: 'a.pdf', mimeType: 'application/pdf', sizeBytes: 26 * 1024 * 1024 }).expect(400);
    });

    it('бесплатный: суммарно 100 МБ', async () => {
      const c = await signInWithFamily(app);
      const big = 20 * 1024 * 1024;
      for (let i = 0; i < 4; i++) await c.post('/documents', { id: uid(), title: `Б${i}`, fileName: 'a.pdf', mimeType: 'application/pdf', sizeBytes: big }).expect(201);
      await c.post('/documents', { id: uid(), title: 'Б5', fileName: 'a.pdf', mimeType: 'application/pdf', sizeBytes: big }).expect(201); // ровно 100 МБ
      const res = await c.post('/documents', { id: uid(), title: 'Б6', fileName: 'a.pdf', mimeType: 'application/pdf', sizeBytes: 1024 * 1024 }).expect(402);
      expect(res.body.error.details.feature).toBe('documents');
    });

    it('после окончания подписки документы остаются доступны для просмотра, выгрузки и удаления; новые сверх лимита блокируются', async () => {
      const c = await signInWithFamily(app);
      await makePremium(c);
      const docs = [];
      for (let i = 0; i < 11; i++) docs.push(await createReadyDoc(c, { title: `Файл ${i}` }));
      await c.post('/billing/dev/mock-expire', {}).expect(200);
      expect((await c.get('/documents').expect(200)).body.items).toHaveLength(11);
      await c.get(`/documents/${docs[0].id}/download-url`).expect(200);
      await c.post('/documents', { id: uid(), title: 'Новый', fileName: 'a.pdf', mimeType: 'application/pdf', sizeBytes: 10 }).expect(402);
      await c.del(`/documents/${docs[0].id}`).expect(204);
      expect((await c.get('/documents').expect(200)).body.items).toHaveLength(10);
    });
  });

  it('удаление: документ исчезает, файл удалён из хранилища', async () => {
    const c = await signInWithFamily(app);
    const doc = await createReadyDoc(c, {}, PNG.length ? PDF : PDF);
    const row = await prisma(app).document.findUnique({ where: { id: doc.id } });
    const { Storage } = await import('../src/storage/storage.service');
    const storage = app.get(Storage);
    expect(await storage.head(row!.objectKey)).not.toBeNull();
    await c.del(`/documents/${doc.id}`).expect(204);
    expect(await storage.head(row!.objectKey)).toBeNull();
    await c.get(`/documents/${doc.id}`).expect(404);
  });

  it('очистка незавершённых загрузок', async () => {
    const c = await signInWithFamily(app);
    const id = uid();
    const r = await c.post('/documents', { id, title: 'Брошенный', fileName: 'x.pdf', mimeType: 'application/pdf', sizeBytes: PDF.length }).expect(201);
    await uploadTo(app, r.body.upload, PDF).expect(200); // файл загружен, но не подтверждён
    await prisma(app).document.update({ where: { id }, data: { uploadExpiresAt: new Date(Date.now() - 1000) } });
    const removed = await app.get(DocumentsService).cleanupExpiredUploads();
    expect(removed).toBeGreaterThanOrEqual(1);
    expect(await prisma(app).document.findUnique({ where: { id } })).toBeNull();
    const pull = await c.get('/sync/pull').expect(200);
    expect(pull.body.changes.find((x: any) => x.id === id)).toMatchObject({ deleted: true }); // автор очистит локальную запись
  });

  it('PNG тоже принимается', async () => {
    const c = await signInWithFamily(app);
    const doc = await createReadyDoc(c, { mimeType: 'image/png', fileName: 'scan.png' }, PNG);
    expect(doc.id).toBeTruthy();
  });
});
