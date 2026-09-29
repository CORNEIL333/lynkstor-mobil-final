/**
 * Gateway API Lynkstor — remplace Express pour Supabase + Cloudflare.
 * Chemins alignés sur le serveur Node :
 *   POST /api/v1/auth/login
 *   GET|POST|PUT /api/v1/admin/*
 *   POST /api/v1/sync/push
 *   GET  /api/v1/sync/pull
 *   POST /api/v1/payments/webhook
 *   GET  /health
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders, handleOptions, jsonResponse } from "../_shared/cors.ts";
import {
  type AdminSession,
  createAdminSessionToken,
  extractBearer,
  generateActivationCode,
  generateSyncToken,
  getAdminSession,
  getSecrets,
  hashPassword,
  hashToken,
  isAdminToken,
  isSyncToken,
  safeEqual,
  verifyPassword,
} from "../_shared/auth.ts";

function sb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

/** Extrait le chemin logique après le nom de la function. */
function routePath(req: Request): string {
  const url = new URL(req.url);
  let path = url.pathname;
  // /functions/v1/lynkstor-api/...  ou /lynkstor-api/...
  const markers = ["/lynkstor-api", "/functions/v1/lynkstor-api"];
  for (const m of markers) {
    const i = path.indexOf(m);
    if (i >= 0) {
      path = path.slice(i + m.length) || "/";
      break;
    }
  }
  if (!path.startsWith("/")) path = `/${path}`;
  // normaliser double slash
  path = path.replace(/\/+/g, "/");
  return path === "" ? "/" : path;
}

