import { Injectable } from '@nestjs/common';
import * as nodemailer from 'nodemailer';
import { loadConfig } from '../common/config';

export abstract class Mailer {
  abstract sendLoginCode(email: string, code: string): Promise<void>;
}

@Injectable()
export class SmtpMailer extends Mailer {
  private readonly transport = (() => {
    const { mail } = loadConfig();
    return nodemailer.createTransport({ host: mail.host, port: mail.port, secure: mail.secure, auth: mail.user ? { user: mail.user, pass: mail.pass } : undefined });
  })();

  async sendLoginCode(email: string, code: string) {
    await this.transport.sendMail({
      from: loadConfig().mail.from,
      to: email,
      subject: `Код для входа в «рядом»: ${code}`,
      text: `Ваш код для входа в «рядом»: ${code}\n\nКод действует 10 минут. Если вы не запрашивали вход, просто проигнорируйте это письмо.`,
    });
  }
}

/** Только для тестов (MAIL_TRANSPORT=memory): письма складываются в память. */
@Injectable()
export class MemoryMailer extends Mailer {
  readonly codes = new Map<string, string>();
  async sendLoginCode(email: string, code: string) {
    this.codes.set(email, code);
  }
}
