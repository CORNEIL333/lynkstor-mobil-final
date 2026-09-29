const crypto = require('crypto');
const config = require('../config');

function extractBearer(req) {
  const header = req.headers.authorization || '';
  if (header.startsWith('Bearer ')) {
    return header.slice(7).trim();
  }
  // Fallback pour clients qui envoient X-API-Key
  const apiKey = req.headers['x-api-key'];
  if (apiKey && typeof apiKey === 'string') {
    return apiKey.trim();
  }
  return null;
}

function timingSafeEqualString(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) {
    // Compare against self to keep constant-ish work
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

function isValidAdminKey(token) {
  return timingSafeEqualString(token, config.adminApiKey);
}

function createAdminSession() {
  const payload = Buffer.from(JSON.stringify({
    role: 'admin',
    exp: Date.now() + 8 * 60 * 60 * 1000,
  })).toString('base64url');
  const signature = crypto
    .createHmac('sha256', config.adminApiKey)
    .update(payload)
    .digest('base64url');
  return `${payload}.${signature}`;
}

function createStaffSession(staff) {
  const payload = Buffer.from(
    JSON.stringify({
      staff_id: staff.id,
      role: staff.role || 'commercial',
      full_name: staff.full_name,
      email: staff.email,
      exp: Date.now() + 12 * 60 * 60 * 1000,
    })
  ).toString('base64url');
  const signature = crypto
    .createHmac('sha256', config.adminApiKey)
    .update(payload)
    .digest('base64url');
  return `${payload}.${signature}`;
}

function parseSessionToken(token) {
  if (typeof token !== 'string') return null;
  const [payload, signature, extra] = token.split('.');
  if (!payload || !signature || extra) return null;
  const expected = crypto
    .createHmac('sha256', config.adminApiKey)
    .update(payload)
    .digest('base64url');
  if (!timingSafeEqualString(signature, expected)) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (Number(data.exp) > Date.now()) {
      return data;
    }
    return null;
  } catch (_) {
    return null;
  }
}

function isValidAdminSession(token) {
  const sess = parseSessionToken(token);
  return sess && (sess.role === 'admin' || sess.role === 'super_admin');
}

function isValidSyncKey(token) {
  if (isValidAdminKey(token)) return true;
  if (parseSessionToken(token)) return true;
  if (config.syncApiKey) {
    return timingSafeEqualString(token, config.syncApiKey);
  }
  return isValidAdminKey(token);
}

/** Protège les routes admin dashboard */
function requireAdmin(req, res, next) {
  const token = extractBearer(req);
  if (token && isValidAdminKey(token)) {
    req.auth = { role: 'super_admin', staff_id: 'st-04', full_name: 'Super Admin' };
    return next();
  }

  const session = parseSessionToken(token);
  if (session) {
    req.auth = session;
    return next();
  }

  return res.status(401).json({
    status: 'error',
    code: 'UNAUTHORIZED',
    message: 'Authentification requise (Identifiants invalides ou session expirée)',
  });
}

/** Protège push/pull sync mobile */
function requireSync(req, res, next) {
  const token = extractBearer(req);
  if (!token || !isValidSyncKey(token)) {
    return res.status(401).json({
      status: 'error',
      code: 'UNAUTHORIZED',
      message: 'Authentification sync requise (Bearer SYNC_API_KEY ou ADMIN_API_KEY)',
    });
  }
  req.auth = { role: 'sync' };
  next();
}

/**
 * Login flexible : Admin maître OU compte Staff (Commercial / Superviseur)
 */
async function handleLogin(req, res) {
  const { username, password } = req.body || {};
  if (typeof username !== 'string' || typeof password !== 'string') {
    return res.status(400).json({
      status: 'error',
      message: 'Identifiant et mot de passe requis',
    });
  }

  const cleanUser = username.trim();
  const cleanPass = password.trim();

  // 1. Vérification Admin maître
  if (
    timingSafeEqualString(cleanUser, config.adminUser) &&
    timingSafeEqualString(cleanPass, config.adminPassword)
  ) {
    return res.json({
      status: 'success',
      token: createAdminSession(),
      token_type: 'Bearer',
      role: 'super_admin',
      staff_id: 'st-04',
      full_name: 'Super Admin Lynkstor',
      expires_in: 8 * 60 * 60,
    });
  }

  // 2. Vérification comptes Staff (sqlite)
  try {
    const { get } = require('../lib/db_async');
    const staff = await get(
      `SELECT * FROM staff_accounts
       WHERE (LOWER(username) = LOWER(?) OR LOWER(email) = LOWER(?) OR phone = ?)
         AND status = 'active'`,
      [cleanUser, cleanUser, cleanUser]
    );

    if (staff && staff.password_hash) {
      // Support mot de passe simple ou hashé
      const match = timingSafeEqualString(cleanPass, staff.password_hash);
      if (match) {
        const token = createStaffSession(staff);
        return res.json({
          status: 'success',
          token,
          token_type: 'Bearer',
          role: staff.role || 'commercial',
          staff_id: staff.id,
          full_name: staff.full_name,
          email: staff.email,
          expires_in: 12 * 60 * 60,
        });
      }
    }
  } catch (err) {
    console.error('Login DB Error:', err.message);
  }

  // Anti-bruteforce delay
  setTimeout(() => {
    res.status(401).json({
      status: 'error',
      code: 'INVALID_CREDENTIALS',
      message: 'Identifiants ou mot de passe incorrects',
    });
  }, 400);
}

module.exports = {
  requireAdmin,
  requireSync,
  requireWebhookSignature,
  handleLogin,
  extractBearer,
  parseSessionToken,
};
