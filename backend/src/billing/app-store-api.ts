import { Injectable } from '@nestjs/common';
import { importPKCS8, SignJWT } from 'jose';
import { AppError } from '../common/errors';
import { loadConfig } from '../common/config';
import { AppleJws } from './apple-jws';

/** Клиент App Store Server API: авторитетные данные о транзакции по её id. Нужны APPLE_IAP_* из App Store Connect. */
@Injectable()
export class AppStoreApi {
  constructor(private readonly jws: AppleJws) {}

  get configured() {
    const b = loadConfig().billing;
    return !!(b.iapKeyId && b.iapIssuerId && b.iapKey);
  }

  async getTransaction(transactionId: string, environment: string): Promise<Record<string, any>> {
    const b = loadConfig().billing;
    const key = await importPKCS8(b.iapKey!.replace(/\\n/g, '\n'), 'ES256');
    const token = await new SignJWT({ bid: b.bundleId })
      .setProtectedHeader({ alg: 'ES256', kid: b.iapKeyId!, typ: 'JWT' })
      .setIssuer(b.iapIssuerId!)
      .setAudience('appstoreconnect-v1')
      .setIssuedAt()
      .setExpirationTime('10m')
      .sign(key);
    const base = environment === 'Sandbox' ? 'https://api.storekit-sandbox.itunes.apple.com' : 'https://api.storekit.itunes.apple.com';
    const res = await fetch(`${base}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`, { headers: { Authorization: `Bearer ${token}` } });
    if (res.status === 404) throw new AppError(404, 'TRANSACTION_NOT_FOUND', 'Покупка не найдена в App Store');
    if (!res.ok) throw new AppError(502, 'APPSTORE_UNAVAILABLE', 'App Store сейчас недоступен. Попробуйте позже');
    const body = (await res.json()) as { signedTransactionInfo: string };
    return this.jws.verify(body.signedTransactionInfo);
  }
}