async function sha256Hex(secret: string, body: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(body));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function digestHex(body: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(body),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();

  try {
    const path = routePath(req);
    const method = req.method.toUpperCase();

    // ——— Health (public) ———
    if (method === "GET" && (path === "/health" || path === "/")) {
      return jsonResponse({
        status: "ok",
        service: "Lynkstor Supabase API Gateway",
        version: "1.0.0",
        timestamp: new Date().toISOString(),
        auth: "required",
      });
    }

    // ——— Config runtime (public) — S8 : mise à jour obligatoire + kill switch —
    if (
      method === "GET" &&
      (path === "/v1/config" || path === "/api/v1/config")
    ) {
      const env = (k: string, d = "") => (Deno.env.get(k) || "").trim() || d;
      return jsonResponse({
        status: "success",
        data: {
          minSupportedVersion: env("MIN_SUPPORTED_VERSION", "1.0.0"),
          latestVersion: env("LATEST_VERSION", "1.2.0"),
          updateMessage: env("UPDATE_MESSAGE"),
          announcement: env("ANNOUNCEMENT"),
          announcementUrl: env("ANNOUNCEMENT_URL"),
          maintenance: env("MAINTENANCE", "false") === "true",
          // Modules désactivés à distance, ex. "ai,scanner,wave".
          killModules: env("KILL_MODULES")
            .split(",")
            .map((m: string) => m.trim())
            .filter(Boolean),
          maxOfflineDays: parseInt(env("MAX_OFFLINE_DAYS", "7"), 10) || 7,
          requireAgentActivationCode:
            env("REQUIRE_AGENT_CODE", "false") === "true",
          serverTime: new Date().toISOString(),
        },
      });
    }

    // ——— Analytique période test (anon key, pas de PII) ———
    if (method === "POST" && path === "/api/v1/analytics/ingest") {
      return await handleAnalyticsIngest(req);
    }

    // ——— Login ———
    if (method === "POST" && path === "/api/v1/auth/login") {
      const body = await req.json().catch(() => ({})) as {
        username?: string;
        password?: string;
      };
      const { username, password } = body;
      if (!username || !password) {
        return jsonResponse({
          status: "error",
          message: "Identifiant et mot de passe requis",
        }, 400);
      }
      const s = getSecrets();
      if (
        safeEqual(username.trim(), s.adminUser) &&
        safeEqual(password.trim(), s.adminPassword) &&
        s.adminApiKey
      ) {
        return jsonResponse({
          status: "success",
          token: await createAdminSessionToken(),
          token_type: "Bearer",
          role: "super_admin",
          staff_id: "st-04",
          full_name: "Super Admin Lynkstor",
          expires_in: 8 * 60 * 60,
        });
      }

      // Vérification staff_accounts dans Supabase DB. Les filtres sont
      // séparés pour ne jamais injecter l'identifiant dans une expression
      // PostgREST `.or(...)`.
      const client = sb();
      const login = username.trim();
      const loginLower = login.toLowerCase();
      const staffColumns =
        "id, full_name, email, phone, username, password_hash, role, status";
      let { data: staff, error: staffError } = await client
        .from("staff_accounts")
        .select(staffColumns)
        .eq("username", loginLower)
        .eq("status", "active")
        .maybeSingle();

      if (!staff && !staffError) {
        const result = await client
          .from("staff_accounts")
          .select(staffColumns)
          .eq("email", loginLower)
          .eq("status", "active")
          .maybeSingle();
        staff = result.data;
        staffError = result.error;
      }
      if (!staff && !staffError) {
        const result = await client
          .from("staff_accounts")
          .select(staffColumns)
          .eq("phone", login)
          .eq("status", "active")
          .maybeSingle();
        staff = result.data;
        staffError = result.error;
      }
      if (staffError) {
        console.error("staff login lookup", staffError);
        return jsonResponse({
          status: "error",
          code: "AUTH_LOOKUP_FAILED",
          message: "Connexion temporairement indisponible",
        }, 503);
      }

      if (
        staff?.password_hash &&
        await verifyPassword(password, String(staff.password_hash))
      ) {
        if (!String(staff.password_hash).startsWith("pbkdf2-sha256$")) {
          await client.from("staff_accounts").update({
            password_hash: await hashPassword(password),
          }).eq("id", staff.id);
        }
        return jsonResponse({
          status: "success",
          token: await createAdminSessionToken(staff),
          token_type: "Bearer",
          role: staff.role || "commercial",
          staff_id: staff.id,
          full_name: staff.full_name,
          email: staff.email,
          expires_in: 12 * 60 * 60,
        });
      }

      return jsonResponse(
        {
          status: "error",
          code: "INVALID_CREDENTIALS",
          message: "Identifiants ou mot de passe incorrects",
        },
        401,
      );
    }

    // ——— Validation code agent (sans consommer) ———
    if (
      method === "POST" &&
      (path === "/api/v1/register/validate" ||
        path === "/api/v1/activation/validate")
    ) {
      return await handleValidateCode(req);
    }

    // ——— Inscription commerce (code agent obligatoire) ———
    if (method === "POST" && path === "/api/v1/register") {
      return await handleRegister(req);
    }

    // ——— Statut abonnement (app mobile, jeton appareil) ———
    if (
      method === "GET" &&
      (path === "/api/v1/subscription/status" ||
        path === "/api/v1/subscription" ||
        path === "/api/v1/license/status")
    ) {
      return await handleSubscriptionStatus(req);
    }

    // ——— Sync push ———
    if (path.startsWith("/api/v1/backups")) {
      const backupAuth = await authorizeSync(req);
      if (!backupAuth.authorized || !backupAuth.businessId) {
        return jsonResponse({
          status: "error",
          code: "UNAUTHORIZED",
          message: "Authentification appareil requise",
        }, 401);
      }
      const client = sb();
      const businessId = backupAuth.businessId;

      if (method === "POST" && path === "/api/v1/backups/upload-ticket") {
        const body = await req.json().catch(() => ({})) as Record<
          string,
          unknown
        >;
        const id = typeof body.id === "string" ? body.id.trim() : "";
        const fileName = typeof body.fileName === "string"
          ? body.fileName.replace(/[^a-zA-Z0-9._-]/g, "_")
          : "";
        const checksum = typeof body.checksum === "string"
          ? body.checksum.toLowerCase()
          : "";
        const sizeBytes = Number(body.sizeBytes);
        if (
          !id || !fileName.endsWith(".kumba") ||
          !/^[0-9a-f]{64}$/.test(checksum) ||
          !Number.isSafeInteger(sizeBytes) ||
          sizeBytes < 1 || sizeBytes > 104857600
        ) {
          return jsonResponse({
            status: "error",
            code: "INVALID_BACKUP_METADATA",
            message: "Métadonnées de sauvegarde invalides",
          }, 400);
        }
        const objectPath = `${businessId}/${id}/${fileName}`;
        const { error: recordError } = await client
          .from("cloud_backup_records")
          .insert({
            id,
            business_id: businessId,
            device_id: backupAuth.deviceId,
            object_path: objectPath,
            file_name: fileName,
            checksum,
            size_bytes: sizeBytes,
            status: "pending",
          });
        if (recordError) {
          return jsonResponse({
            status: "error",
            code: "BACKUP_RECORD_FAILED",
            message: recordError.message,
          }, recordError.code === "23505" ? 409 : 500);
        }
        const { data, error } = await client.storage
          .from("kumba-backups")
          .createSignedUploadUrl(objectPath, { upsert: false });
        if (error || !data) {
          await client.from("cloud_backup_records")
            .update({ status: "failed" }).eq("id", id);
          return jsonResponse({
            status: "error",
            code: "UPLOAD_TICKET_FAILED",
            message: error?.message || "Ticket de dépôt indisponible",
          }, 500);
        }
        return jsonResponse({
          status: "success",
          id,
          objectPath,
          signedUrl: data.signedUrl,
          token: data.token,
        }, 201);
      }

      if (method === "POST" && path === "/api/v1/backups/complete") {
        const body = await req.json().catch(() => ({})) as Record<
          string,
          unknown
        >;
        const id = typeof body.id === "string" ? body.id.trim() : "";
        const { data: record } = await client
          .from("cloud_backup_records")
          .select("id, object_path, size_bytes")
          .eq("id", id)
          .eq("business_id", businessId)
          .maybeSingle();
        if (!record) {
          return jsonResponse({
            status: "error",
            code: "BACKUP_NOT_FOUND",
            message: "Sauvegarde cloud introuvable",
          }, 404);
        }
        const separator = record.object_path.lastIndexOf("/");
        const folder = record.object_path.substring(0, separator);
        const name = record.object_path.substring(separator + 1);
        const { data: objects, error: listError } = await client.storage
          .from("kumba-backups")
          .list(folder, { search: name, limit: 10 });
        const stored = objects?.find((object) => object.name === name);
        const storedSize = Number(stored?.metadata?.size ?? -1);
        if (listError || !stored || storedSize !== Number(record.size_bytes)) {
          return jsonResponse({
            status: "error",
            code: "BACKUP_UPLOAD_INCOMPLETE",
            message: "Le fichier cloud est absent ou incomplet",
          }, 409);
        }
        await client.from("cloud_backup_records").update({
          status: "available",
          completed_at: new Date().toISOString(),
        }).eq("id", id).eq("business_id", businessId);
        return jsonResponse({ status: "success", id });
      }

      if (method === "GET" && path === "/api/v1/backups") {
        const { data, error } = await client
          .from("cloud_backup_records")
          .select(
            "id, file_name, checksum, size_bytes, status, created_at, completed_at",
          )
          .eq("business_id", businessId)
          .eq("status", "available")
          .order("created_at", { ascending: false })
          .limit(50);
        if (error) {
          return jsonResponse({
            status: "error",
            code: "BACKUP_LIST_FAILED",
            message: error.message,
          }, 500);
        }
        return jsonResponse({ status: "success", items: data ?? [] });
      }

      if (method === "POST" && path === "/api/v1/backups/download-ticket") {
        const body = await req.json().catch(() => ({})) as Record<
          string,
          unknown
        >;
        const id = typeof body.id === "string" ? body.id.trim() : "";
        const { data: record } = await client
          .from("cloud_backup_records")
          .select("id, object_path, file_name, checksum, size_bytes")
          .eq("id", id)
          .eq("business_id", businessId)
          .eq("status", "available")
          .maybeSingle();
        if (!record) {
          return jsonResponse({
            status: "error",
            code: "BACKUP_NOT_FOUND",
            message: "Sauvegarde cloud introuvable",
          }, 404);
        }
        const { data, error } = await client.storage
          .from("kumba-backups")
          .createSignedUrl(record.object_path, 600, {
            download: record.file_name,
          });
        if (error || !data) {
          return jsonResponse({
            status: "error",
            code: "DOWNLOAD_TICKET_FAILED",
            message: error?.message || "Ticket de téléchargement indisponible",
          }, 500);
        }
        return jsonResponse({
          status: "success",
          ...record,
          signedUrl: data.signedUrl,
        });
      }
    }

    if (method === "POST" && path === "/api/v1/sync/push") {
      const syncAuth = await authorizeSync(req);
      if (!syncAuth.authorized) {
        return jsonResponse({
          status: "error",
          code: "UNAUTHORIZED",
          message: "Authentification sync requise",
        }, 401);
      }
      const body = await req.json().catch(() => ({})) as Record<
        string,
        unknown
      >;
      if (Array.isArray(body.items)) {
        if (body.items.length < 1 || body.items.length > 100) {
          return jsonResponse({
            status: "error",
            code: "INVALID_BATCH_SIZE",
            message: "Un lot doit contenir entre 1 et 100 éléments",
          }, 400);
        }
        const normalizedItems: Record<string, unknown>[] = [];
        let batchBusinessId: string | null = null;
        let totalBytes = 0;
        for (const raw of body.items) {
          if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
            return jsonResponse({
              status: "error",
              code: "INVALID_BATCH_ITEM",
              message: "Chaque élément du lot doit être un objet",
            }, 400);
          }
          const item = raw as Record<string, unknown>;
          const businessId = (item.businessId || item.business_id) as
            | string
            | undefined;
          const entityType = (item.entityType || item.entity_type) as
            | string
            | undefined;
          const entityId = (item.entityId || item.entity_id) as
            | string
            | undefined;
          const operation = item.operation as string | undefined;
          const id = typeof item.id === "string" ? item.id.trim() : "";
          if (
            !id || !businessId || !entityType || !entityId || !operation ||
            !["create", "update", "delete", "upsert"].includes(operation)
          ) {
            return jsonResponse({
              status: "error",
              code: "INVALID_BATCH_ITEM",
              message:
                "id, businessId, entityType, entityId et operation valides requis",
            }, 400);
          }
          if (batchBusinessId !== null && batchBusinessId !== businessId) {
            return jsonResponse({
              status: "error",
              code: "MIXED_BUSINESS_BATCH",
              message: "Un lot ne peut concerner qu'un seul commerce",
            }, 400);
          }
          batchBusinessId = businessId;
          if (!syncAuth.privileged && syncAuth.businessId !== businessId) {
            return jsonResponse({
              status: "error",
              code: "FORBIDDEN_BUSINESS",
              message: "Ce jeton appareil n'appartient pas à ce commerce",
            }, 403);
          }
          const payload = item.payload ?? item.payload_json ?? {};
          const serialized = typeof payload === "string"
            ? payload
            : JSON.stringify(payload);
          totalBytes += serialized.length;
          if (serialized.length > 262144 || totalBytes > 1048576) {
            return jsonResponse({
              status: "error",
              code: "PAYLOAD_TOO_LARGE",
              message: "Le lot de synchronisation dépasse la taille autorisée",
            }, 413);
          }
          let parsedPayload: unknown;
          try {
            parsedPayload = typeof payload === "string"
              ? JSON.parse(payload)
              : payload;
          } catch (_) {
            return jsonResponse({
              status: "error",
              code: "INVALID_PAYLOAD_JSON",
              message: "Un payload du lot est invalide",
            }, 400);
          }
          const requestedVersion = Number(
            item.entityVersion ?? item.entity_version ??
              (typeof parsedPayload === "object" && parsedPayload !== null
                ? (parsedPayload as Record<string, unknown>).version
                : 1),
          );
          normalizedItems.push({
            id,
            businessId,
            entityType,
            entityId,
            operation,
            payload: parsedPayload,
            entityVersion: Number.isSafeInteger(requestedVersion) &&
                requestedVersion > 0
              ? requestedVersion
              : 1,
            deviceId: syncAuth.deviceId ||
              (typeof item.deviceId === "string" ? item.deviceId : null),
            localCreatedAt: typeof item.localCreatedAt === "string"
              ? item.localCreatedAt
              : null,
          });
        }
        const client = sb();
        const { data: biz } = await client
          .from("businesses")
          .select("id")
          .eq("id", batchBusinessId!)
          .maybeSingle();
        if (!biz) {
          return jsonResponse({
            status: "error",
            code: "BUSINESS_NOT_FOUND",
            message: "Commerce cloud introuvable",
          }, 404);
        }
        const { data: recorded, error } = await client.rpc(
          "record_sync_batch",
          { p_items: normalizedItems },
        );
        if (error) {
          console.error("sync batch push", error);
          return jsonResponse({
            status: "error",
            code: "SYNC_BATCH_FAILED",
            message: error.message,
          }, 500);
        }
        return jsonResponse({
          status: "success",
          count: normalizedItems.length,
          items: recorded?.items ?? [],
          timestamp: new Date().toISOString(),
        }, 201);
      }
      const businessId = (body.businessId || body.business_id) as
        | string
        | undefined;
      const entityType = (body.entityType || body.entity_type) as
        | string
        | undefined;
      const entityId = (body.entityId || body.entity_id) as string | undefined;
      const operation = body.operation as string | undefined;
      const payload = body.payload ?? body.payload_json ?? {};
      const requestedVersion = Number(
        body.entityVersion ?? body.entity_version ??
          (typeof payload === "object" && payload !== null
            ? (payload as Record<string, unknown>).version
            : 1),
      );
      const entityVersion = Number.isSafeInteger(requestedVersion) &&
          requestedVersion > 0
        ? requestedVersion
        : 1;
      const deviceId = syncAuth.deviceId ||
        (typeof body.deviceId === "string" ? body.deviceId : null) ||
        (typeof body.device_id === "string" ? body.device_id : null);
      const clientCreatedAt = (typeof body.localCreatedAt === "string"
        ? body.localCreatedAt
        : null) ||
        (typeof body.local_created_at === "string"
          ? body.local_created_at
          : null);

      if (!businessId || !entityType || !entityId || !operation) {
        return jsonResponse({
          status: "error",
          code: "VALIDATION_ERROR",
          message: "businessId, entityType, entityId, operation requis",
        }, 400);
      }
      if (!["create", "update", "delete", "upsert"].includes(operation)) {
        return jsonResponse({
          status: "error",
          message: "operation invalide",
        }, 400);
      }
      if (!syncAuth.privileged && syncAuth.businessId !== businessId) {
        return jsonResponse({
          status: "error",
          code: "FORBIDDEN_BUSINESS",
          message: "Ce jeton appareil n'appartient pas à ce commerce",
        }, 403);
      }
      const serializedPayload = typeof payload === "string"
        ? payload
        : JSON.stringify(payload);
      if (serializedPayload.length > 262144) {
        return jsonResponse({
          status: "error",
          code: "PAYLOAD_TOO_LARGE",
          message: "Le paquet de synchronisation dépasse 256 Ko",
        }, 413);
      }

      const headerKey = req.headers.get("x-idempotency-key");
      let itemId = (typeof body.id === "string" && body.id.trim()) ||
        (headerKey && headerKey.trim()) ||
        null;
      if (!itemId) {
        const raw = `${businessId}|${entityType}|${entityId}|${operation}`;
        const digest = await crypto.subtle.digest(
          "SHA-256",
          new TextEncoder().encode(raw),
        );
        itemId = Array.from(new Uint8Array(digest))
          .map((b) =>
            b.toString(16).padStart(2, "0")
          )
          .join("")
          .slice(0, 32);
      }

      const client = sb();
      // Assurer business_id (FK) — fallback soft si commerce inconnu
      const { data: biz } = await client
        .from("businesses")
        .select("id")
        .eq("id", businessId)
        .maybeSingle();
      if (!biz) {
        return jsonResponse({
          status: "error",
          code: "BUSINESS_NOT_FOUND",
          message: "Commerce cloud introuvable",
        }, 404);
      }

      let normalizedPayload: unknown;
      try {
        normalizedPayload = typeof payload === "string"
          ? JSON.parse(payload)
          : payload;
      } catch (_) {
        return jsonResponse({
          status: "error",
          code: "INVALID_PAYLOAD_JSON",
          message: "payload_json invalide",
        }, 400);
      }
      if (
        entityType === "sale" &&
        ["create", "upsert"].includes(operation) &&
        typeof normalizedPayload === "object" &&
        normalizedPayload !== null
      ) {
        const salePayload = normalizedPayload as Record<string, unknown>;
        const amount = Number(salePayload.total);
        if (!Number.isFinite(amount) || amount < 0) {
          return jsonResponse({
            status: "error",
            code: "INVALID_SALE_TOTAL",
            message: "Le total de vente synchronisé est invalide",
          }, 400);
        }
        const methods = Array.isArray(salePayload.paymentMethods)
          ? salePayload.paymentMethods.join(", ")
          : "Non précisé";
        const { error: summaryError } = await client
          .from("sales_summary")
          .upsert({
            id: entityId,
            business_id: businessId,
            amount_fcfa: amount,
            payment_method: methods,
            sold_at: salePayload.soldAt || new Date().toISOString(),
          });
        if (summaryError) {
          return jsonResponse({
            status: "error",
            code: "SALE_SUMMARY_FAILED",
            message: summaryError.message,
          }, 500);
        }
      }
      const { data: recorded, error } = await client.rpc("record_sync_event", {
        p_event_id: itemId,
        p_business_id: businessId,
        p_entity_type: entityType,
        p_entity_id: entityId,
        p_operation: operation,
        p_payload: normalizedPayload,
        p_entity_version: entityVersion,
        p_device_id: deviceId,
        p_client_created_at: clientCreatedAt,
      });
      if (error) {
        console.error("sync push", error);
        return jsonResponse({
          status: "error",
          code: "SYNC_PUSH_FAILED",
          message: error.message,
        }, 500);
      }
      return jsonResponse({
        status: "success",
        duplicate: recorded?.duplicate === true,
        id: itemId,
        serverSeq: recorded?.serverSeq,
        timestamp: recorded?.createdAt || new Date().toISOString(),
      }, recorded?.duplicate === true ? 200 : 201);
    }

    // ——— Sync pull ———
    if (method === "GET" && path === "/api/v1/sync/pull") {
      const syncAuth = await authorizeSync(req);
      if (!syncAuth.authorized) {
        return jsonResponse({
          status: "error",
          code: "UNAUTHORIZED",
          message: "Authentification sync requise",
        }, 401);
      }
      const url = new URL(req.url);
      const businessId = url.searchParams.get("businessId") ||
        url.searchParams.get("business_id");
      if (!businessId) {
        return jsonResponse({
          status: "error",
          message: "Query businessId requis",
        }, 400);
      }
      if (!syncAuth.privileged && syncAuth.businessId !== businessId) {
        return jsonResponse({
          status: "error",
          code: "FORBIDDEN_BUSINESS",
          message: "Ce jeton appareil n'appartient pas à ce commerce",
        }, 403);
      }
      const cursorRaw = url.searchParams.get("cursor") || "0";
      const cursor = Number.parseInt(cursorRaw, 10);
      if (!Number.isSafeInteger(cursor) || cursor < 0) {
        return jsonResponse({
          status: "error",
          code: "INVALID_CURSOR",
          message: "Le curseur de synchronisation est invalide",
        }, 400);
      }
      const limit = Math.min(
        parseInt(url.searchParams.get("limit") || "100", 10) || 100,
        500,
      );

      const client = sb();
      const { data, error } = await client
        .from("sync_events")
        .select(
          "id, business_id, entity_type, entity_id, operation, payload_json, created_at, server_seq, device_id, entity_version",
        )
        .eq("business_id", businessId)
        .gt("server_seq", cursor)
        .order("server_seq", { ascending: true })
        .limit(limit);
      if (error) {
        return jsonResponse({
          status: "error",
          message: error.message,
        }, 500);
      }
      const items = (data || []).map((r) => ({
        id: r.id,
        businessId: r.business_id,
        entityType: r.entity_type,
        entityId: r.entity_id,
        operation: r.operation,
        payload: r.payload_json ?? {},
        createdAt: r.created_at,
        serverSeq: r.server_seq,
        deviceId: r.device_id,
        entityVersion: r.entity_version,
      }));
      const nextCursor = items.length > 0
        ? Number(items[items.length - 1].serverSeq)
        : cursor;
      const deviceId = syncAuth.deviceId ||
        url.searchParams.get("deviceId") ||
        url.searchParams.get("device_id");
      if (deviceId && nextCursor >= cursor) {
        const { error: cursorError } = await client
          .from("device_sync_cursors")
          .upsert({
            business_id: businessId,
            device_id: deviceId,
            last_server_seq: nextCursor,
            updated_at: new Date().toISOString(),
          }, { onConflict: "business_id,device_id" });
        if (cursorError) {
          console.error("sync cursor acknowledgement", cursorError);
        }
      }
      return jsonResponse({
        status: "success",
        items,
        count: items.length,
        limit,
        cursor,
        nextCursor,
        hasMore: items.length === limit,
      });
    }

    // ——— Webhook paiement ———
    if (method === "POST" && path === "/api/v1/payments/webhook") {
      const raw = await req.text();
      const s = getSecrets();
      const skip = Deno.env.get("SKIP_WEBHOOK_VERIFY") === "true";
      if (!skip) {
        const header = req.headers.get("x-webhook-signature") ||
          req.headers.get("x-signature") ||
          "";
        const match = header.match(/^(?:sha256=)?([a-fA-F0-9]+)$/);
        if (!match || !s.webhookSecret) {
          return jsonResponse({
            status: "error",
            code: "INVALID_SIGNATURE",
            message: "Signature manquante ou invalide",
          }, 401);
        }
        const expected = await sha256Hex(s.webhookSecret, raw);
        if (!safeEqual(match[1].toLowerCase(), expected)) {
          return jsonResponse({
            status: "error",
            code: "INVALID_SIGNATURE",
            message: "Signature webhook invalide",
          }, 401);
        }
      }
      const body = JSON.parse(raw || "{}") as Record<string, unknown>;
      const bId = body.business_id as string | undefined;
      if (!bId) {
        return jsonResponse({
          status: "error",
          message: "business_id requis",
        }, 400);
      }
      const status = body.status;
      const ok = status === "ACCEPTED" ||
        status === "SUCCESS" ||
        status === "100" ||
        status === 100;
      if (!ok) {
        return jsonResponse({
          code: "400",
          message: "Transaction non acceptée",
        });
      }
      const txId = String(
        body.cpay_trans_id || body.transaction_id || "",
      ).trim();
      if (!txId) {
        return jsonResponse({
          code: "400",
          message: "transaction_id requis",
        }, 400);
      }
      const { data, error } = await sb().rpc("process_payment_webhook", {
        p_transaction_id: txId,
        p_business_id: bId,
        p_payload_hash: await digestHex(raw),
        p_plan_name: String(body.plan_name || "PRO"),
      });
      if (error) {
        const missing = error.message.includes("SUBSCRIPTION_NOT_FOUND");
        return jsonResponse(
          { code: missing ? "404" : "500", message: error.message },
          missing ? 404 : 500,
        );
      }
      const result = (data || {}) as {
        duplicate?: boolean;
        expiresAt?: string;
      };
      return jsonResponse({
        code: "200",
        duplicate: result.duplicate === true,
        message: result.duplicate
          ? "Webhook déjà traité"
          : "SUCCES: Abonnement mis à jour",
        expires_at: result.expiresAt,
        transaction_id: txId,
      });
    }

    // ——— Admin routes (auth requise) ———
    if (path.startsWith("/api/v1/admin")) {
      const adminSession = await getAdminSession(extractBearer(req));
      if (!adminSession) {
        return jsonResponse({
          status: "error",
          code: "UNAUTHORIZED",
          message: "Authentification admin requise",
        }, 401);
      }
      return await handleAdmin(method, path, req, adminSession);
    }

    return jsonResponse({
      status: "error",
      message: "Route API introuvable",
      path,
    }, 404);
  } catch (e) {
    console.error(e);
    return jsonResponse({
      status: "error",
      message: e instanceof Error ? e.message : "Erreur serveur",
    }, 500);
  }
});

