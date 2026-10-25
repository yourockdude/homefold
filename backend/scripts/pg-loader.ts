// embedded-postgres — ESM-only пакет, а проект собирается в CommonJS: грузим через настоящий dynamic import.
// eslint-disable-next-line @typescript-eslint/no-implied-eval
const dynamicImport = new Function('s', 'return import(s)') as (s: string) => Promise<any>;

export async function createEmbeddedPostgres(options: Record<string, unknown>): Promise<any> {
  const mod = await dynamicImport('embedded-postgres');
  const Ctor = mod.default;
  return new Ctor({ user: 'ryadom', password: 'ryadom', onLog: () => undefined, onError: () => undefined, ...options });
}
