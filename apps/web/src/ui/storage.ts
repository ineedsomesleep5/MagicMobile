/** localStorage that a private window or blocked site data cannot break: reads fall back, writes are dropped. */
export const storage = {
  get: (key: string) => { try { return localStorage.getItem(key) ?? undefined; } catch { return undefined; } },
  set: (key: string, value: string) => { try { localStorage.setItem(key, value); } catch { /* private window */ } },
};
