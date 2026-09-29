import { defineConfig } from "@neon/config/v1";

export default defineConfig({
  auth: true,
  functions: {
    api: {
      name: "lynkstor-api",
      source: "./functions/api/index.ts",
      env: {
        LICENSE_KEY_ID: process.env.LICENSE_KEY_ID!,
        LICENSE_PRIVATE_KEY_B64: process.env.LICENSE_PRIVATE_KEY_B64!,
        ADMIN_SESSION_SECRET: process.env.ADMIN_SESSION_SECRET!,
        PAYMENT_WEBHOOK_SECRET: process.env.PAYMENT_WEBHOOK_SECRET!,
        CORS_ALLOWED_ORIGIN: process.env.CORS_ALLOWED_ORIGIN!,
        MIN_SUPPORTED_VERSION: process.env.MIN_SUPPORTED_VERSION!,
        LATEST_VERSION: process.env.LATEST_VERSION!,
        MAINTENANCE: process.env.MAINTENANCE!,
        KILL_MODULES: process.env.KILL_MODULES!,
        MAX_OFFLINE_DAYS: process.env.MAX_OFFLINE_DAYS!,
        REQUIRE_AGENT_ACTIVATION_CODE: process.env.REQUIRE_AGENT_ACTIVATION_CODE!,
        TRIAL_DAYS: process.env.TRIAL_DAYS!,
        TRIAL_PLAN_NAME: process.env.TRIAL_PLAN_NAME!,
        TRIAL_PRICE_FCFA: process.env.TRIAL_PRICE_FCFA!,
      },
    },
  },
});
