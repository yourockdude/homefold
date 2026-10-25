import { Module } from '@nestjs/common';
import { TasksModule } from '../tasks/tasks.module';
import { AppleJws } from './apple-jws';
import { AppStoreApi } from './app-store-api';
import { BillingController } from './billing.controller';
import { BillingService } from './billing.service';

@Module({ imports: [TasksModule], controllers: [BillingController], providers: [BillingService, AppleJws, AppStoreApi] })
export class BillingModule {}
