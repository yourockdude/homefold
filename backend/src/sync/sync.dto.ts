import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsIn, IsInt, IsObject, IsOptional, IsUUID, Min, ValidateNested } from 'class-validator';
import { Matches } from 'class-validator';

export const SYNC_ENTITIES = ['shoppingList', 'shoppingItem', 'taskSeries', 'taskOccurrence', 'checklistItem', 'document'] as const;
export type SyncEntity = (typeof SYNC_ENTITIES)[number];

export class OperationDto {
  @ApiProperty({ description: 'Клиентский UUID операции — ключ идемпотентности' }) @IsUUID() opId: string;
  @ApiProperty({ enum: SYNC_ENTITIES }) @IsIn(SYNC_ENTITIES as unknown as string[]) entity: SyncEntity;
  @ApiProperty() @IsUUID() entityId: string;
  @ApiProperty({ enum: ['upsert', 'delete'] }) @IsIn(['upsert', 'delete']) type: 'upsert' | 'delete';
  @ApiPropertyOptional({ description: 'Версия записи, на которой основана правка' }) @IsOptional() @IsInt() @Min(0) baseVersion?: number;
  @ApiPropertyOptional({ description: 'Поля сущности (те же, что в REST PUT)' }) @IsOptional() @IsObject() payload?: Record<string, unknown>;
}

export class PushDto {
  @ApiProperty({ type: [OperationDto] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(100) @ValidateNested({ each: true }) @Type(() => OperationDto)
  operations: OperationDto[];
}

export class PullQuery {
  @ApiPropertyOptional({ default: '0' }) @IsOptional() @Matches(/^\d+$/, { message: 'Курсор — число' }) cursor?: string;
  @ApiPropertyOptional({ default: 200 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) limit?: number;
}
