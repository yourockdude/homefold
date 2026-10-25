import { Module } from '@nestjs/common';
import { ShoppingModule } from '../shopping/shopping.module';
import { TasksModule } from '../tasks/tasks.module';
import { DocumentsModule } from '../documents/documents.module';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';

@Module({ imports: [ShoppingModule, TasksModule, DocumentsModule], controllers: [SyncController], providers: [SyncService] })
export class SyncModule {}
