const express = require('express');
const router = express.Router();
const { get, all, run } = require('./lib/db_async');
const {
  badRequest,
  validateStaff,
  validateActivate,
  validatePing,
} = require('./lib/validate');

// 1. Statistiques globales (KPIs réels)
router.get('/stats', async (req, res) => {
  try {
    const isCommercial = req.auth?.role === 'commercial';
    const staffId = req.auth?.staff_id;

    const [
      salesRow,
      bizRow,
      usersRow,
      subsRow,
      syncRow,
      fieldRow,
      agentsRow,
      totalCodesRow,
      availCodesRow,
      usedCodesRow,
      recentSales,
    ] = await Promise.all([
      get('SELECT COALESCE(SUM(amount_fcfa), 0) AS total FROM sales_summary'),
      get('SELECT COUNT(*) AS count FROM businesses'),
      get('SELECT COUNT(*) AS count FROM users'),
      get("SELECT COUNT(*) AS count FROM subscriptions WHERE status = 'active'"),
      get('SELECT COUNT(*) AS count FROM sync_events'),
      isCommercial
        ? get('SELECT COALESCE(SUM(amount_collected_fcfa), 0) AS total FROM field_activities WHERE staff_id = ?', [staffId])
        : get('SELECT COALESCE(SUM(amount_collected_fcfa), 0) AS total FROM field_activities'),
      get("SELECT COUNT(*) AS count FROM staff_accounts WHERE role = 'commercial' AND status = 'active'"),
      isCommercial
        ? get('SELECT COUNT(*) AS count FROM activation_codes WHERE staff_id = ?', [staffId])
        : get('SELECT COUNT(*) AS count FROM activation_codes'),
      isCommercial
        ? get("SELECT COUNT(*) AS count FROM activation_codes WHERE staff_id = ? AND status = 'available'", [staffId])
        : get("SELECT COUNT(*) AS count FROM activation_codes WHERE status = 'available'"),
      isCommercial
        ? get("SELECT COUNT(*) AS count FROM activation_codes WHERE staff_id = ? AND status = 'used'", [staffId])
        : get("SELECT COUNT(*) AS count FROM activation_codes WHERE status = 'used'"),
      all(`
        SELECT s.*, b.name AS business_name
        FROM sales_summary s
        JOIN businesses b ON s.business_id = b.id
        ORDER BY s.sold_at DESC
        LIMIT 5
      `),
    ]);

    res.json({
      status: 'success',
      data: {
        totalSalesFcfa: salesRow?.total ?? 0,
        totalBusinesses: bizRow?.count ?? 0,
        totalUsers: usersRow?.count ?? 0,
        activeSubscriptions: subsRow?.count ?? 0,
        totalSyncEvents: syncRow?.count ?? 0,
        totalFieldCollectionsFcfa: fieldRow?.total ?? 0,
        activeFieldAgents: agentsRow?.count ?? 0,
        totalCodes: totalCodesRow?.count ?? 0,
        availableCodes: availCodesRow?.count ?? 0,
        usedCodes: usedCodesRow?.count ?? 0,
        recentSales: recentSales || [],
      },
    });
  } catch (err) {
    console.error('stats error:', err.message);
    res.status(500).json({ status: 'error', message: err.message });
  }
});

