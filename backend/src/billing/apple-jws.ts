import { Injectable } from '@nestjs/common';
import { X509Certificate, verify as cryptoVerify } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { AppError } from '../common/errors';
import { loadConfig } from '../common/config';

const b64u = (s: string) => Buffer.from(s, 'base64url');

/**
 * Проверка JWS от Apple (подписанные транзакции и уведомления V2):
 * ES256, цепочка x5c (leaf → intermediate → root) должна замыкаться на корневой сертификат Apple.
 * Корневые сертификаты берутся из APPLE_ROOT_CA_PATHS (Apple Root CA - G3, PEM или DER).
 */
@Injectable()
export class AppleJws {
  private roots(): X509Certificate[] {
    return loadConfig()
      .billing.rootCaPaths.filter((p) => existsSync(p))
      .map((p) => new X509Certificate(readFileSync(p)));
  }

  get configured() {
    return this.roots().length > 0;
  }

  verify<T = Record<string, any>>(jws: string): T {
    const fail = (msg: string) => new AppError(400, 'INVALID_SIGNATURE', `Подпись Apple недействительна: ${msg}`);
    const roots = this.roots();
    if (!roots.length) throw new AppError(503, 'BILLING_NOT_CONFIGURED', 'Корневой сертификат Apple не настроен на сервере');
    const parts = jws.split('.');
    if (parts.length !== 3) throw fail('формат');
    let header: any;
    try {
      header = JSON.parse(b64u(parts[0]).toString());
    } catch {
      throw fail('заголовок');
    }
    if (header.alg !== 'ES256' || !Array.isArray(header.x5c) || header.x5c.length < 2) throw fail('алгоритм или цепочка');

    let chain: X509Certificate[];
    try {
      chain = header.x5c.map((c: string) => new X509Certificate(Buffer.from(c, 'base64')));
    } catch {
      throw fail('сертификат');
    }
    const now = Date.now();
    for (const c of chain) if (new Date(c.validFrom).getTime() > now || new Date(c.validTo).getTime() < now) throw fail('срок сертификата');
    for (let i = 0; i < chain.length - 1; i++) {
      if (!chain[i].checkIssued(chain[i + 1]) || !chain[i].verify(chain[i + 1].publicKey)) throw fail('цепочка');
    }
    const top = chain[chain.length - 1];
    const anchored = roots.some((r) => top.fingerprint256 === r.fingerprint256 || (top.checkIssued(r) && top.verify(r.publicKey)));
    if (!anchored) throw fail('корень не доверенный');

    const ok = cryptoVerify('sha256', Buffer.from(`${parts[0]}.${parts[1]}`), { key: chain[0].publicKey, dsaEncoding: 'ieee-p1363' }, b64u(parts[2]));
    if (!ok) throw fail('подпись');
    return JSON.parse(b64u(parts[1]).toString());
  }
}

