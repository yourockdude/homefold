import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { Document, DocumentPermission, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ChangesService } from '../changes/changes.service';
import { PlanService } from '../plan/plan.service';
import { Storage } from '../storage/storage.service';
import { FamilyCtx } from '../common/context';
import { AppError, Err } from '../common/errors';
import { assertMember, defined, guardExisting, requireText, UpsertResult } from '../common/entity';
import { decodeCursor, encodeCursor } from '../common/pagination';
import { isValidDate } from '../common/dates';
import { CreateDocumentDto, UpdateDocumentDto } from './documents.dto';

export const UPLOAD_URL_TTL_SEC = 900;
export const DOWNLOAD_URL_TTL_SEC = 120;
export const PENDING_UPLOAD_TTL_MS = 24 * 3600_000;

type DocWithPerms = Document & { permissions: DocumentPermission[] };

/** Видимость — серверная проверка на каждый объект. Админ не получает доступ к чужим приватным документам. */
export function isVisibleTo(doc: DocWithPerms, userId: string): boolean {
  if (doc.deletedAt) return false;
  if (doc.authorId === userId) return true;
  if (doc.status !== 'ready') return false;
  if (doc.access === 'family') return true;
  return doc.access === 'selected' && doc.permissions.some((p) => p.userId === userId);
}

export function toDocumentDto(doc: DocWithPerms) {
  const { objectKey: _k, uploadExpiresAt: _u, permissions, ...rest } = doc;
  return { ...rest, selectedUserIds: permissions.map((p) => p.userId) };
}

const searchText = (title: string, number: string | null | undefined, fileName: string) =>
  [title, number ?? '', fileName].join(' ').toLocaleLowerCase('ru-RU');

