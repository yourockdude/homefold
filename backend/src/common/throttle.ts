/** Лимит запросов в минуту на IP для чувствительных эндпоинтов; в тестах снимается THROTTLE_RELAXED=true. */
export const perMinute = (n: number) => () => (process.env.THROTTLE_RELAXED === 'true' ? 1_000_000 : n);
