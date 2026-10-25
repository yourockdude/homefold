import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min, MinLength } from 'class-validator';
import { Transform } from 'class-transformer';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class CreateFamilyDto {
  @ApiProperty({ example: 'Смирновы' }) @Transform(trim) @IsString() @MinLength(1, { message: 'Введите название семьи' }) @MaxLength(60)
  name: string;
  @ApiProperty({ example: 'Анна' }) @Transform(trim) @IsString() @MinLength(1, { message: 'Введите ваше имя' }) @MaxLength(40)
  displayName: string;
}

export class UpdateFamilyDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(1) @MaxLength(60)
  name: string;
}

export class UpdateMemberDto {
  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MinLength(1) @MaxLength(40)
  displayName?: string;
  @ApiPropertyOptional({ enum: ['admin', 'member'] }) @IsOptional() @IsIn(['admin', 'member'])
  role?: 'admin' | 'member';
  @ApiPropertyOptional({ description: 'Индекс пастельного цвета аватара 0…7' }) @IsOptional() @IsInt() @Min(0) @Max(7)
  color?: number;
}