const MAGIC: Record<string, (b: Buffer) => boolean> = {
  'application/pdf': (b) => b.subarray(0, 4).toString('latin1') === '%PDF',
  'image/jpeg': (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  'image/png': (b) => b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
};

@Injectable()
export class DocumentsService {
  private readonly logger = new Logger(DocumentsService.name);
  constructor(
    private readonly prisma: PrismaService,
    private readonly changes: ChangesService,
    private readonly plan: PlanService,
    private readonly storage: Storage,
  ) {}

  private async load(id: string, familyId: string): Promise<DocWithPerms | null> {
    const doc = await this.prisma.document.findUnique({ where: { id }, include: { permissions: true } });
    if (doc && doc.familyId !== familyId) throw Err.notFound('Документ');
    return doc;
  }

  /** Документ, который пользователь вправе видеть; иначе — 404 (существование не раскрываем). */
  private async loadVisible(ctx: FamilyCtx, id: string): Promise<DocWithPerms> {
    const doc = await this.load(id, ctx.familyId);
    if (!doc || !isVisibleTo(doc, ctx.userId)) throw Err.notFound('Документ');
    return doc;
  }

  private async loadOwn(ctx: FamilyCtx, id: string): Promise<DocWithPerms> {
    const doc = await this.loadVisible(ctx, id);
    if (doc.authorId !== ctx.userId) throw Err.forbidden('Менять и удалять документ может только его автор');
    return doc;
  }

  private async resolveSharing(ctx: FamilyCtx, dto: UpdateDocumentDto, current?: DocWithPerms) {
    await assertMember(this.prisma, ctx.familyId, dto.ownerId);
    if (dto.expiresAt && !isValidDate(dto.expiresAt)) throw Err.validation('Некорректная дата окончания срока действия');
    const access = dto.access ?? current?.access ?? 'author_only';
    let selected = dto.selectedUserIds;
    if (access === 'selected') {
      selected = selected ?? current?.permissions.map((p) => p.userId) ?? [];
      selected = [...new Set(selected)].filter((u) => u !== ctx.userId);
      const members = await this.prisma.familyMember.findMany({ where: { familyId: ctx.familyId, userId: { in: selected } }, select: { userId: true } });
      if (members.length !== selected.length) throw Err.validation('Доступ можно дать только участникам семьи');
      if (selected.length === 0) throw Err.validation('Выберите хотя бы одного участника или другой тип доступа');
    } else {
      selected = [];
    }
    return { access, selected, changed: dto.access !== undefined || dto.selectedUserIds !== undefined };
  }

  async create(ctx: FamilyCtx, dto: CreateDocumentDto) {
    const again = await this.load(dto.id, ctx.familyId);
    if (again) {
      // Повтор запроса после сбоя связи: возвращаем ту же запись, дубликата нет.
      if (again.authorId !== ctx.userId || again.deletedAt) throw Err.notFound('Документ');
      return { document: toDocumentDto(again), upload: again.status === 'pending_upload' ? await this.signUpload(again) : null };
    }
    const plan = await this.plan.get(ctx.familyId);
    const usage = await this.prisma.document.aggregate({ where: { familyId: ctx.familyId, deletedAt: null }, _count: true, _sum: { sizeBytes: true } });
    if (plan.limits.documents !== null && usage._count + 1 > plan.limits.documents) {
      throw Err.premium('documents', `В бесплатном тарифе — до ${plan.limits.documents} файлов. Подключите HomeFold Plus`);
    }
    if ((usage._sum.sizeBytes ?? 0) + dto.sizeBytes > plan.limits.totalBytes) {
      throw Err.premium('documents', 'Не хватает места для документов. Подключите HomeFold Plus или удалите ненужные файлы');
    }
    const { access, selected } = await this.resolveSharing(ctx, dto);
    const title = requireText(dto.title, 'Название');
    const doc = await this.prisma.document.create({
      data: {
        id: dto.id, familyId: ctx.familyId, authorId: ctx.userId,
        title, category: dto.category ?? 'personal', ownerId: dto.ownerId ?? ctx.userId,
        number: dto.number?.trim() || null, expiresAt: dto.expiresAt ?? null, access,
        searchText: searchText(title, dto.number?.trim(), dto.fileName),
        fileName: dto.fileName, mimeType: dto.mimeType, sizeBytes: dto.sizeBytes,
        objectKey: `families/${ctx.familyId}/documents/${dto.id}`,
        uploadExpiresAt: new Date(Date.now() + PENDING_UPLOAD_TTL_MS),
        permissions: { create: selected.map((userId) => ({ userId })) },
      },
      include: { permissions: true },
    });
    await this.changes.record(ctx.familyId, 'document', doc.id);
    return { document: toDocumentDto(doc), upload: await this.signUpload(doc) };
  }

  private signUpload(doc: Document) {
    return this.storage.presignPut(doc.objectKey, doc.mimeType, UPLOAD_URL_TTL_SEC);
  }

  /** Новая подписанная ссылка для повторной загрузки (ошибка с повтором). */
  async uploadUrl(ctx: FamilyCtx, id: string) {
    const doc = await this.loadOwn(ctx, id);
    if (doc.status !== 'pending_upload') throw Err.conflict('ALREADY_UPLOADED', 'Файл уже загружен');
    await this.prisma.document.update({ where: { id }, data: { uploadExpiresAt: new Date(Date.now() + PENDING_UPLOAD_TTL_MS) } });
    return this.signUpload(doc);
  }

  /** Сервер сам проверяет, что файл в хранилище: размер, тип по сигнатуре, завершённость. */
  async confirm(ctx: FamilyCtx, id: string) {
    const doc = await this.loadOwn(ctx, id);
    if (doc.status === 'ready') return toDocumentDto(doc);
    const obj = await this.storage.head(doc.objectKey);
    if (!obj) throw new AppError(409, 'UPLOAD_INCOMPLETE', 'Файл ещё не загружен');
    const reject = async (code: string, message: string) => {
      await this.storage.delete(doc.objectKey).catch(() => undefined);
      throw new AppError(422, code, message);
    };
    if (obj.size !== doc.sizeBytes) await reject('UPLOAD_SIZE_MISMATCH', 'Размер загруженного файла не совпадает с заявленным');
    const head = await this.storage.readHead(doc.objectKey, 8);
    if (!MAGIC[doc.mimeType]?.(head)) await reject('UPLOAD_TYPE_MISMATCH', 'Содержимое файла не соответствует PDF, JPEG или PNG');
    const updated = await this.prisma.document.update({
      where: { id }, data: { status: 'ready', uploadExpiresAt: null, version: { increment: 1 } }, include: { permissions: true },
    });
    await this.changes.record(ctx.familyId, 'document', id);
    return toDocumentDto(updated);
  }

  async update(ctx: FamilyCtx, id: string, dto: UpdateDocumentDto, baseVersion?: number): Promise<UpsertResult<ReturnType<typeof toDocumentDto>>> {
    const current = guardExisting(await this.load(id, ctx.familyId), ctx.familyId);
    if (!current || !isVisibleTo(current, ctx.userId)) throw Err.notFound('Документ');
    if (current.authorId !== ctx.userId) throw Err.forbidden('Менять и удалять документ может только его автор');
    const sharing = await this.resolveSharing(ctx, dto, current);
    const data = defined({
      title: dto.title === undefined ? undefined : requireText(dto.title, 'Название'),
      category: dto.category,
      ownerId: dto.ownerId,
      number: dto.number === undefined ? undefined : dto.number?.trim() || null,
      expiresAt: dto.expiresAt,
      access: sharing.changed ? sharing.access : undefined,
    });
    const next = { title: (data.title as string | undefined) ?? current.title, number: 'number' in data ? (data.number as string | null) : current.number };
    const withSearch = { ...data, searchText: searchText(next.title, next.number, current.fileName) };
    const updated = await this.prisma.$transaction(async (tx) => {
      if (sharing.changed) {
        await tx.documentPermission.deleteMany({ where: { documentId: id } });
        if (sharing.selected.length) await tx.documentPermission.createMany({ data: sharing.selected.map((userId) => ({ documentId: id, userId })) });
      }
      return tx.document.update({ where: { id }, data: { ...withSearch, version: { increment: 1 } }, include: { permissions: true } });
    });
    // Запись в журнале: у тех, кто потерял доступ, следующий pull вернёт tombstone — локальная копия очистится.
    await this.changes.record(ctx.familyId, 'document', id);
    return { record: toDocumentDto(updated), created: false, conflict: baseVersion !== undefined && baseVersion < current.version };
  }

  async remove(ctx: FamilyCtx, id: string) {
    const doc = await this.load(id, ctx.familyId);
    if (!doc || doc.deletedAt) return;
    if (doc.authorId !== ctx.userId) {
      if (!isVisibleTo(doc, ctx.userId)) throw Err.notFound('Документ');
      throw Err.forbidden('Менять и удалять документ может только его автор');
    }
    const updated = await this.prisma.document.update({ where: { id }, data: { deletedAt: new Date(), version: { increment: 1 } }, include: { permissions: true } });
    await this.storage.delete(doc.objectKey).catch((e) => this.logger.warn(`Файл не удалён из хранилища: ${(e as Error).message}`));
    await this.changes.record(ctx.familyId, 'document', id);
    return toDocumentDto(updated);
  }

  async downloadUrl(ctx: FamilyCtx, id: string) {
    const doc = await this.loadVisible(ctx, id);
    if (doc.status !== 'ready') throw Err.conflict('UPLOAD_INCOMPLETE', 'Файл ещё не загружен');
    return { url: await this.storage.presignGet(doc.objectKey, doc.fileName, DOWNLOAD_URL_TTL_SEC), expiresInSeconds: DOWNLOAD_URL_TTL_SEC, fileName: doc.fileName, mimeType: doc.mimeType };
  }

  async get(ctx: FamilyCtx, id: string) {
    return toDocumentDto(await this.loadVisible(ctx, id));
  }

  async list(ctx: FamilyCtx, q: { category?: string; q?: string; cursor?: string; limit?: number }) {
    const limit = q.limit ?? 50;
    const cut = decodeCursor(q.cursor);
    const search = q.q?.trim();
    const and: Prisma.DocumentWhereInput[] = [
      { OR: [{ authorId: ctx.userId }, { status: 'ready', access: 'family' }, { status: 'ready', access: 'selected', permissions: { some: { userId: ctx.userId } } }] },
    ];
    if (search) {
      and.push({ searchText: { contains: search.toLocaleLowerCase('ru-RU') } });
    }
    if (cut) and.push({ OR: [{ createdAt: { lt: cut.createdAt } }, { createdAt: cut.createdAt, id: { lt: cut.id } }] });
    const rows = await this.prisma.document.findMany({
      where: { familyId: ctx.familyId, deletedAt: null, ...(q.category ? { category: q.category as any } : {}), AND: and },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
      include: { permissions: true },
    });
    const items = rows.slice(0, limit);
    return { items: items.map(toDocumentDto), nextCursor: rows.length > limit ? encodeCursor(items[items.length - 1].createdAt, items[items.length - 1].id) : null };
  }

  async usage(ctx: FamilyCtx) {
    const [plan, agg] = await Promise.all([
      this.plan.get(ctx.familyId),
      this.prisma.document.aggregate({ where: { familyId: ctx.familyId, deletedAt: null }, _count: true, _sum: { sizeBytes: true } }),
    ]);
    return { count: agg._count, bytes: agg._sum.sizeBytes ?? 0, maxCount: plan.limits.documents, maxBytes: plan.limits.totalBytes, maxFileBytes: plan.maxFileBytes };
  }

  /** Незавершённые загрузки старше TTL удаляются вместе с возможным «хвостом» в хранилище. */
  @Cron('*/15 * * * *')
  async cleanupExpiredUploads(): Promise<number> {
    const stale = await this.prisma.document.findMany({ where: { status: 'pending_upload', uploadExpiresAt: { lt: new Date() } } });
    for (const d of stale) {
      await this.changes.record(d.familyId, 'document', d.id); // автор получит tombstone при pull
      await this.storage.delete(d.objectKey).catch(() => undefined);
      await this.prisma.document.delete({ where: { id: d.id } });
    }
    return stale.length;
  }
}
