/**
 * Origine autorisée pour le CORS (durcissement S4).
 * - En production, définir CORS_ALLOWED_ORIGIN sur l'URL exacte du dashboard
 *   admin (ex. https://lynkstor-admin.pages.dev). Une seule origine suffit.
 * - Si la variable est absente (dev / parc mobile), on retombe sur "*" :
 *   le mobile ignore le CORS, et les routes admin exigent un jeton de session
 *   signé que seule l'app admin légitime détient.
 * NB: on n'active PAS Access-Control-Allow-Credentials — l'auth passe par un
 * en-tête Authorization posé par le JS, jamais par cookie.
 */
function allowedOrigin(): string {
  const raw = (Deno.env.get("CORS_ALLOWED_ORIGIN") || "").trim();
  return raw.length > 0 ? raw.replace(/\/+$/, "") : "*";
}

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": allowedOrigin(),
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-api-key, x-idempotency-key, x-webhook-signature, x-signature",
  "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function handleOptions(): Response {
  return new Response("ok", { headers: corsHeaders });
}
