import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsIn, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { Transform } from 'class-transformer';
import { PageQuery } from '../common/pagination';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class ListDto {
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(80) name?: string;
  @ApiPropertyOptional({ enum: ['active', 'archived'] }) @IsOptional() @IsIn(['active', 'archived']) status?: 'active' | 'archived';
}

export class ItemDto {
  @ApiPropertyOptional() @IsOptional() @IsUUID() listId?: string;
  @ApiPropertyOptional({ description: 'Обязательно при создании' }) @IsOptional() @Transform(trim) @IsString() @MaxLength(120) name?: string;
  @ApiPropertyOptional({ description: 'Положительное число' }) @IsOptional() @IsNumber({}, { message: 'Количество — число' }) @Min(0.001, { message: 'Количество должно быть больше нуля' }) @Max(100000) quantity?: number;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(20) unit?: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(40) category?: string;
  @ApiPropertyOptional({ nullable: true, description: 'userId участника; null = «Любой»' }) @IsOptional() @IsUUID() assigneeId?: string | null;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsString() @MaxLength(500) note?: string | null;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() purchased?: boolean;
}

export class NewListDto {
  @ApiPropertyOptional({ description: 'Клиентский UUID нового списка (идемпотентность)' }) @IsUUID() id: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(80) name?: string;
}

export class ListsQuery extends PageQuery {
  @ApiPropertyOptional({ enum: ['active', 'archived'] }) @IsOptional() @IsIn(['active', 'archived']) status?: 'active' | 'archived';
}
