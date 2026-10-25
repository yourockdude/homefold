import { Injectable, Logger, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import { HttpAdapterHost } from '@nestjs/core';
import { WebSocket, WebSocketServer } from 'ws';
import type { IncomingMessage } from 'node:http';
import type { Duplex } from 'node:stream';
import { PrismaService } from '../prisma/prisma.service';
import { ChangesService } from '../changes/changes.service';
import { authenticate } from '../common/auth.guard';

interface Client {
  ws: WebSocket;
  userId: string;
  familyId: string;
  alive: boolean;
}

/**
 * WebSocket /ws?token=<access JWT>. Шлёт только сигнал {type:"changed", cursor}.
 * Данные клиент забирает через GET /sync/pull — WebSocket не единственный канал синхронизации.
 */
@Injectable()
export class RealtimeService implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly logger = new Logger(RealtimeService.name);
  private readonly wss = new WebSocketServer({ noServer: true });
  private readonly clients = new Set<Client>();
  private heartbeat?: NodeJS.Timeout;

  constructor(private readonly adapterHost: HttpAdapterHost, private readonly prisma: PrismaService, private readonly changes: ChangesService) {}

  onApplicationBootstrap() {
    const server = this.adapterHost.httpAdapter?.getHttpServer();
    if (!server) return;
    server.on('upgrade', (req: IncomingMessage, socket: Duplex, head: Buffer) => {
      const url = new URL(req.url ?? '/', 'http://localhost');
      if (url.pathname !== '/ws') return; // чужие upgrade не трогаем
      void this.handleUpgrade(req, socket, head, url.searchParams.get('token') ?? '');
    });
    this.changes.events.on('changed', ({ familyId, cursor }: { familyId: string; cursor: string }) => this.broadcast(familyId, cursor));
    this.heartbeat = setInterval(() => {
      for (const c of this.clients) {
        if (!c.alive) {
          c.ws.terminate();
          continue;
        }
        c.alive = false;
        c.ws.ping();
      }
    }, 30_000);
    this.heartbeat.unref();
  }

  private async handleUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer, token: string) {
    try {
      const ctx = await authenticate(this.prisma, token);
      if (!ctx.familyId) throw new Error('no family');
      this.wss.handleUpgrade(req, socket, head, (ws) => {
        const client: Client = { ws, userId: ctx.userId, familyId: ctx.familyId!, alive: true };
        this.clients.add(client);
        ws.on('pong', () => (client.alive = true));
        ws.on('close', () => this.clients.delete(client));
        ws.on('error', () => this.clients.delete(client));
        ws.send(JSON.stringify({ type: 'ready' }));
      });
    } catch {
      socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      socket.destroy();
    }
  }

  private broadcast(familyId: string, cursor: string) {
    const msg = JSON.stringify({ type: 'changed', cursor });
    for (const c of this.clients) if (c.familyId === familyId && c.ws.readyState === WebSocket.OPEN) c.ws.send(msg);
  }

  disconnectUser(userId: string) {
    for (const c of this.clients) if (c.userId === userId) c.ws.close(4001, 'access revoked');
  }

  onApplicationShutdown() {
    if (this.heartbeat) clearInterval(this.heartbeat);
    for (const c of this.clients) c.ws.terminate();
    this.wss.close();
  }
}
