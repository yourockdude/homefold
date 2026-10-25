import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsOptional, IsString, Length, MaxLength } from 'class-validator';
import { Transform } from 'class-transformer';

const normalizeEmail = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim().toLowerCase() : value);

export class RequestCodeDto {
  @ApiProperty({ example: 'anna@example.com' })
  @Transform(normalizeEmail) @IsEmail({}, { message: 'Введите корректный email' }) @MaxLength(254)
  email: string;
}

export class VerifyCodeDto {
  @ApiProperty() @Transform(normalizeEmail) @IsEmail({}, { message: 'Введите корректный email' })
  email: string;
  @ApiProperty({ example: '123456' }) @IsString() @Length(6, 6, { message: 'Код состоит из 6 цифр' })
  code: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80)
  deviceName?: string;
}

export class RefreshDto {
  @ApiProperty() @IsString() @MaxLength(200)
  refreshToken: string;
}