type SyncAuthorization = {
  authorized: boolean;
  privileged: boolean;
  businessId: string | null;
  deviceId: string | null;
};

async function authorizeSync(req: Request): Promise<SyncAuthorization> {
  const token = extractBearer(req);
  if (!token) {
    return {
      authorized: false,
      privileged: false,
      businessId: null,
      deviceId: null,
    };
  }
  if (await isSyncToken(token)) {
    return {
      authorized: true,
      privileged: true,
      businessId: null,
      deviceId: null,
    };
  }
  const tokenHash = await hashToken(token);
  const { data } = await sb()
    .from("device_sync_tokens")
    .select("id, business_id, revoked_at")
    .eq("token_hash", tokenHash)
    .maybeSingle();
  if (!data || data.revoked_at) {
    return {
      authorized: false,
      privileged: false,
      businessId: null,
      deviceId: null,
    };
  }
  await sb()
    .from("device_sync_tokens")
    .update({ last_used_at: new Date().toISOString() })
    .eq("id", data.id);
  return {
    authorized: true,
    privileged: false,
    businessId: String(data.business_id),
    deviceId: String(data.id),
  };
}

/** Résout business_id depuis jeton appareil (ou admin + query). */
async function resolveDeviceBusiness(
  req: Request,
): Promise<{ businessId: string | null; viaAdmin: boolean }> {
  const token = extractBearer(req);
  if (!token) return { businessId: null, viaAdmin: false };
  if (await isAdminToken(token) || await isSyncToken(token)) {
    const url = new URL(req.url);
    const q = url.searchParams.get("businessId") ||
      url.searchParams.get("business_id");
    return { businessId: q, viaAdmin: true };
  }
  const tokenHash = await hashToken(token);
  const { data } = await sb()
    .from("device_sync_tokens")
    .select("id, business_id, revoked_at")
    .eq("token_hash", tokenHash)
    .maybeSingle();
  if (!data || data.revoked_at) {
    return { businessId: null, viaAdmin: false };
  }
  await sb()
    .from("device_sync_tokens")
    .update({ last_used_at: new Date().toISOString() })
    .eq("id", data.id);
  return {
    businessId: data.business_id ? String(data.business_id) : null,
    viaAdmin: false,
  };
}

