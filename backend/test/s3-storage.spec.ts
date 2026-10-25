import { createServer, Server } from 'node:http';
import { AddressInfo } from 'node:net';
import { S3Storage } from '../src/storage/storage.service';

/** Фейковый S3 (path-style): проверяем, что S3Storage корректно строит подписанные ссылки и ходит за HEAD/GET/DELETE. */
describe('S3Storage (против фейкового S3)', () => {
  let server: Server;
  const objects = new Map<string, Buffer>();
  const log: string[] = [];
  let storage: S3Storage;

  beforeAll(async () => {
    server = createServer((req, res) => {
      const key = decodeURIComponent((req.url ?? '').split('?')[0]);
      log.push(`${req.method} ${key}`);
      const chunks: Buffer[] = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        if (req.method === 'PUT') objects.set(key, Buffer.concat(chunks)), res.writeHead(200).end();
        else if (req.method === 'HEAD') {
          const o = objects.get(key);
          o ? res.writeHead(200, { 'content-length': o.length, 'content-type': 'application/pdf' }).end() : res.writeHead(404).end();
        } else if (req.method === 'GET') {
          const o = objects.get(key);
          if (!o) return void res.writeHead(404).end();
          const m = /bytes=(\d+)-(\d+)/.exec(String(req.headers.range ?? ''));
          const body = m ? o.subarray(Number(m[1]), Number(m[2]) + 1) : o;
          res.writeHead(m ? 206 : 200).end(body);
        } else if (req.method === 'DELETE') objects.delete(key), res.writeHead(204).end();
      });
    });
    await new Promise<void>((r) => server.listen(0, r));
    const port = (server.address() as AddressInfo).port;
    Object.assign(process.env, { S3_ENDPOINT: `http://localhost:${port}`, S3_FORCE_PATH_STYLE: 'true', S3_ACCESS_KEY_ID: 'test', S3_SECRET_ACCESS_KEY: 'testtest', S3_BUCKET: 'bkt', S3_REGION: 'us-east-1' });
    storage = new S3Storage();
  });
  afterAll(() => new Promise((r) => server.close(r)));

  it('presigned PUT: короткий TTL, подпись в query, загрузка проходит, head видит размер и тип', async () => {
    const put = await storage.presignPut('families/f/documents/d', 'application/pdf', 900);
    const url = new URL(put.url);
    expect(url.searchParams.get('X-Amz-Expires')).toBe('900');
    expect(url.searchParams.get('X-Amz-Signature')).toBeTruthy();
    expect(put.headers['Content-Type']).toBe('application/pdf');
    const res = await fetch(put.url, { method: 'PUT', headers: put.headers, body: Buffer.from('%PDF-1.4 hello') });
    expect(res.status).toBe(200);
    expect(await storage.head('families/f/documents/d')).toMatchObject({ size: 14, contentType: 'application/pdf' });
    expect((await storage.readHead('families/f/documents/d', 4)).toString()).toBe('%PDF');
  });

  it('presigned GET: TTL и имя файла в Content-Disposition; несуществующий объект → head null; delete', async () => {
    const url = new URL(await storage.presignGet('families/f/documents/d', 'Полис ДМС.pdf', 120));
    expect(url.searchParams.get('X-Amz-Expires')).toBe('120');
    expect(decodeURIComponent(url.searchParams.get('response-content-disposition')!)).toContain('Полис ДМС.pdf');
    expect(await storage.head('nope')).toBeNull();
    await storage.delete('families/f/documents/d');
    expect(await storage.head('families/f/documents/d')).toBeNull();
  });
});
