import { Global, Injectable, Module } from '@nestjs/common';
import { mkdir, readFile, rm, stat, open, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { SignJWT, jwtVerify } from 'jose';
import { loadConfig } from '../common/config';

export interface PresignedUpload {
  url: string;
  method: 'PUT';
  headers: Record<string, string>;
  expiresInSeconds: number;
}

export interface StoredObject {
  size: number;
  contentType?: string;
}

export abstract class Storage {
  abstract presignPut(key: string, contentType: string, ttlSec: number): Promise<PresignedUpload>;
  abstract presignGet(key: string, fileName: string, ttlSec: number): Promise<string>;
  abstract head(key: string): Promise<StoredObject | null>;
  abstract readHead(key: string, bytes: number): Promise<Buffer>;
  abstract delete(key: string): Promise<void>;
}

/** Файловая реализация для dev/тестов: «подписанные» URL — короткоживущие JWT на /storage/*. */
export class LocalStorage extends Storage {
  constructor(private readonly dir: string, private readonly baseUrl: string, private readonly secret: string) {
    super();
  }
  private path(key: string) {
    const p = resolve(this.dir, key);
    if (!p.startsWith(resolve(this.dir))) throw new Error('Некорректный ключ');
    return p;
  }
  private sign(claims: Record<string, unknown>, ttlSec: number) {
    return new SignJWT(claims).setProtectedHeader({ alg: 'HS256' }).setIssuer('ryadom-storage').setExpirationTime(`${ttlSec}s`).sign(new TextEncoder().encode(this.secret));
  }
  async verifyToken(token: string, op: 'put' | 'get') {
    const { payload } = await jwtVerify(token, new TextEncoder().encode(this.secret), { issuer: 'ryadom-storage' });
    if (payload.op !== op) throw new Error('wrong op');
    return payload as { key: string; ct?: string; fn?: string };
  }
  async presignPut(key: string, contentType: string, ttlSec: number): Promise<PresignedUpload> {
    const token = await this.sign({ op: 'put', key, ct: contentType }, ttlSec);
    return { url: `${this.baseUrl}/storage/upload/${token}`, method: 'PUT', headers: { 'Content-Type': contentType }, expiresInSeconds: ttlSec };
  }
  async presignGet(key: string, fileName: string, ttlSec: number) {
    return `${this.baseUrl}/storage/download/${await this.sign({ op: 'get', key, fn: fileName }, ttlSec)}`;
  }
  async write(key: string, data: Buffer) {
    const p = this.path(key);
    await mkdir(dirname(p), { recursive: true });
    await writeFile(p, data);
  }
  async read(key: string) {
    return readFile(this.path(key));
  }
  async head(key: string) {
    try {
      return { size: (await stat(this.path(key))).size };
    } catch {
      return null;
    }
  }
  async readHead(key: string, bytes: number) {
    const fh = await open(this.path(key), 'r');
    try {
      const buf = Buffer.alloc(bytes);
      const { bytesRead } = await fh.read(buf, 0, bytes, 0);
      return buf.subarray(0, bytesRead);
    } finally {
      await fh.close();
    }
  }
  async delete(key: string) {
    await rm(this.path(key), { force: true });
  }
}

export class S3Storage extends Storage {
  private readonly client: S3Client;
  private readonly bucket: string;
  constructor() {
    super();
    const s3 = loadConfig().storage.s3;
    this.bucket = s3.bucket;
    this.client = new S3Client({
      region: s3.region,
      endpoint: s3.endpoint,
      forcePathStyle: s3.forcePathStyle,
      credentials: s3.accessKeyId && s3.secretAccessKey ? { accessKeyId: s3.accessKeyId, secretAccessKey: s3.secretAccessKey } : undefined,
    });
  }
  async presignPut(key: string, contentType: string, ttlSec: number): Promise<PresignedUpload> {
    const url = await getSignedUrl(this.client, new PutObjectCommand({ Bucket: this.bucket, Key: key, ContentType: contentType }), { expiresIn: ttlSec });
    return { url, method: 'PUT', headers: { 'Content-Type': contentType }, expiresInSeconds: ttlSec };
  }
  presignGet(key: string, fileName: string, ttlSec: number) {
    return getSignedUrl(
      this.client,
      new GetObjectCommand({ Bucket: this.bucket, Key: key, ResponseContentDisposition: `attachment; filename*=UTF-8''${encodeURIComponent(fileName)}` }),
      { expiresIn: ttlSec },
    );
  }
  async head(key: string) {
    try {
      const r = await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      return { size: r.ContentLength ?? 0, contentType: r.ContentType };
    } catch {
      return null;
    }
  }
  async readHead(key: string, bytes: number) {
    const r = await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: key, Range: `bytes=0-${bytes - 1}` }));
    return Buffer.from(await r.Body!.transformToByteArray());
  }
  async delete(key: string) {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }
}

@Global()
@Module({
  providers: [
    {
      provide: Storage,
      useFactory: () => {
        const cfg = loadConfig();
        return cfg.storage.driver === 's3' ? new S3Storage() : new LocalStorage(resolve(cfg.storage.localDir), cfg.publicBaseUrl, cfg.jwtSecret + ':storage');
      },
    },
  ],
  exports: [Storage],
})
export class StorageModule {}