/**
 * GET /api/v1/subscription/status
 * Authorization: Bearer <device sync token>
 * Retourne le forfait / statut / expiration pour validation côté app.
 */
async function handleSubscriptionStatus(req: Request): Promise<Response> {
  const { businessId, viaAdmin } = await resolveDeviceBusiness(req);
  if (!businessId) {
    return jsonResponse({
      status: "error",
      code: "UNAUTHORIZED",
      message: viaAdmin
        ? "businessId requis pour jeton admin"
        : "Jeton appareil invalide ou manquant",
    }, 401);
  }

  const client = sb();
  const { data: biz } = await client
    .from("businesses")
    .select("id, name, status, agent_staff_id")
    .eq("id", businessId)
    .maybeSingle();

  if (!biz) {
    return jsonResponse({
      status: "error",
      code: "BUSINESS_NOT_FOUND",
      message: "Commerce introuvable côté cloud",
    }, 404);
  }

  const { data: subs } = await client
    .from("subscriptions")
    .select("id, plan_name, status, price_fcfa, expires_at, created_at")
    .eq("business_id", businessId)
    .order("created_at", { ascending: false })
    .limit(1);

  const sub = (subs && subs.length > 0) ? subs[0] : null;
  const now = new Date();
  let subStatus = sub?.status ? String(sub.status) : "missing";
  const expiresAt = sub?.expires_at ? String(sub.expires_at) : null;
  let expiredByDate = false;
  if (expiresAt) {
    const exp = new Date(expiresAt);
    // expires_at date-only → fin de journée UTC
    if (!Number.isNaN(exp.getTime()) && exp < now) {
      expiredByDate = true;
    }
  }
  if (sub && (subStatus === "active") && expiredByDate) {
    subStatus = "expired";
    // Aligne la base (admin + app cohérents)
    await client.from("subscriptions").update({ status: "expired" }).eq(
      "id",
      sub.id,
    );
  }

  const bizStatus = String(biz.status || "active");
  const licenseActive = subStatus === "active" && bizStatus === "active" &&
    !expiredByDate;

  return jsonResponse({
    status: "success",
    data: {
      businessId,
      businessName: biz.name,
      businessStatus: bizStatus,
      planName: sub?.plan_name || null,
      subscriptionStatus: subStatus,
      priceFcfa: sub?.price_fcfa ?? null,
      expiresAt,
      licenseActive,
      checkedAt: now.toISOString(),
      source: "supabase",
    },
  });
}

