import { Global, Module } from '@nestjs/common';
import { NotificationsController } from './notifications.controller';
import { PushService } from './push.service';
import { RealtimeService } from './realtime.service';

@Global()
@Module({ controllers: [NotificationsController], providers: [PushService, RealtimeService], exports: [PushService, RealtimeService] })
export class NotificationsModule {}
