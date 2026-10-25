import { Injectable, Logger } from '@nestjs/common';
import { connect } from 'node:http2';
import { importPKCS8, SignJWT } from 'jose';
import { PrismaService } from '../prisma/prisma.service';
import { loadConfig } from '../common/config';

export type PushKind = 'task' | 'shopping';

/** APNs по HTTP/2 с токеном-ключом (.p8). Без настроек APNS_* — тихий no-op. */
@Injectable()
export class PushService {
  private readonly logger = new Logger(PushService.name);
  private jwt?: { token: string; at: number };

  constructor(private readonly prisma: PrismaService) {}

  get configured() {
    const a = loadConfig().apns;
    return !!(a.keyId && a.teamId && a.key && a.topic);
  }

  private async authToken() {
    if (this.jwt && Date.now() - this.jwt.at < 40 * 60_000) return this.jwt.token;
    const a = loadConfig().apns;
    const key = await importPKCS8(a.key!.replace(/\\n/g, '\n'), 'ES256');
    const token = await new SignJWT({}).setProtectedHeader({ alg: 'ES256', kid: a.keyId! }).setIssuer(a.teamId!).setIssuedAt().sign(key);
    this.jwt = { token, at: Date.now() };
    return token;
  }

  private inQuietHours(s: { quietHoursEnabled: boolean; quietStart: string; quietEnd: string; timezone: string }) {
    if (!s.quietHoursEnabled) return false;
    let now: string;
    try {
      now = new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: s.timezone }).format(new Date());
    } catch {
      return false;
    }
    return s.quietStart <= s.quietEnd ? now >= s.quietStart && now < s.quietEnd : now >= s.quietStart || now < s.quietEnd;
  }

  /** Push о назначении. Содержимое документов в push не попадает (метода для них нет). */
  async notify(userId: string, kind: PushKind, title: string, body: string, entityId: string) {
    if (!this.configured) return;
    try {
      const settings = await this.prisma.notificationSettings.findUnique({ where: { userId } });
      if (settings) {
        if (kind === 'task' && !settings.taskReminders) return;
        if (kind === 'shopping' && !settings.shoppingPush) return;
        if (this.inQuietHours(settings)) return;
      }
      const devices = await this.prisma.deviceToken.findMany({ where: { userId } });
      for (const d of devices) await this.sendOne(d.token, d.environment, { aps: { alert: { title, body }, sound: 'default' }, kind, entityId });
    } catch (e) {
      this.logger.warn(`Push не отправлен: ${(e as Error).message}`);
    }
  }

  private async sendOne(token: string, environment: string, payload: object) {
    const host = environment === 'sandbox' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
    const jwt = await this.authToken();
    const status = await new Promise<number>((resolve, reject) => {
      const client = connect(host);
      client.on('error', reject);
      const req = client.request({
        ':method': 'POST',
        ':path': `/3/device/${token}`,
        authorization: `bearer ${jwt}`,
        'apns-topic': loadConfig().apns.topic!,
        'apns-push-type': 'alert',
      });
      let code = 0;
      req.on('response', (h) => (code = Number(h[':status'])));
      req.on('end', () => {
        client.close();
        resolve(code);
      });
      req.on('error', reject);
      req.end(JSON.stringify(payload));
    });
    if (status === 410 || status === 400) await this.prisma.deviceToken.deleteMany({ where: { token } });
  }
}