async function handleValidateCode(req: Request): Promise<Response> {
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const codeRaw = String(
    body.activationCode || body.activation_code || body.code || "",
  )
    .trim()
    .toUpperCase();
  if (!codeRaw || codeRaw.length < 6) {
    return jsonResponse({
      status: "error",
      code: "CODE_REQUIRED",
      message: "Saisissez le code d'activation fourni par votre agent.",
    }, 400);
  }
  const client = sb();
  const { data: reg, error } = await client
    .from("registration_codes")
    .select("code, status, plan_name, expires_at, staff_id")
    .eq("code", codeRaw)
    .maybeSingle();
  if (error) {
    return jsonResponse({ status: "error", message: error.message }, 500);
  }
  if (!reg) {
    return jsonResponse({
      status: "error",
      code: "INVALID_CODE",
      message: "Code invalide. Vérifiez avec votre agent Lynkstor.",
    }, 400);
  }
  if (reg.status === "revoked") {
    return jsonResponse({
      status: "error",
      code: "CODE_REVOKED",
      message: "Ce code a été révoqué. Demandez un nouveau code.",
    }, 400);
  }
  if (reg.status !== "unused") {
    return jsonResponse({
      status: "error",
      code: "CODE_USED",
      message: "Ce code a déjà été utilisé. Demandez un nouveau code.",
    }, 400);
  }
  if (reg.expires_at && new Date(reg.expires_at) < new Date()) {
    return jsonResponse({
      status: "error",
      code: "CODE_EXPIRED",
      message: "Code expiré. Demandez un nouveau code à votre agent.",
    }, 400);
  }
  return jsonResponse({
    status: "success",
    data: {
      code: reg.code,
      planName: reg.plan_name || "STARTER",
      expiresAt: reg.expires_at,
      valid: true,
    },
  });
}

async function handleRegister(req: Request): Promise<Response> {
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const codeRaw = String(body.activationCode || body.activation_code || "")
    .trim()
    .toUpperCase();
  if (!codeRaw || codeRaw.length < 6) {
    return jsonResponse({
      status: "error",
      code: "CODE_REQUIRED",
      message:
        "Un code d'activation fourni par un agent Lynkstor est obligatoire.",
    }, 400);
  }

  const business = (body.business || {}) as Record<string, unknown>;
  const user = (body.user || {}) as Record<string, unknown>;
  const name = String(business.name || "").trim();
  const ownerName = String(
    business.ownerName || business.owner_name || user.fullName || "",
  ).trim();
  const phone = String(business.phone || user.phone || "").trim();
  const sector = String(business.sector || "boutique");
  const city = business.city ? String(business.city) : null;
  const neighborhood = business.neighborhood
    ? String(business.neighborhood)
    : null;
  const businessId = String(business.id || crypto.randomUUID());
  const userId = String(user.id || crypto.randomUUID());

  if (!name || !ownerName || !phone) {
    return jsonResponse({
      status: "error",
      message: "name, ownerName et phone sont requis",
    }, 400);
  }

  const syncToken = generateSyncToken();
  const tokenHash = await hashToken(syncToken);
  const client = sb();
  const { data, error } = await client.rpc("register_business_atomic", {
    p_code: codeRaw,
    p_business_id: businessId,
    p_business_name: name,
    p_owner_name: ownerName,
    p_phone: phone,
    p_sector: sector,
    p_city: city,
    p_neighborhood: neighborhood,
    p_user_id: userId,
    p_subscription_id: `sub-${crypto.randomUUID()}`,
    p_token_id: `tok-${crypto.randomUUID()}`,
    p_token_hash: tokenHash,
  });
  if (error) {
    const knownCode = [
      "INVALID_CODE",
      "CODE_USED",
      "CODE_REVOKED",
      "CODE_EXPIRED",
      "REGISTRATION_INCOMPLETE",
    ].find(
      (code) => error.message.includes(code),
    );
    if (knownCode) {
      const messages: Record<string, string> = {
        INVALID_CODE: "Code d'activation invalide.",
        CODE_USED: "Ce code a déjà été utilisé ou révoqué.",
        CODE_REVOKED: "Ce code a été révoqué.",
        CODE_EXPIRED:
          "Ce code a expiré. Demandez un nouveau code à votre agent.",
        REGISTRATION_INCOMPLETE:
          "Inscription cloud incomplète. Contactez le support Lynkstor.",
      };
      return jsonResponse({
        status: "error",
        code: knownCode,
        message: messages[knownCode],
      }, 400);
    }
    return jsonResponse({ status: "error", message: error.message }, 500);
  }

  const registration = (data || {}) as Record<string, unknown>;
  const registeredBusinessId = String(
    registration.businessId || businessId,
  );
  const registeredUserId = String(registration.userId || userId);

  return jsonResponse({
    status: "success",
    data: {
      businessId: registeredBusinessId,
      userId: registeredUserId,
      planName: registration.planName || "STARTER",
      expiresAt: registration.expiresAt,
      syncToken,
      syncEndpoint: `${
        Deno.env.get("SUPABASE_URL")
      }/functions/v1/lynkstor-api/api/v1/sync/push`,
      message: "Commerce enregistré auprès de Lynkstor.",
    },
  }, 201);
}

