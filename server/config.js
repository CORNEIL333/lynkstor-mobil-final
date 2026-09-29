/**
 * Configuration centralisée (variables d'environnement).
 * En production : définir toutes les clés secrètes — ne jamais committer .env
 */
require('dotenv').config();

function requiredInProduction(name, fallback) {
  const value = process.env[name] || fallback;
  if (process.env.NODE_ENV === 'production' && !process.env[name]) {
    console.error(`❌ FATAL: ${name} doit être défini en production.`);
    process.exit(1);
  }
  return value;
}

const config = {
  port: parseInt(process.env.PORT || '3001', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  isProduction: process.env.NODE_ENV === 'production',

  /** Clé Bearer pour le dashboard admin et routes /api/v1/admin/* */
  adminApiKey: requiredInProduction(
    'ADMIN_API_KEY',
    'dev-admin-key-change-me'
  ),

  /** Clé Bearer pour sync mobile (si vide → même clé que admin) */
  syncApiKey: process.env.SYNC_API_KEY || null,

  /** Secret HMAC pour les webhooks de paiement (header X-Webhook-Signature) */
  webhookSecret: requiredInProduction(
    'WEBHOOK_SECRET',
    'dev-webhook-secret-change-me'
  ),

  /** Login dashboard (optionnel) — échange user/pass contre le token admin */
  adminUser: process.env.ADMIN_USER || 'admin',
  adminPassword: requiredInProduction(
    'ADMIN_PASSWORD',
    'admin-dev-change-me'
  ),

  /** CORS : origines autorisées (séparées par des virgules). * = dev only */
  corsOrigin: process.env.CORS_ORIGIN || (process.env.NODE_ENV === 'production' ? '' : '*'),

  /** Désactive la vérif webhook uniquement en dev si explicitement demandé */
  skipWebhookVerify: process.env.SKIP_WEBHOOK_VERIFY === 'true',
};

if (!config.isProduction) {
  console.warn('⚠️  Mode développement — utilisez un fichier .env avec des secrets forts avant la prod.');
}

module.exports = config;
