const express = require('express');
const cors = require('cors');
const path = require('path');
const crypto = require('crypto');

const config = require('./config');
const { run, get, all } = require('./lib/db_async');
const {
  requireAdmin,
  requireSync,
  requireWebhookSignature,
  handleLogin,
} = require('./middleware/auth');
const { badRequest, validateSyncPush } = require('./lib/validate');
const adminRoutes = require('./routes_admin');

const app = express();

// ——— CORS restreint ———
const corsOptions = {
  origin(origin, callback) {
    const allowed = config.corsOrigin;
    if (!allowed || allowed === '*') {
      // En prod sans CORS_ORIGIN, refuser les origines cross-site (même-origine OK)
      if (config.isProduction && origin) {
        return callback(null, false);
      }
      return callback(null, true);
    }
    const list = allowed.split(',').map((s) => s.trim()).filter(Boolean);
    if (!origin || list.includes(origin)) {
      return callback(null, true);
    }
    return callback(null, false);
  },
  methods: ['GET', 'POST', 'PUT', 'OPTIONS'],
  allowedHeaders: [
    'Content-Type',
    'Authorization',
    'X-API-Key',
    'X-Idempotency-Key',
    'X-Webhook-Signature',
  ],
};
app.use(cors(corsOptions));

// Capture raw body pour HMAC webhook
app.use(
  express.json({
    verify: (req, _res, buf) => {
      req.rawBody = buf;
    },
  })
);
app.use(express.urlencoded({ extended: true }));

// Interface Web Admin (statique)
app.use(express.static(path.join(__dirname, 'public')));

// ——— Auth publique (login dashboard) ———
app.post('/api/v1/auth/login', handleLogin);

// ——— Inscription & Validation des Codes d'Activation uniques (Mobile) ———
app.post('/api/v1/register/validate', async (req, res) => {
  try {
    const { activationCode } = req.body || {};
    if (typeof activationCode !== 'string' || !activationCode.trim()) {
      return badRequest(res, 'Code d\'activation requis');
    }
    const code = activationCode.trim().toUpperCase();
    const codeRow = await get(
      `SELECT ac.*, sa.full_name AS staff_name
       FROM activation_codes ac
       LEFT JOIN staff_accounts sa ON ac.staff_id = sa.id
       WHERE UPPER(ac.code) = ?`,
      [code]
    );

    if (!codeRow) {
      return res.status(404).json({
        status: 'error',
        message: 'Code d\'activation invalide ou inconnu.',
      });
    }

    if (codeRow.status === 'used') {
      return res.status(400).json({
        status: 'error',
        message: 'Ce code d\'activation a déjà été utilisé pour créer un autre compte commerce.',
      });
    }

    if (codeRow.status === 'revoked') {
      return res.status(400).json({
        status: 'error',
        message: 'Ce code d\'activation a été révoqué par le superviseur.',
      });
    }

    if (codeRow.expires_at && new Date(codeRow.expires_at) < new Date()) {
      return res.status(400).json({
        status: 'error',
        message: 'Ce code d\'activation a expiré.',
      });
    }

    const duration = codeRow.duration_months || 1;
    const expDate = new Date();
    expDate.setMonth(expDate.getMonth() + duration);

    return res.json({
      status: 'success',
      data: {
        valid: true,
        planName: codeRow.plan_name || 'PRO (Mensuel)',
        durationMonths: duration,
        expiresAt: expDate.toISOString(),
        staffName: codeRow.staff_name || 'Agent Lynkstor',
      },
    });
  } catch (err) {
    console.error('Validate activation code error:', err.message);
    return res.status(500).json({ status: 'error', message: 'Erreur lors de la vérification du code' });
  }
});