async function handleAdmin(
  method: string,
  path: string,
  req: Request,
  session: AdminSession,
): Promise<Response> {
  const client = sb();
  const sub = path.replace(/^\/api\/v1\/admin/, "") || "/";
  const isSuperAdmin = ["admin", "super_admin"].includes(session.role);
  const isSupervisor = isSuperAdmin || session.role === "supervisor";
  const forbidden = () =>
    jsonResponse({
      status: "error",
      code: "FORBIDDEN",
      message: "Votre rôle ne permet pas cette action",
    }, 403);

  // GET /activation-codes ou /registration-codes
  if (
    method === "GET" &&
    (sub === "/activation-codes" || sub === "/registration-codes")
  ) {
    if (!isSupervisor) return forbidden();
    const { data, error } = await client
      .from("registration_codes")
      .select("*, staff_accounts(full_name), businesses(name)")
      .order("created_at", { ascending: false })
      .limit(100);

    if (error) {
      return jsonResponse({ status: "error", message: error.message }, 500);
    }
    const rows = (data || []).map((r: Record<string, unknown>) => ({
      ...r,
      staff_name: (r.staff_accounts as { full_name?: string } | null)
        ?.full_name,
      business_name: (r.businesses as { name?: string } | null)?.name,
      staff_accounts: undefined,
      businesses: undefined,
    }));
    return jsonResponse({ status: "success", data: rows });
  }

  // POST /activation-codes/generate ou /registration-codes — générer 1..N codes agent
  if (
    method === "POST" &&
    (sub === "/activation-codes/generate" || sub === "/registration-codes")
  ) {
    if (!isSupervisor) return forbidden();
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const staffId = (body.staff_id as string) || "st-04";
    const plan = (body.plan_name as string) || "PRO (Mensuel)";
    const months = parseInt(String(body.duration_months || "1"), 10) || 1;
    const count = Math.min(
      Math.max(parseInt(String(body.count || "1"), 10) || 1, 1),
      50,
    );
    const planUpper = plan.toUpperCase();
    const price = planUpper.includes("ENTERPRISE")
      ? 150000
      : planUpper.includes("PRO")
      ? 15000
      : 5000;

    const { data: staff } = await client
      .from("staff_accounts")
      .select("full_name, status")
      .eq("id", staffId)
      .maybeSingle();
    if (!staff || staff.status !== "active") {
      return jsonResponse({
        status: "error",
        code: "STAFF_NOT_FOUND",
        message: "Agent actif introuvable",
      }, 404);
    }

    const createdCodes: string[] = [];
    for (let i = 0; i < count; i++) {
      let inserted = false;
      for (let attempt = 0; attempt < 5 && !inserted; attempt++) {
        const code = `KMB-${generateActivationCode()}`;
        const { error: insertError } = await client
          .from("registration_codes")
          .insert({
            id: `rc-${crypto.randomUUID()}`,
            code,
            staff_id: staffId,
            plan_name: plan,
            price_fcfa: price,
            duration_months: months,
            status: "unused",
            expires_at: new Date(Date.now() + 30 * 86400000).toISOString(),
          });
        if (!insertError) {
          createdCodes.push(code);
          inserted = true;
        } else if (insertError.code !== "23505") {
          return jsonResponse({
            status: "error",
            code: "CODE_GENERATION_FAILED",
            message: insertError.message,
          }, 500);
        }
      }
      if (!inserted) {
        return jsonResponse({
          status: "error",
          code: "CODE_COLLISION",
          message: "Impossible de générer une clé unique. Réessayez.",
        }, 503);
      }
    }
    return jsonResponse({
      status: "success",
      count: createdCodes.length,
      staff_name: staff?.full_name || "Agent Commercial",
      codes: createdCodes,
      message: `${createdCodes.length} clé(s) d'activation générée(s) pour ${
        staff?.full_name || "l'agent"
      }`,
    }, 201);
  }

  // POST /activation-codes/revoke
  if (method === "POST" && sub === "/activation-codes/revoke") {
    if (!isSupervisor) return forbidden();
    const body = await req.json().catch(() => ({})) as { code?: string };
    if (!body.code) {
      return jsonResponse({ status: "error", message: "Code requis" }, 400);
    }
    const { data, error } = await client
      .from("registration_codes")
      .update({ status: "revoked" })
      .eq("code", body.code.trim().toUpperCase())
      .eq("status", "unused")
      .select("id");

    if (error) {
      return jsonResponse({ status: "error", message: error.message }, 400);
    }
    if (!data?.length) {
      return jsonResponse({
        status: "error",
        code: "CODE_NOT_AVAILABLE",
        message: "Cette clé est introuvable, déjà utilisée ou déjà révoquée",
      }, 409);
    }
    return jsonResponse({
      status: "success",
      message: `Code ${body.code} révoqué`,
    });
  }

  // GET /stats
  if (method === "GET" && sub === "/stats") {
    const [
      sales,
      businesses,
      users,
      subs,
      syncs,
      fields,
      agents,
      recent,
      allCodes,
      availableCodes,
      usedCodes,
    ] = await Promise.all([
      client.from("sales_summary").select("amount_fcfa"),
      client.from("businesses").select("id", { count: "exact", head: true }),
      client.from("users").select("id", { count: "exact", head: true }),
      client.from("subscriptions").select("id", { count: "exact", head: true })
        .eq("status", "active"),
      client.from("sync_events").select("id", { count: "exact", head: true }),
      client.from("field_activities").select("amount_collected_fcfa"),
      client.from("staff_accounts").select("id", { count: "exact", head: true })
        .eq("role", "commercial").eq("status", "active"),
      client.from("sales_summary").select(
        "*, businesses(name)",
      ).order("sold_at", { ascending: false }).limit(5),
      client.from("registration_codes").select("id", {
        count: "exact",
        head: true,
      }),
      client.from("registration_codes").select("id", {
        count: "exact",
        head: true,
      }).eq("status", "unused"),
      client.from("registration_codes").select("id", {
        count: "exact",
        head: true,
      }).eq("status", "used"),
    ]);

    const totalSales = (sales.data || []).reduce(
      (a, r) => a + Number(r.amount_fcfa || 0),
      0,
    );
    const totalField = (fields.data || []).reduce(
      (a, r) => a + Number(r.amount_collected_fcfa || 0),
      0,
    );
    const recentSales = (recent.data || []).map((
      s: Record<string, unknown>,
    ) => ({
      ...s,
      business_name: (s.businesses as { name?: string } | null)?.name,
      businesses: undefined,
    }));

    return jsonResponse({
      status: "success",
      data: {
        totalSalesFcfa: totalSales,
        totalBusinesses: businesses.count ?? 0,
        totalUsers: users.count ?? 0,
        activeSubscriptions: subs.count ?? 0,
        totalSyncEvents: syncs.count ?? 0,
        totalFieldCollectionsFcfa: totalField,
        activeFieldAgents: agents.count ?? 0,
        totalCodes: allCodes.count ?? 0,
        availableCodes: availableCodes.count ?? 0,
        usedCodes: usedCodes.count ?? 0,
        recentSales,
      },
    });
  }

  // GET /map-data
  if (method === "GET" && sub === "/map-data") {
    const { data: businesses } = await client.from("businesses").select(
      "*, subscriptions(plan_name, status, expires_at)",
    );
    const mapped = (businesses || []).map((b: Record<string, unknown>) => {
      const subs = b.subscriptions as
        | Array<{ plan_name?: string; status?: string; expires_at?: string }>
        | { plan_name?: string; status?: string; expires_at?: string }
        | null;
      const subRow = Array.isArray(subs) ? subs[0] : subs;
      return {
        ...b,
        plan_name: subRow?.plan_name,
        sub_status: subRow?.status,
        expires_at: subRow?.expires_at,
        subscriptions: undefined,
      };
    });
    const { data: commercials } = await client
      .from("staff_accounts")
      .select(
        "id, full_name, phone, role, status, current_lat, current_lng, last_ping_at",
      )
      .eq("role", "commercial");
    return jsonResponse({
      status: "success",
      data: { businesses: mapped, commercials: commercials || [] },
    });
  }

  // GET /staff
  if (method === "GET" && sub === "/staff") {
    if (!isSupervisor) return forbidden();
    const { data: staff, error: staffError } = await client
      .from("staff_accounts")
      .select(
        "id, full_name, username, email, phone, role, status, current_lat, current_lng, last_ping_at, created_at",
      )
      .order("created_at", { ascending: false });
    if (staffError) {
      return jsonResponse({
        status: "error",
        message: staffError.message,
      }, 500);
    }
    const { data: acts } = await client.from("field_activities").select(
      "staff_id, amount_collected_fcfa",
    );
    const byStaff: Record<string, { sum: number; n: number }> = {};
    for (const a of acts || []) {
      const id = a.staff_id as string;
      if (!byStaff[id]) byStaff[id] = { sum: 0, n: 0 };
      byStaff[id].sum += Number(a.amount_collected_fcfa || 0);
      byStaff[id].n += 1;
    }
    const rows = (staff || []).map((s) => ({
      ...s,
      total_collected_fcfa: byStaff[s.id]?.sum ?? 0,
      total_activations: byStaff[s.id]?.n ?? 0,
    }));
    return jsonResponse({ status: "success", data: rows });
  }

  // POST /staff
  if (method === "POST" && sub === "/staff") {
    if (!isSuperAdmin) return forbidden();
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    if (!body.full_name || typeof body.full_name !== "string") {
      return jsonResponse({
        status: "error",
        message: "full_name requis",
      }, 400);
    }
    const role = (body.role as string) || "commercial";
    if (!["super_admin", "supervisor", "commercial"].includes(role)) {
      return jsonResponse({ status: "error", message: "role invalide" }, 400);
    }
    const username = String(body.username || "").trim().toLowerCase();
    const password = String(body.password || "");
    if (!/^[a-z0-9._-]{3,40}$/.test(username)) {
      return jsonResponse({
        status: "error",
        code: "INVALID_USERNAME",
        message:
          "L'identifiant doit contenir 3 à 40 lettres, chiffres, points, tirets ou underscores",
      }, 400);
    }
    if (password.length < 8 || password.length > 128) {
      return jsonResponse({
        status: "error",
        code: "INVALID_PASSWORD",
        message: "Le mot de passe doit contenir entre 8 et 128 caractères",
      }, 400);
    }
    const email = body.email ? String(body.email).trim().toLowerCase() : null;
    const id = `st-${crypto.randomUUID()}`;
    const { error } = await client.from("staff_accounts").insert({
      id,
      full_name: String(body.full_name).trim(),
      username,
      password_hash: await hashPassword(password),
      email,
      phone: body.phone || null,
      role,
      status: "active",
    });
    if (error) {
      const duplicate = error.code === "23505";
      return jsonResponse({
        status: "error",
        code: duplicate ? "USERNAME_EXISTS" : "STAFF_CREATE_FAILED",
        message: duplicate ? "Cet identifiant est déjà utilisé" : error.message,
      }, duplicate ? 409 : 500);
    }
    return jsonResponse({
      status: "success",
      id,
      username,
      message: "Compte personnel créé avec succès",
    }, 201);
  }

  // POST /commercial/activate
  if (method === "POST" && sub === "/commercial/activate") {
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const bId = body.business_id as string;
    const stId = body.staff_id as string;
    if (!bId || !stId) {
      return jsonResponse({
        status: "error",
        message: "business_id et staff_id requis",
      }, 400);
    }
    if (session.role === "commercial" && session.staff_id !== stId) {
      return forbidden();
    }
    const price = body.price_fcfa !== undefined
      ? Number(body.price_fcfa)
      : 15000;
    const months = parseInt(String(body.duration_months || "1"), 10) || 1;
    const plan = (body.plan_name as string) || "PRO (Mensuel)";
    const expires = new Date();
    expires.setMonth(expires.getMonth() + months);
    const expiresStr = expires.toISOString().split("T")[0];

    const { data: updated } = await client
      .from("subscriptions")
      .update({
        status: "active",
        plan_name: plan,
        price_fcfa: price,
        expires_at: expiresStr,
      })
      .eq("business_id", bId)
      .select("id");

    if (!updated?.length) {
      await client.from("subscriptions").insert({
        id: `sub-${Date.now()}`,
        business_id: bId,
        plan_name: plan,
        status: "active",
        price_fcfa: price,
        expires_at: expiresStr,
      });
    }

    await client.from("field_activities").insert({
      id: `act-${Date.now()}`,
      staff_id: stId,
      business_id: bId,
      activity_type: "activation",
      amount_collected_fcfa: price,
      notes: (body.notes as string) || "Activation terrain commercial",
    });

    return jsonResponse({
      status: "success",
      message: `Abonnement ${plan} activé jusqu'au ${expiresStr}`,
      expires_at: expiresStr,
    });
  }

  // POST /commercial/ping
  if (method === "POST" && sub === "/commercial/ping") {
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const stId = body.staff_id as string;
    const lat = Number(body.latitude);
    const lng = Number(body.longitude);
    if (!stId || !Number.isFinite(lat) || !Number.isFinite(lng)) {
      return jsonResponse({
        status: "error",
        message: "staff_id, latitude, longitude requis",
      }, 400);
    }
    if (session.role === "commercial" && session.staff_id !== stId) {
      return forbidden();
    }
    const { data, error } = await client
      .from("staff_accounts")
      .update({
        current_lat: lat,
        current_lng: lng,
        last_ping_at: new Date().toISOString(),
      })
      .eq("id", stId)
      .select("id");
    if (error) {
      return jsonResponse({ status: "error", message: error.message }, 500);
    }
    if (!data?.length) {
      return jsonResponse({
        status: "error",
        message: "Agent introuvable",
      }, 404);
    }
    return jsonResponse({
      status: "success",
      message: "Position GPS mise à jour",
    });
  }

  // GET /field-activities
  if (method === "GET" && sub === "/field-activities") {
    const { data, error } = await client
      .from("field_activities")
      .select("*, staff_accounts(full_name), businesses(name)")
      .order("created_at", { ascending: false })
      .limit(50);
    if (error) {
      return jsonResponse({ status: "error", message: error.message }, 500);
    }
    const rows = (data || []).map((r: Record<string, unknown>) => ({
      ...r,
      staff_name: (r.staff_accounts as { full_name?: string } | null)
        ?.full_name,
      business_name: (r.businesses as { name?: string } | null)?.name,
      staff_accounts: undefined,
      businesses: undefined,
    }));
    return jsonResponse({ status: "success", data: rows });
  }

  // GET /users
  if (method === "GET" && sub === "/users") {
    if (!isSuperAdmin) return forbidden();
    const { data, error } = await client
      .from("users")
      .select("*, businesses(name, sector, subscriptions(plan_name, status))")
      .order("created_at", { ascending: false });
    if (error) {
      return jsonResponse({ status: "error", message: error.message }, 500);
    }
    const rows = (data || []).map((u: Record<string, unknown>) => {
      const b = u.businesses as {
        name?: string;
        sector?: string;
        subscriptions?:
          | Array<{ plan_name?: string; status?: string }>
          | { plan_name?: string; status?: string };
      } | null;
      const subRow = Array.isArray(b?.subscriptions)
        ? b?.subscriptions[0]
        : b?.subscriptions;
      return {
        ...u,
        business_name: b?.name,
        sector: b?.sector,
        plan_name: subRow?.plan_name,
        sub_status: subRow?.status,
        businesses: undefined,
      };
    });
    return jsonResponse({ status: "success", data: rows });
  }

  // GET /subscriptions
  if (method === "GET" && sub === "/subscriptions") {
    const { data, error } = await client
      .from("subscriptions")
      .select(
        "*, businesses(name, owner_name, phone, latitude, longitude)",
      )
      .order("created_at", { ascending: false });
    if (error) {
      return jsonResponse({ status: "error", message: error.message }, 500);
    }
    const rows = (data || []).map((s: Record<string, unknown>) => {
      const b = s.businesses as {
        name?: string;
        owner_name?: string;
        phone?: string;
        latitude?: number;
        longitude?: number;
      } | null;
      return {
        ...s,
        business_name: b?.name,
        owner_name: b?.owner_name,
        phone: b?.phone,
        latitude: b?.latitude,
        longitude: b?.longitude,
        businesses: undefined,
      };
    });
    return jsonResponse({ status: "success", data: rows });
  }

  // PUT /subscriptions/:id
  const subMatch = sub.match(/^\/subscriptions\/([^/]+)$/);
  if (method === "PUT" && subMatch) {
    if (!isSupervisor) return forbidden();
    const id = subMatch[1];
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    if (
      body.status &&
      !["active", "expired", "suspended"].includes(String(body.status))
    ) {
      return jsonResponse({ status: "error", message: "status invalide" }, 400);
    }
    const patch: Record<string, unknown> = {};
    if (body.plan_name != null) patch.plan_name = body.plan_name;
    if (body.status != null) patch.status = body.status;
    if (body.price_fcfa != null) patch.price_fcfa = body.price_fcfa;
    if (body.expires_at != null) patch.expires_at = body.expires_at;

    const { data, error } = await client
      .from("subscriptions")
      .update(patch)
      .eq("id", id)
      .select("id");
    if (error) {
      return jsonResponse({ status: "error", message: error.message }, 500);
    }
    if (!data?.length) {
      return jsonResponse({
        status: "error",
        message: "Abonnement introuvable",
      }, 404);
    }
    return jsonResponse({
      status: "success",
      message: "Abonnement mis à jour",
    });
  }

  // GET /analytics/summary
  if (method === "GET" && sub === "/analytics/summary") {
    if (!isSupervisor) return forbidden();
    const [eventsCount, installs, snapshots, named, sectors] = await Promise
      .all([
        client.from("trial_analytics_events").select("id", {
          count: "exact",
          head: true,
        }),
        client.from("trial_analytics_events").select("install_id"),
        client.from("trial_analytics_snapshots").select("*").order(
          "captured_at",
          { ascending: false },
        ).limit(400),
        client.from("trial_analytics_events").select("event_name"),
        client.from("trial_analytics_snapshots").select("sector, install_id"),
      ]);
    if (eventsCount.error) {
      return jsonResponse({
        status: "error",
        message: eventsCount.error.message,
      }, 500);
    }
    const installSet = new Set(
      (installs.data || []).map((r: { install_id?: string }) => r.install_id)
        .filter(Boolean),
    );
    const byEvent: Record<string, number> = {};
    for (const row of named.data || []) {
      const name = String(
        (row as { event_name?: string }).event_name || "unknown",
      );
      byEvent[name] = (byEvent[name] || 0) + 1;
    }
    const latestByInstall = new Map<string, Record<string, unknown>>();
    for (const row of snapshots.data || []) {
      const id = String((row as { install_id?: string }).install_id || "");
      if (!id || latestByInstall.has(id)) continue;
      latestByInstall.set(id, row as Record<string, unknown>);
    }
    const shops = [...latestByInstall.values()];
    const bySector: Record<string, number> = {};
    let sold = 0;
    let sales = 0;
    for (const shop of shops) {
      const sector = String(shop.sector || "inconnu");
      bySector[sector] = (bySector[sector] || 0) + 1;
      sold += Number(shop.sold_fcfa || 0);
      sales += Number(shop.sales_count || 0);
    }
    return jsonResponse({
      status: "success",
      data: {
        installs: installSet.size,
        events: eventsCount.count ?? 0,
        byEvent,
        bySector,
        totalSoldFcfa: sold,
        totalSales: sales,
        shops,
      },
    });
  }

  // GET /analytics/export
  if (method === "GET" && sub === "/analytics/export") {
    if (!isSupervisor) return forbidden();
    const { data, error } = await client
      .from("trial_analytics_events")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(5000);
    if (error) {
      return jsonResponse({ status: "error", message: error.message }, 500);
    }
    return jsonResponse({ status: "success", data: data || [] });
  }

  // GET /sync-logs
  if (method === "GET" && sub === "/sync-logs") {
    if (!isSuperAdmin) return forbidden();
    const { data, error } = await client
      .from("sync_events")
      .select("*, businesses(name)")
      .order("created_at", { ascending: false })
      .limit(50);
    if (error) {
      return jsonResponse({ status: "error", message: error.message }, 500);
    }
    const rows = (data || []).map((r: Record<string, unknown>) => ({
      ...r,
      business_name: (r.businesses as { name?: string } | null)?.name,
      businesses: undefined,
    }));
    return jsonResponse({ status: "success", data: rows });
  }

  return jsonResponse({
    status: "error",
    message: "Route admin introuvable",
    path: sub,
  }, 404);
}

