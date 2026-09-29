/**
 * Copier vers config.js — ne pas committer de service_role.
 */
window.LYNKSTOR_CONFIG = {
  mode: "supabase",
  supabaseUrl: "https://YOUR_PROJECT_REF.supabase.co",
  apiBase: "https://YOUR_PROJECT_REF.supabase.co/functions/v1/lynkstor-api",
  // Settings → API → publishable / anon key
  supabaseAnonKey: "sb_publishable_… ou eyJ…",
};

window.LYNKSTOR_API_BASE = window.LYNKSTOR_CONFIG.apiBase;