app.post('/api/v1/register', async (req, res) => {
  try {
    const { activationCode, business, user } = req.body || {};
    if (!activationCode || typeof activationCode !== 'string') {
      return badRequest(res, 'activationCode requis');
    }
    if (!business || !business.id || !business.name) {
      return badRequest(res, 'Informations commerce requises');
    }
    if (!user || !user.id || !user.fullName) {
      return badRequest(res, 'Informations utilisateur requises');
    }

    const code = activationCode.trim().toUpperCase();
    const codeRow = await get(
      `SELECT * FROM activation_codes WHERE UPPER(code) = ?`,
      [code]
    );

    const bId = business.id;
    const uId = user.id;

    if (!codeRow) {
      return res.status(400).json({
        status: 'error',
        message: "Code d'activation invalide.",
      });
    }

    // Gestion de la ré-essai (retry) si la création locale a échoué après l'appel cloud
    const isRetrySameBusiness = (codeRow.status === 'used' && codeRow.business_id === bId);

    if (codeRow.status !== 'available' && !isRetrySameBusiness) {
      return res.status(400).json({
        status: 'error',
        message: "Ce code d'activation a déjà été utilisé pour un autre commerce.",
      });
    }

    const now = new Date().toISOString();
    const duration = codeRow.duration_months || 1;
    const expDate = new Date();
    expDate.setMonth(expDate.getMonth() + duration);
    const expStr = expDate.toISOString().split('T')[0];

    // Résolution géographie (coordonnées par ville)
    let lat = business.latitude ? Number(business.latitude) : null;
    let lng = business.longitude ? Number(business.longitude) : null;
    const cityKey = (business.city || '').trim().toLowerCase();

    const CITY_COORDS = {
      'douala': { lat: 4.0511, lng: 9.7679 },
      'yaoundé': { lat: 3.8480, lng: 11.5021 },
      'yaounde': { lat: 3.8480, lng: 11.5021 },
      'bamenda': { lat: 5.9631, lng: 10.1591 },
      'bafoussam': { lat: 5.4778, lng: 10.4176 },
      'garoua': { lat: 9.3014, lng: 13.3977 },
      'maroua': { lat: 10.5910, lng: 14.3159 },
      'kumba': { lat: 4.6364, lng: 9.4469 },
      'ngaoundéré': { lat: 7.3167, lng: 13.5833 },
      'ngaoundere': { lat: 7.3167, lng: 13.5833 },
      'kribi': { lat: 2.9372, lng: 9.9077 },
      'limbe': { lat: 4.0244, lng: 9.2049 },
      'bertoua': { lat: 4.5772, lng: 13.6847 },
      'ebolowa': { lat: 2.9000, lng: 11.1500 },
      'abidjan': { lat: 5.3484, lng: -4.0305 },
      'yamoussoukro': { lat: 6.8276, lng: -5.2893 },
      'bouaké': { lat: 7.6900, lng: -5.0300 },
      'bouake': { lat: 7.6900, lng: -5.0300 },
      'san-pédro': { lat: 4.7485, lng: -6.6363 },
      'san pedro': { lat: 4.7485, lng: -6.6363 },
      'libreville': { lat: 0.4162, lng: 9.4673 },
      'kinshasa': { lat: -4.4419, lng: 15.2663 },
      'dakar': { lat: 14.7167, lng: -17.4677 },
    };

    if (!lat || !lng || (lat === 5.3484 && lng === -4.0305)) {
      if (cityKey && CITY_COORDS[cityKey]) {
        lat = CITY_COORDS[cityKey].lat;
        lng = CITY_COORDS[cityKey].lng;
      } else if (cityKey.includes('yaound')) {
        lat = 3.8480; lng = 11.5021;
      } else if (cityKey.includes('douala')) {
        lat = 4.0511; lng = 9.7679;
      } else {
        lat = lat || 4.0511; // Default fallback Douala
        lng = lng || 9.7679;
      }
    }

    await run('BEGIN IMMEDIATE TRANSACTION');
    try {
      // 1. Marquer le code comme consommé
      await run(
        `UPDATE activation_codes
         SET status = 'used', business_id = ?, activated_at = ?
         WHERE code = ?`,
        [bId, now, codeRow.code]
      );

      // 2. Créer le commerce
      await run(
        `INSERT INTO businesses (id, name, sector, phone, owner_name, status, latitude, longitude, city)
         VALUES (?, ?, ?, ?, ?, 'active', ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           name = excluded.name,
           owner_name = excluded.owner_name,
           phone = excluded.phone,
           latitude = excluded.latitude,
           longitude = excluded.longitude,
           city = excluded.city`,
        [
          bId,
          business.name,
          business.sector || 'general',
          business.phone || null,
          business.ownerName || null,
          lat,
          lng,
          business.city || null,
        ]
      );

      // 3. Créer l'utilisateur
      await run(
        `INSERT INTO users (id, business_id, full_name, phone, role, status)
         VALUES (?, ?, ?, ?, 'owner', 'active')
         ON CONFLICT(id) DO UPDATE SET
           full_name = excluded.full_name,
           phone = excluded.phone`,
        [uId, bId, user.fullName, user.phone || null]
      );

      // 4. Créer l'abonnement
      const subId = 'sub-' + Date.now();
      await run(
        `INSERT INTO subscriptions (id, business_id, plan_name, status, price_fcfa, expires_at)
         VALUES (?, ?, ?, 'active', ?, ?)
         ON CONFLICT(business_id) DO UPDATE SET
           plan_name = excluded.plan_name,
           status = 'active',
           expires_at = excluded.expires_at`,
        [subId, bId, codeRow.plan_name || 'PRO (Mensuel)', 15000, expStr]
      );

      // 5. Enregistrer l'activité terrain de l'agent commercial propriétaire du code
      const actId = 'act-' + Date.now();
      await run(
        `INSERT INTO field_activities
           (id, staff_id, business_id, activity_type, amount_collected_fcfa, notes)
         VALUES (?, ?, ?, 'activation', ?, ?)`,
        [
          actId,
          codeRow.staff_id,
          bId,
          15000,
          `Activation via clé ${codeRow.code} (${codeRow.plan_name})`,
        ]
      );

      await run('COMMIT');

      console.log(`🔑 [Clé activée] Code=${codeRow.code} Agent=${codeRow.staff_id} Commerce=${bId}`);

      return res.status(201).json({
        status: 'success',
        data: {
          businessId: bId,
          userId: uId,
          syncToken: config.syncApiKey || config.adminApiKey,
          syncEndpoint: `${config.corsOrigin || 'http://localhost:' + config.port}/api/v1/sync/push`,
          planName: codeRow.plan_name || 'PRO (Mensuel)',
          expiresAt: expStr,
        },
      });
    } catch (err) {
      await run('ROLLBACK').catch(() => {});
      throw err;
    }
  } catch (err) {
    console.error('Registration error:', err.message);
    return res.status(500).json({ status: 'error', message: err.message });
  }
});

