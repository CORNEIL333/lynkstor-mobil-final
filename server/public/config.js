/**
 * Console d'administration Lynkstor — backend Neon Functions.
 * La passerelle `lynkstor-api` tourne sur Neon (compute endpoint) ; le schéma
 * applicatif est dans le schema `lynkstor`. CORS_ALLOWED_ORIGIN=* sur la
 * gateway, donc cette page peut etre servie de n'importe quelle origine
 * (Cloudflare Pages, ou un serveur statique local pour la recette).
 */
window.LYNKSTOR_CONFIG = {
  mode: "neon",
  // Endpoint public de la Neon Function (sans trailing slash).
  apiBase: "https://br-curly-mud-b11jrchz-api.compute.c-5.eu-central-1.aws.neon.tech",
};

window.LYNKSTOR_API_BASE = window.LYNKSTOR_CONFIG.apiBase;