// 2. Données cartographiques GPS
router.get('/map-data', async (req, res) => {
  try {
    const isCommercial = req.auth?.role === 'commercial';
    const staffId = req.auth?.staff_id;

    const rawBusinesses = await all(`
      SELECT b.*, s.plan_name, s.status AS sub_status, s.expires_at,
             fa.staff_id, sa.full_name AS commercial_name
      FROM businesses b
      LEFT JOIN subscriptions s ON b.id = s.business_id
      LEFT JOIN field_activities fa ON b.id = fa.business_id AND fa.activity_type = 'activation'
      LEFT JOIN staff_accounts sa ON fa.staff_id = sa.id
    `);

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

    const businesses = rawBusinesses.map((b) => {
      let lat = b.latitude ? Number(b.latitude) : null;
      let lng = b.longitude ? Number(b.longitude) : null;
      const cityKey = (b.city || '').trim().toLowerCase();

      if (!lat || !lng || (lat === 5.3484 && lng === -4.0305)) {
        if (cityKey && CITY_COORDS[cityKey]) {
          lat = CITY_COORDS[cityKey].lat;
          lng = CITY_COORDS[cityKey].lng;
        } else if (cityKey.includes('yaound')) {
          lat = 3.8480; lng = 11.5021;
        } else if (cityKey.includes('douala')) {
          lat = 4.0511; lng = 9.7679;
        } else {
          lat = lat || 4.0511; // Default Douala
          lng = lng || 9.7679;
        }
      }
      return { ...b, latitude: lat, longitude: lng };
    });

    let commercialsSql = `
      SELECT id, full_name, phone, role, status, current_lat, current_lng, last_ping_at
      FROM staff_accounts
      WHERE role = 'commercial'
    `;
    const params = [];
    if (isCommercial) {
      commercialsSql += ' AND id = ?';
      params.push(staffId);
    }

    const commercials = await all(commercialsSql, params);

    res.json({
      status: 'success',
      data: { businesses, commercials },
    });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

// 3. Staff
router.get('/staff', async (req, res) => {
  try {
    const isCommercial = req.auth?.role === 'commercial';
    const staffId = req.auth?.staff_id;

    let sql = `
      SELECT s.id, s.username, s.full_name, s.email, s.phone, s.role, s.status, s.current_lat, s.current_lng, s.last_ping_at, s.created_at,
        (SELECT COALESCE(SUM(amount_collected_fcfa), 0) FROM field_activities WHERE staff_id = s.id) AS total_collected_fcfa,
        (SELECT COUNT(id) FROM field_activities WHERE staff_id = s.id) AS total_activations,
        (SELECT COUNT(code) FROM activation_codes WHERE staff_id = s.id AND status = 'available') AS available_codes_count
      FROM staff_accounts s
    `;
    const params = [];
    if (isCommercial) {
      sql += ' WHERE s.id = ?';
      params.push(staffId);
    }
    sql += ' ORDER BY s.created_at DESC';

    const rows = await all(sql, params);
    res.json({ status: 'success', data: rows });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

router.post('/staff', async (req, res) => {
  try {
    if (req.auth?.role === 'commercial') {
      return res.status(403).json({ status: 'error', message: 'Seuls les administrateurs et superviseurs peuvent créer des comptes staff.' });
    }

    const errors = validateStaff(req.body || {});
    if (errors.length) return badRequest(res, 'Données staff invalides', errors);

    const { full_name, email, phone, role, username, password } = req.body;
    const id = 'st-' + Date.now();

    const cleanUsername = username && username.trim()
      ? username.trim().toLowerCase()
      : (email ? email.split('@')[0].toLowerCase() : full_name.trim().toLowerCase().replace(/[^a-z0-9]/g, ''));

    const cleanPassword = password && password.trim() ? password.trim() : 'Password123';

    await run(
      `INSERT INTO staff_accounts (id, username, password_hash, full_name, email, phone, role, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'active')`,
      [id, cleanUsername, cleanPassword, full_name.trim(), email || null, phone || null, role || 'commercial']
    );

    res.status(201).json({
      status: 'success',
      id,
      username: cleanUsername,
      message: `Compte ${role || 'commercial'} créé avec succès (Identifiant: ${cleanUsername})`,
    });
  } catch (err) {
    if (err.message && err.message.includes('UNIQUE constraint failed')) {
      return res.status(400).json({ status: 'error', message: 'Cet identifiant (username) est déjà utilisé.' });
    }
    res.status(500).json({ status: 'error', message: err.message });
  }
});

// 3b. Codes d'activation uniques par commercial
router.get('/activation-codes', async (req, res) => {
  try {
    const isCommercial = req.auth?.role === 'commercial';
    const staffId = req.auth?.staff_id;

    let sql = `
      SELECT ac.*, sa.full_name AS staff_name, sa.phone AS staff_phone,
             b.name AS business_name, b.phone AS business_phone,
             creator.full_name AS creator_name
      FROM activation_codes ac
      LEFT JOIN staff_accounts sa ON ac.staff_id = sa.id
      LEFT JOIN staff_accounts creator ON ac.created_by_staff_id = creator.id
      LEFT JOIN businesses b ON ac.business_id = b.id
    `;
    const params = [];
    const conditions = [];

    if (isCommercial) {
      conditions.push('ac.staff_id = ?');
      params.push(staffId);
    } else if (req.query.staff_id) {
      conditions.push('ac.staff_id = ?');
      params.push(req.query.staff_id);
    }

    if (req.query.status) {
      conditions.push('ac.status = ?');
      params.push(req.query.status);
    }

    if (conditions.length > 0) {
      sql += ' WHERE ' + conditions.join(' AND ');
    }

    sql += ' ORDER BY ac.created_at DESC';

    const rows = await all(sql, params);
    res.json({ status: 'success', data: rows });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

router.post('/activation-codes/generate', async (req, res) => {
  try {
    if (req.auth?.role === 'commercial') {
      return res.status(403).json({ status: 'error', message: 'Seuls les administrateurs et superviseurs peuvent générer des lots de clés.' });
    }

    const { staff_id, plan_name, duration_months, count } = req.body || {};
    const effectiveStaffId = (staff_id && String(staff_id).trim()) || req.auth?.staff_id || 'st-04';

    let staff = await get('SELECT id, full_name FROM staff_accounts WHERE id = ?', [effectiveStaffId]);
    if (!staff) {
      staff = { id: effectiveStaffId, full_name: req.auth?.full_name || 'Agent Commercial' };
    }

    const qty = Math.min(Math.max(parseInt(count || '1', 10) || 1, 1), 50);
    const plan = plan_name || 'PRO (Mensuel)';
    const months = parseInt(duration_months || '1', 10) || 1;
    const creatorId = req.auth?.staff_id || 'st-04';

    const generatedCodes = [];

    for (let i = 0; i < qty; i++) {
      const part1 = Math.floor(1000 + Math.random() * 9000);
      const part2 = Math.floor(1000 + Math.random() * 9000);
      const code = `KMB-${part1}-${part2}`;

      await run(
        `INSERT INTO activation_codes
           (code, staff_id, created_by_staff_id, plan_name, duration_months, status)
         VALUES (?, ?, ?, ?, ?, 'available')`,
        [code, effectiveStaffId, creatorId, plan, months]
      );
      generatedCodes.push(code);
    }

    res.status(201).json({
      status: 'success',
      count: generatedCodes.length,
      staff_name: staff.full_name,
      codes: generatedCodes,
      message: `${generatedCodes.length} clé(s) d'activation générée(s) pour ${staff.full_name}`,
    });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

router.post('/activation-codes/revoke', async (req, res) => {
  try {
    const { code } = req.body || {};
    if (!code) return badRequest(res, 'Code d\'activation requis');

    const result = await run(
      `UPDATE activation_codes
       SET status = 'revoked'
       WHERE code = ? AND status = 'available'`,
      [code.trim().toUpperCase()]
    );

    if (result.changes === 0) {
      return res.status(400).json({ status: 'error', message: 'Code introuvable ou déjà utilisé/révoqué' });
    }

    res.json({ status: 'success', message: `Code ${code} révoqué avec succès` });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

// 4. Activation express abonnement (terrain)
router.post('/commercial/activate', async (req, res) => {
  try {
    const errors = validateActivate(req.body || {});
    if (errors.length) return badRequest(res, 'Activation invalide', errors);

    const {
      business_id: bId,
      staff_id: stId,
      plan_name,
      price_fcfa,
      duration_months,
      notes,
    } = req.body;

    const price = price_fcfa !== undefined ? Number(price_fcfa) : 15000;
    const months = parseInt(duration_months || '1', 10) || 1;

    const biz = await get('SELECT id FROM businesses WHERE id = ?', [bId]);
    if (!biz) {
      return res.status(404).json({ status: 'error', message: 'Commerce introuvable' });
    }
    const staff = await get('SELECT id FROM staff_accounts WHERE id = ?', [stId]);
    if (!staff) {
      return res.status(404).json({ status: 'error', message: 'Agent introuvable' });
    }

    const expiresDate = new Date();
    expiresDate.setMonth(expiresDate.getMonth() + months);
    const expiresStr = expiresDate.toISOString().split('T')[0];

    const subUpdate = await run(
      `UPDATE subscriptions
       SET status = 'active', plan_name = ?, price_fcfa = ?, expires_at = ?
       WHERE business_id = ?`,
      [plan_name || 'PRO (Mensuel)', price, expiresStr, bId]
    );

    if (subUpdate.changes === 0) {
      // Créer un abonnement s'il n'existe pas encore
      const subId = 'sub-' + Date.now();
      await run(
        `INSERT INTO subscriptions (id, business_id, plan_name, status, price_fcfa, expires_at)
         VALUES (?, ?, ?, 'active', ?, ?)`,
        [subId, bId, plan_name || 'PRO (Mensuel)', price, expiresStr]
      );
    }

    const actId = 'act-' + Date.now();
    await run(
      `INSERT INTO field_activities
         (id, staff_id, business_id, activity_type, amount_collected_fcfa, notes)
       VALUES (?, ?, ?, 'activation', ?, ?)`,
      [actId, stId, bId, price, notes || 'Activation terrain commercial']
    );

    console.log(
      `⚡ [Activation] Commerce=${bId} Agent=${stId} Plan=${plan_name} Expire=${expiresStr}`
    );

    res.json({
      status: 'success',
      message: `Abonnement ${plan_name || 'PRO'} activé jusqu'au ${expiresStr}`,
      expires_at: expiresStr,
    });
  } catch (err) {
    console.error('activate error:', err.message);
    res.status(500).json({ status: 'error', message: err.message });
  }
});

// 5. Ping GPS commercial
router.post('/commercial/ping', async (req, res) => {
  try {
    const errors = validatePing(req.body || {});
    if (errors.length) return badRequest(res, 'Ping GPS invalide', errors);

    const { staff_id: stId, latitude, longitude } = req.body;
    const result = await run(
      `UPDATE staff_accounts
       SET current_lat = ?, current_lng = ?, last_ping_at = CURRENT_TIMESTAMP
       WHERE id = ?`,
      [Number(latitude), Number(longitude), stId]
    );

    if (result.changes === 0) {
      return res.status(404).json({ status: 'error', message: 'Agent introuvable' });
    }

    res.json({ status: 'success', message: 'Position GPS mise à jour' });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

// 6. Activités terrain
router.get('/field-activities', async (req, res) => {
  try {
    const rows = await all(`
      SELECT fa.*, sa.full_name AS staff_name, b.name AS business_name
      FROM field_activities fa
      JOIN staff_accounts sa ON fa.staff_id = sa.id
      JOIN businesses b ON fa.business_id = b.id
      ORDER BY fa.created_at DESC
      LIMIT 50
    `);
    res.json({ status: 'success', data: rows });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

// 7. Users & abonnements
router.get('/users', async (req, res) => {
  try {
    const rows = await all(`
      SELECT u.*, b.name AS business_name, b.sector, s.plan_name, s.status AS sub_status
      FROM users u
      LEFT JOIN businesses b ON u.business_id = b.id
      LEFT JOIN subscriptions s ON b.id = s.business_id
      ORDER BY u.created_at DESC
    `);
    res.json({ status: 'success', data: rows });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

router.get('/subscriptions', async (req, res) => {
  try {
    const rows = await all(`
      SELECT s.*, b.name AS business_name, b.owner_name, b.phone, b.latitude, b.longitude
      FROM subscriptions s
      JOIN businesses b ON s.business_id = b.id
      ORDER BY s.created_at DESC
    `);
    res.json({ status: 'success', data: rows });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

router.put('/subscriptions/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { plan_name, status, price_fcfa, expires_at } = req.body || {};

    if (status && !['active', 'expired', 'suspended'].includes(status)) {
      return badRequest(res, 'status invalide (active|expired|suspended)');
    }
    if (price_fcfa !== undefined && Number(price_fcfa) < 0) {
      return badRequest(res, 'price_fcfa invalide');
    }

    const result = await run(
      `UPDATE subscriptions
       SET plan_name = COALESCE(?, plan_name),
           status = COALESCE(?, status),
           price_fcfa = COALESCE(?, price_fcfa),
           expires_at = COALESCE(?, expires_at)
       WHERE id = ?`,
      [plan_name ?? null, status ?? null, price_fcfa ?? null, expires_at ?? null, id]
    );

    if (result.changes === 0) {
      return res.status(404).json({ status: 'error', message: 'Abonnement introuvable' });
    }

    res.json({ status: 'success', message: 'Abonnement mis à jour' });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

router.get('/sync-logs', async (req, res) => {
  try {
    const rows = await all(`
      SELECT se.*, b.name AS business_name
      FROM sync_events se
      LEFT JOIN businesses b ON se.business_id = b.id
      ORDER BY se.created_at DESC
      LIMIT 50
    `);
    res.json({ status: 'success', data: rows });
  } catch (err) {
    res.status(500).json({ status: 'error', message: err.message });
  }
});

module.exports = router;
