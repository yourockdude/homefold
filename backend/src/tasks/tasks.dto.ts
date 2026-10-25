import { ApiPropertyOptional } from '@nestjs/swagger';
import { ArrayMaxSize, IsArray, IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min } from 'class-validator';
import { Transform } from 'class-transformer';
import { PageQuery } from '../common/pagination';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;

export class OccurrenceDto {
  @ApiPropertyOptional({ description: 'Обязательно при создании' }) @IsOptional() @Transform(trim) @IsString() @MaxLength(120) title?: string;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsUUID() assigneeId?: string | null;
  @ApiPropertyOptional({ example: '2026-10-22', description: 'Обязательно при создании' }) @IsOptional() @Matches(DATE, { message: 'Дата в формате YYYY-MM-DD' }) date?: string;
  @ApiPropertyOptional({ nullable: true, example: '18:30' }) @IsOptional() @Matches(TIME, { message: 'Время в формате HH:mm' }) time?: string | null;
  @ApiPropertyOptional({ example: 'Europe/Moscow' }) @IsOptional() @IsString() @MaxLength(64) timezone?: string;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsString() @MaxLength(120) place?: string | null;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsString() @MaxLength(1000) note?: string | null;
  @ApiPropertyOptional({ nullable: true, description: 'За сколько минут напомнить; по умолчанию 30; null — без напоминания' }) @IsOptional() @IsInt() @Min(0) @Max(10080) reminderMinutes?: number | null;
  @ApiPropertyOptional({ enum: ['open', 'done'] }) @IsOptional() @IsIn(['open', 'done']) status?: 'open' | 'done';
}

export class PostponeDto {
  @ApiPropertyOptional() @Matches(DATE, { message: 'Дата в формате YYYY-MM-DD' }) date: string;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @Matches(TIME, { message: 'Время в формате HH:mm' }) time?: string | null;
}

export class ChecklistDto {
  @ApiPropertyOptional() @IsOptional() @IsUUID() occurrenceId?: string;
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(200) title?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() done?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) @Max(1000) position?: number;
}

export class SeriesDto {
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(120) title?: string;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsUUID() assigneeId?: string | null;
  @ApiPropertyOptional({ example: '2026-10-22' }) @IsOptional() @Matches(DATE, { message: 'Дата в формате YYYY-MM-DD' }) startDate?: string;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @Matches(TIME, { message: 'Время в формате HH:mm' }) time?: string | null;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(64) timezone?: string;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsString() @MaxLength(120) place?: string | null;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsString() @MaxLength(1000) note?: string | null;
  @ApiPropertyOptional({ enum: ['daily', 'weekly', 'monthly'] }) @IsOptional() @IsIn(['daily', 'weekly', 'monthly']) repeat?: 'daily' | 'weekly' | 'monthly';
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsInt() @Min(0) @Max(10080) reminderMinutes?: number | null;
  @ApiPropertyOptional({ type: [String], description: 'Шаблон чек-листа для новых выполнений' }) @IsOptional() @IsArray() @ArrayMaxSize(50) @IsString({ each: true }) @MaxLength(200, { each: true }) checklist?: string[];
}

export class TasksQuery extends PageQuery {
  @ApiPropertyOptional({ example: '2026-10-19' }) @IsOptional() @Matches(DATE) from?: string;
  @ApiPropertyOptional({ example: '2026-10-25' }) @IsOptional() @Matches(DATE) to?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() assigneeId?: string;
  @ApiPropertyOptional({ enum: ['open', 'done'] }) @IsOptional() @IsIn(['open', 'done']) status?: 'open' | 'done';
  @ApiPropertyOptional({ example: '2026-10-22', description: 'Сегодняшняя дата клиента — по ней считается overdue' }) @IsOptional() @Matches(DATE) today?: string;
}
