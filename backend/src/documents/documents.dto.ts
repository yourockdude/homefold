import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ArrayMaxSize, IsArray, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min } from 'class-validator';
import { Transform } from 'class-transformer';
import { PageQuery } from '../common/pagination';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);
export const ALLOWED_MIME = ['application/pdf', 'image/jpeg', 'image/png'] as const;
const CATEGORIES = ['personal', 'health', 'home', 'travel'];
const ACCESS = ['author_only', 'selected', 'family'];

export class UpdateDocumentDto {
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(120) title?: string;
  @ApiPropertyOptional({ enum: CATEGORIES }) @IsOptional() @IsIn(CATEGORIES) category?: 'personal' | 'health' | 'home' | 'travel';
  @ApiPropertyOptional({ nullable: true, description: 'Чей это документ (участник). Не то же самое, что доступ.' }) @IsOptional() @IsUUID() ownerId?: string | null;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsString() @MaxLength(60) number?: string | null;
  @ApiPropertyOptional({ nullable: true, example: '2027-08-31' }) @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/, { message: 'Дата в формате YYYY-MM-DD' }) expiresAt?: string | null;
  @ApiPropertyOptional({ enum: ACCESS }) @IsOptional() @IsIn(ACCESS) access?: 'author_only' | 'selected' | 'family';
  @ApiPropertyOptional({ type: [String], description: 'Для access=selected' }) @IsOptional() @IsArray() @ArrayMaxSize(20) @IsUUID('all', { each: true }) selectedUserIds?: string[];
}

export class CreateDocumentDto extends UpdateDocumentDto {
  @ApiProperty({ description: 'Клиентский UUID' }) @IsUUID() id: string;
  @ApiProperty() @IsString() @MaxLength(200) fileName: string;
  @ApiProperty({ enum: ALLOWED_MIME }) @IsIn(ALLOWED_MIME as unknown as string[], { message: 'Поддерживаются PDF, JPEG и PNG' }) mimeType: (typeof ALLOWED_MIME)[number];
  @ApiProperty({ description: 'Размер файла в байтах, до 25 МБ' }) @IsInt() @Min(1) @Max(25 * 1024 * 1024, { message: 'Файл больше 25 МБ' }) sizeBytes: number;
}

export class DocumentsQuery extends PageQuery {
  @ApiPropertyOptional({ enum: CATEGORIES }) @IsOptional() @IsIn(CATEGORIES) category?: string;
  @ApiPropertyOptional({ description: 'Поиск по названию, номеру и имени файла' }) @IsOptional() @IsString() @MaxLength(100) q?: string;
}