// ——— Routes admin protégées ———
app.use('/api/v1/admin', requireAdmin, adminRoutes);

// Health check (public)
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'KUMBA Central Cloud Server',
    version: '1.1.0',
    timestamp: new Date().toISOString(),
    auth: 'required',
  });
});

// ——— Sync Push (mobile → serveur) ———
app.post('/api/v1/sync/push', requireSync, async (req, res) => {
  try {
    const errors = validateSyncPush(req.body || {});
    if (errors.length) return badRequest(res, 'Payload sync invalide', errors);

    const body = req.body;
    const businessId = body.businessId || body.business_id;
    const entityType = body.entityType || body.entity_type;
    const entityId = body.entityId || body.entity_id;
    const operation = body.operation;
    const payload = body.payload ?? body.payload_json ?? {};

    // Idempotence : id fourni, ou X-Idempotency-Key, ou hash déterministe
    const headerKey = req.headers['x-idempotency-key'];
    let itemId =
      (typeof body.id === 'string' && body.id.trim()) ||
      (typeof headerKey === 'string' && headerKey.trim()) ||
      null;

    if (!itemId) {
      itemId = crypto
        .createHash('sha256')
        .update(`${businessId}|${entityType}|${entityId}|${operation}`)
        .digest('hex')
        .slice(0, 32);
    }

    const existing = await get('SELECT id, created_at FROM sync_events WHERE id = ?', [itemId]);
    if (existing) {
      console.log(`📦 [Push Sync] duplicate id=${itemId} (idempotent OK)`);
      return res.status(200).json({
        status: 'success',
        duplicate: true,
        id: itemId,
        timestamp: existing.created_at || new Date().toISOString(),
      });
    }

    const payloadJson =
      typeof payload === 'string' ? payload : JSON.stringify(payload ?? {});

    if (entityType === 'sale' && ['create', 'upsert'].includes(operation)) {
      const salePayload =
        typeof payload === 'string' ? JSON.parse(payload) : payload;
      const amount = Number(salePayload.total);
      if (!Number.isFinite(amount) || amount < 0) {
        return badRequest(res, 'Total de vente synchronisé invalide');
      }
      await run(
        `INSERT INTO sales_summary
           (id, business_id, amount_fcfa, payment_method, sold_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           amount_fcfa = excluded.amount_fcfa,
           payment_method = excluded.payment_method,
           sold_at = excluded.sold_at`,
        [
          entityId,
          businessId,
          amount,
          Array.isArray(salePayload.paymentMethods)
            ? salePayload.paymentMethods.join(', ')
            : 'Non précisé',
          salePayload.soldAt || new Date().toISOString(),
        ]
      );
    }

    await run(
      `INSERT INTO sync_events (id, business_id, entity_type, entity_id, operation, payload_json)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [itemId, businessId, entityType, entityId, operation, payloadJson]
    );

    console.log(`📦 [Push Sync] item=${itemId} entity=${entityType}/${entityId} op=${operation}`);
    return res.status(201).json({
      status: 'success',
      duplicate: false,
      id: itemId,
      timestamp: new Date().toISOString(),
    });
  } catch (err) {
    console.error('Sync push error:', err.message);
    return res.status(500).json({
      status: 'error',
      code: 'SYNC_PUSH_FAILED',
      message: 'Échec de l\'enregistrement sync',
    });
  }
});

// ——— Sync Pull (serveur → mobile / autres appareils) ———
app.get('/api/v1/sync/pull', requireSync, async (req, res) => {
  try {
    const businessId = req.query.businessId || req.query.business_id;
    if (!businessId || typeof businessId !== 'string') {
      return badRequest(res, 'Query businessId requis');
    }

    const since = req.query.since; // ISO date optionnelle
    const limit = Math.min(parseInt(req.query.limit || '100', 10) || 100, 500);

    let sql = `
      SELECT id, business_id, entity_type, entity_id, operation, payload_json, created_at
      FROM sync_events
      WHERE business_id = ?
    `;
    const params = [businessId];

    if (since && typeof since === 'string') {
      sql += ' AND created_at > ?';
      params.push(since);
    }

    sql += ' ORDER BY created_at ASC LIMIT ?';
    params.push(limit);

    const rows = await all(sql, params);
    const items = rows.map((r) => {
      let payload = {};
      try {
        payload = r.payload_json ? JSON.parse(r.payload_json) : {};
      } catch (_) {
        payload = { raw: r.payload_json };
      }
      return {
        id: r.id,
        businessId: r.business_id,
        entityType: r.entity_type,
        entityId: r.entity_id,
        operation: r.operation,
        payload,
        createdAt: r.created_at,
      };
    });

    return res.json({
      status: 'success',
      items,
      count: items.length,
      limit,
    });
  } catch (err) {
    console.error('Sync pull error:', err.message);
    return res.status(500).json({
      status: 'error',
      code: 'SYNC_PULL_FAILED',
      message: 'Échec du pull sync',
    });
  }
});

// ——— Webhook paiement (HMAC obligatoire) ———
app.post(
  '/api/v1/payments/webhook',
  requireWebhookSignature,
  async (req, res) => {
    try {
      const body = req.body || {};
      const {
        cpay_trans_id,
        transaction_id,
        business_id,
        status,
        plan_name,
      } = body;

      const bId = business_id;
      if (!bId || typeof bId !== 'string') {
        return badRequest(res, 'business_id requis dans le webhook');
      }

      const txId = cpay_trans_id || transaction_id || null;
      if (typeof txId !== 'string' || txId.trim().length < 3) {
        return badRequest(res, 'transaction_id requis dans le webhook');
      }
      console.log(`💳 [Webhook] tx=${txId || 'n/a'} business=${bId} status=${status}`);

      const ok =
        status === 'ACCEPTED' ||
        status === 'SUCCESS' ||
        status === '100' ||
        status === 100;

      if (!ok) {
        return res.status(200).json({
          code: '400',
          message: 'Transaction non acceptée — abonnement non modifié',
        });
      }

      await run('BEGIN IMMEDIATE TRANSACTION');
      try {
        const duplicate = await get(
          'SELECT transaction_id FROM payment_webhook_events WHERE transaction_id = ?',
          [txId.trim()]
        );
        if (duplicate) {
          await run('COMMIT');
          return res.json({
            code: '200',
            duplicate: true,
            message: 'Webhook déjà traité',
            transaction_id: txId,
          });
        }

        const subscription = await get(
          'SELECT id, expires_at FROM subscriptions WHERE business_id = ?',
          [bId]
        );
        if (!subscription) {
          await run('ROLLBACK');
          console.warn(`⚠️  Webhook: aucun abonnement pour business_id=${bId}`);
          return res.status(404).json({
            code: '404',
            message: 'Commerce / abonnement introuvable',
          });
        }

        const now = new Date();
        const currentExpiry = subscription.expires_at
          ? new Date(subscription.expires_at)
          : now;
        const baseDate =
          Number.isFinite(currentExpiry.getTime()) && currentExpiry > now
            ? currentExpiry
            : now;
        baseDate.setMonth(baseDate.getMonth() + 1);
        const expiresStr = baseDate.toISOString();
        const payloadHash = crypto
          .createHash('sha256')
          .update(req.rawBody || Buffer.from(JSON.stringify(body)))
          .digest('hex');

        await run(
          `INSERT INTO payment_webhook_events
             (transaction_id, business_id, payload_hash)
           VALUES (?, ?, ?)`,
          [txId.trim(), bId, payloadHash]
        );
        await run(
          `UPDATE subscriptions
           SET status = 'active',
               plan_name = COALESCE(?, plan_name),
               expires_at = ?
           WHERE id = ?`,
          [plan_name || null, expiresStr, subscription.id]
        );
        await run('COMMIT');

        console.log(`✅ [Abonnement] ${bId} prolongé jusqu'au ${expiresStr}`);
        return res.json({
          code: '200',
          duplicate: false,
          message: 'SUCCES: Abonnement mis à jour',
          expires_at: expiresStr,
          transaction_id: txId,
        });
      } catch (error) {
        await run('ROLLBACK').catch(() => {});
        throw error;
      }
    } catch (err) {
      console.error('Webhook DB Error:', err.message);
      return res.status(500).json({
        code: '500',
        message: 'Erreur serveur webhook',
      });
    }
  }
);

// Page de retour paiement (publique, informative uniquement)
app.get('/payment-success', (req, res) => {
  res.send(`<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Paiement Réussi — Lynkstor Business</title>
</head>
<body style="font-family:sans-serif;text-align:center;padding:50px;background:#0f172a;color:white;">
  <h1 style="color:#10b981;">Paiement reçu</h1>
  <p>Si le paiement a été validé par l'agrégateur, votre abonnement <strong>Lynkstor Business</strong> sera activé sous peu.</p>
  <p>Vous pouvez retourner sur l'application mobile.</p>
</body>
</html>`);
});

// 404 API
app.use('/api', (req, res) => {
  res.status(404).json({ status: 'error', message: 'Route API introuvable' });
});

app.listen(config.port, () => {
  console.log(`
======================================================
🚀 KUMBA Central Cloud Server v1.1.0
🌐 Admin UI     : http://localhost:${config.port}
🔐 Auth         : Bearer ADMIN_API_KEY / SYNC_API_KEY
📦 Sync push    : POST /api/v1/sync/push
📥 Sync pull    : GET  /api/v1/sync/pull?businessId=
💳 Webhook      : POST /api/v1/payments/webhook (+ HMAC)
❤️  Health      : GET  /health
======================================================
  `);
});
