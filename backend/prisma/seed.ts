/**
 * Демо-данные семьи Смирновых. Все имена и документы вымышленные; файлы — синтетические PDF-заглушки.
 * Запуск: npm run seed (идемпотентно: пересоздаёт данные демо-семьи).
 */
import { PrismaClient } from '@prisma/client';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { loadConfig } from '../src/common/config';
import { addDays, todayUtc } from '../src/common/dates';

const prisma = new PrismaClient();

const ID = {
  family: '5eed0000-0000-4000-8000-000000000001',
  anna: '5eed0000-0000-4000-8000-0000000000a1',
  mikhail: '5eed0000-0000-4000-8000-0000000000a2',
  sonya: '5eed0000-0000-4000-8000-0000000000a3',
  list: '5eed0000-0000-4000-8000-0000000000b1',
};
let n = 0;
const uid = (prefix: string) => `5eed0000-0000-4000-8000-${prefix}${String(++n).padStart(12 - prefix.length, '0')}`;

/** Минимальный валидный PDF с одной страницей и надписью. */
function demoPdf(title: string): Buffer {
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 420 595] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  const text = `BT /F1 20 Tf 40 520 Td (DEMO DOCUMENT) Tj 0 -30 Td /F1 12 Tf (${title.replace(/[^\x20-\x7e]/g, '?')}) Tj 0 -24 Td (Synthetic file for demo data. No personal data.) Tj ET`;
  objs[3] = `<< /Length ${text.length} >>\nstream\n${text}\nendstream`;
  let out = '%PDF-1.4\n';
  const offsets: number[] = [];
  objs.forEach((o, i) => {
    offsets.push(out.length);
    out += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = out.length;
  out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${offsets.map((o) => `${String(o).padStart(10, '0')} 00000 n \n`).join('')}`;
  out += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(out, 'latin1');
}

async function main() {
  const cfg = loadConfig();
  const today = todayUtc();

  // Чистим прежние демо-данные (каскадом).
  await prisma.change.deleteMany({ where: { familyId: ID.family } });
  await prisma.shoppingList.deleteMany({ where: { familyId: ID.family } });
  await prisma.taskOccurrence.deleteMany({ where: { familyId: ID.family } });
  await prisma.taskSeries.deleteMany({ where: { familyId: ID.family } });
  await prisma.document.deleteMany({ where: { familyId: ID.family } });
  await prisma.family.deleteMany({ where: { id: ID.family } });

  const people = [
    { id: ID.anna, email: 'anna@smirnovy.example', name: 'Анна', role: 'admin' as const, color: 0 },
    { id: ID.mikhail, email: 'mikhail@smirnovy.example', name: 'Михаил', role: 'member' as const, color: 1 },
    { id: ID.sonya, email: 'sonya@smirnovy.example', name: 'Соня', role: 'member' as const, color: 2 },
  ];
  for (const p of people) {
    await prisma.user.upsert({ where: { id: p.id }, update: { email: p.email }, create: { id: p.id, email: p.email } });
    await prisma.notificationSettings.upsert({ where: { userId: p.id }, update: {}, create: { userId: p.id } });
  }
  await prisma.family.create({ data: { id: ID.family, name: 'Смирновы', createdById: ID.anna } });
  for (const p of people) {
    await prisma.familyMember.deleteMany({ where: { userId: p.id } });
    await prisma.familyMember.create({ data: { familyId: ID.family, userId: p.id, role: p.role, displayName: p.name, color: p.color } });
  }

  const base = { familyId: ID.family, authorId: ID.anna };
  const touched: { entity: string; id: string }[] = [{ entity: 'family', id: ID.family }];
  const track = (entity: string, id: string) => touched.push({ entity, id });

  // Покупки
  await prisma.shoppingList.create({ data: { id: ID.list, ...base, name: 'Покупки на неделю' } });
  track('shoppingList', ID.list);
  const items: Array<[string, number, string, string, string | null, string | null, boolean]> = [
    ['Помидоры', 1, 'кг', 'Овощи и фрукты', null, null, false],
    ['Огурцы', 0.5, 'кг', 'Овощи и фрукты', null, null, false],
    ['Молоко', 2, 'л', 'Молочное', ID.mikhail, 'Без лактозы', false],
    ['Йогурт', 4, 'шт', 'Молочное', null, null, false],
    ['Гречка', 1, 'кг', 'Бакалея', null, null, false],
    ['Хлеб', 1, 'шт', 'Бакалея', ID.anna, null, false],
    ['Салфетки', 2, 'уп', 'Дом', null, null, false],
    ['Яйца', 10, 'шт', 'Молочное', null, null, true],
  ];
  for (const [name, quantity, unit, category, assigneeId, note, purchased] of items) {
    const id = uid('b2');
    await prisma.shoppingItem.create({
      data: { id, ...base, listId: ID.list, name, quantity, unit, category, assigneeId, note,
        purchased, purchasedById: purchased ? ID.mikhail : null, purchasedAt: purchased ? new Date() : null },
    });
    track('shoppingItem', id);
  }

  // Дела
  const task = async (title: string, date: string, time: string | null, assigneeId: string | null, extra: Record<string, unknown> = {}) => {
    const id = uid('c1');
    await prisma.taskOccurrence.create({ data: { id, ...base, title, date, time, assigneeId, ...extra } as any });
    track('taskOccurrence', id);
    return id;
  };
  await task('Забрать Соню с танцев', today, '18:30', ID.mikhail, { place: 'Студия «Ритм»' });
  const plants = await task('Полить растения', today, '19:00', ID.sonya, { note: 'Фикус и монстера' });
  const cl = uid('c2');
  await prisma.checklistItem.create({ data: { id: cl, ...base, occurrenceId: plants, title: 'Фикус', position: 0 } });
  track('checklistItem', cl);
  const cl2 = uid('c2');
  await prisma.checklistItem.create({ data: { id: cl2, ...base, occurrenceId: plants, title: 'Монстера', position: 1 } });
  track('checklistItem', cl2);
  await task('Записаться к стоматологу', addDays(today, 1), '10:00', ID.anna, { reminderMinutes: 60 });
  await task('Оплатить интернет', addDays(today, -1), null, ID.anna); // просрочено
  await task('Вынести мусор', today, '08:00', ID.anna, { status: 'done', completedById: ID.anna, completedAt: new Date() });

  // Документы (метаданные + синтетические файлы)
  const docs: Array<{ title: string; category: 'personal' | 'health' | 'home' | 'travel'; ownerId: string; number: string | null; expiresAt: string | null; access: 'author_only' | 'selected' | 'family'; selected?: string[] }> = [
    { title: 'Полис ДМС · Соня', category: 'health', ownerId: ID.sonya, number: 'ДМС-0000-0000', expiresAt: '2027-08-31', access: 'family' },
    { title: 'Паспорт Анны', category: 'personal', ownerId: ID.anna, number: '00 00 000000', expiresAt: null, access: 'author_only' },
    { title: 'Свидетельство о рождении Сони', category: 'personal', ownerId: ID.sonya, number: 'I-ИК 000000', expiresAt: null, access: 'selected', selected: [ID.mikhail] },
    { title: 'Страховка квартиры', category: 'home', ownerId: ID.anna, number: null, expiresAt: addDays(today, 40), access: 'family' },
  ];
  for (const d of docs) {
    const id = uid('d1');
    const pdf = demoPdf(d.title);
    const objectKey = `families/${ID.family}/documents/${id}`;
    await prisma.document.create({
      data: {
        id, ...base, title: d.title, category: d.category, ownerId: d.ownerId, number: d.number, expiresAt: d.expiresAt, access: d.access,
        fileName: `${d.title.replace(/[^A-Za-zА-Яа-я0-9]+/g, '_')}.pdf`, mimeType: 'application/pdf', sizeBytes: pdf.length, objectKey, status: 'ready',
        searchText: [d.title, d.number ?? '', 'demo.pdf'].join(' ').toLocaleLowerCase('ru-RU'),
        permissions: { create: (d.selected ?? []).map((userId) => ({ userId })) },
      },
    });
    track('document', id);
    if (cfg.storage.driver === 'local') {
      const path = resolve(cfg.storage.localDir, objectKey);
      await mkdir(dirname(path), { recursive: true });
      await writeFile(path, pdf);
    }
  }
  if (cfg.storage.driver !== 'local') console.warn('STORAGE_DRIVER=s3: файлы-заглушки не загружены, метаданные созданы без объектов.');

  await prisma.change.createMany({ data: touched.map((t) => ({ familyId: ID.family, entity: t.entity, entityId: t.id })) });
  console.log('Демо-семья «Смирновы» создана. Вход: anna@smirnovy.example / mikhail@smirnovy.example / sonya@smirnovy.example (код придёт в Mailpit, http://localhost:8025).');
}

main().finally(() => prisma.$disconnect());
