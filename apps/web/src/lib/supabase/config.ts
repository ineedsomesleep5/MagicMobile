export interface SupabasePublicConfig {
  url: string;
  publishableKey: string;
}

export const getSupabasePublicConfig = (): SupabasePublicConfig | null => {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const publishableKey = (
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
    ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  )?.trim();
  if (!url || !publishableKey) return null;
  return { url, publishableKey };
};

export const requireSupabasePublicConfig = (): SupabasePublicConfig => {
  const config = getSupabasePublicConfig();
  if (!config) {
    throw new Error("Cloud decks are not configured. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY.");
  }
  return config;
};