const ANALYTICS_EVENTS = new Set([
  "app.opened",
  "app.background",
  "onboarding.completed",
  "screen.viewed",
  "sale.completed",
  "product.created",
  "catalog.opened",
  "catalog.activated",
  "customer.created",
  "expense.created",
  "debt.collected",
  "ai.used",
  "snapshot.daily",
  "error.captured",
  "analytics.exported",
]);

async function handleAnalyticsIngest(req: Request): Promise<Response> {
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const installId = String(body.installId || "").trim();
  if (!installId || installId.length > 80) {
    return jsonResponse({
      status: "error",
      message: "installId requis",
    }, 400);
  }
  const rawEvents = Array.isArray(body.events) ? body.events : [];
  if (rawEvents.length > 200) {
    return jsonResponse({
      status: "error",
      message: "Trop d’événements (max 200)",
    }, 400);
  }
  const sector = body.sector ? String(body.sector).slice(0, 40) : null;
  const businessId = body.businessId
    ? String(body.businessId).slice(0, 80)
    : null;
  const appVersion = body.appVersion
    ? String(body.appVersion).slice(0, 24)
    : null;
  const rows = [];
  for (const item of rawEvents) {
    if (!item || typeof item !== "object") continue;
    const ev = item as Record<string, unknown>;
    const name = String(ev.name || "");
    if (!ANALYTICS_EVENTS.has(name)) continue;
    const id = String(ev.id || "").slice(0, 80);
    if (!id) continue;
    rows.push({
      id,
      install_id: installId,
      business_id: businessId,
      sector,
      event_name: name,
      properties: ev.properties && typeof ev.properties === "object"
        ? ev.properties
        : {},
      app_version: appVersion,
      created_at: String(ev.createdAt || new Date().toISOString()),
    });
  }
  const client = sb();
  if (rows.length) {
    const { error } = await client.from("trial_analytics_events").upsert(
      rows,
      { onConflict: "id" },
    );
    if (error) {
      return jsonResponse({ status: "error", message: error.message }, 500);
    }
  }
  const snap = body.snapshot as Record<string, unknown> | undefined;
  if (snap && typeof snap === "object") {
    const { error } = await client.from("trial_analytics_snapshots").insert({
      id: crypto.randomUUID(),
      install_id: installId,
      business_id: businessId,
      sector,
      sales_count: Number(snap.salesCount || 0),
      sold_fcfa: Number(snap.soldFcfa || 0),
      products_count: Number(snap.productsCount || 0),
      catalog_activated_count: Number(snap.catalogActivatedCount || 0),
      customers_count: Number(snap.customersCount || 0),
      expenses_count: Number(snap.expensesCount || 0),
      event_count: Number(snap.eventCount || 0),
      open_days: Number(snap.openDays || 0),
      last_open_at: snap.lastOpenAt ? String(snap.lastOpenAt) : null,
      app_version: appVersion,
      captured_at: new Date().toISOString(),
    });
    if (error) {
      console.error("analytics snapshot insert", error);
    }
  }
  return jsonResponse({
    status: "success",
    accepted: rows.length,
  });
}
