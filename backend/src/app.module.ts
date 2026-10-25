import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AuthGuard } from './common/auth.guard';
import { loadConfig } from './common/config';
import { PrismaModule } from './prisma/prisma.service';
import { ChangesModule } from './changes/changes.service';
import { PlanModule } from './plan/plan.service';
import { StorageModule } from './storage/storage.service';
import { StorageController } from './storage/storage.controller';
import { NotificationsModule } from './notifications/notifications.module';
import { AuthModule } from './auth/auth.module';
import { FamiliesModule } from './families/families.module';
import { InvitationsModule } from './invitations/invitations.module';
import { ShoppingModule } from './shopping/shopping.module';
import { TasksModule } from './tasks/tasks.module';
import { DocumentsModule } from './documents/documents.module';
import { SyncModule } from './sync/sync.module';
import { BillingModule } from './billing/billing.module';
import { HealthModule } from './health/health.module';

@Module({
  imports: [
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: loadConfig().throttleLimit }]),
    ScheduleModule.forRoot(),
    PrismaModule,
    ChangesModule,
    PlanModule,
    StorageModule,
    NotificationsModule,
    AuthModule,
    FamiliesModule,
    InvitationsModule,
    ShoppingModule,
    TasksModule,
    DocumentsModule,
    SyncModule,
    BillingModule,
    HealthModule,
  ],
  controllers: [StorageController],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
  ],
})
export class AppModule {}
