/**
 * Validation légère des entrées API (sans dépendance externe).
 */

function isNonEmptyString(v, max = 500) {
  return typeof v === 'string' && v.trim().length > 0 && v.length <= max;
}

function isOptionalString(v, max = 500) {
  return v === undefined || v === null || v === '' || isNonEmptyString(v, max);
}

function isPositiveNumber(v) {
  const n = Number(v);
  return Number.isFinite(n) && n >= 0;
}

function isOneOf(v, allowed) {
  return allowed.includes(v);
}

function badRequest(res, message, details) {
  return res.status(400).json({
    status: 'error',
    code: 'VALIDATION_ERROR',
    message,
    details: details || undefined,
  });
}

function validateSyncPush(body) {
  const errors = [];
  if (!isNonEmptyString(body.businessId, 128) && !isNonEmptyString(body.business_id, 128)) {
    errors.push('businessId est requis');
  }
  const entityType = body.entityType || body.entity_type;
  if (!isNonEmptyString(entityType, 64)) {
    errors.push('entityType est requis');
  }
  const entityId = body.entityId || body.entity_id;
  if (!isNonEmptyString(entityId, 128)) {
    errors.push('entityId est requis');
  }
  const operation = body.operation;
  if (!isNonEmptyString(operation, 32)) {
    errors.push('operation est requis');
  } else if (!['create', 'update', 'delete', 'upsert'].includes(operation)) {
    errors.push('operation doit être create|update|delete|upsert');
  }
  return errors;
}

function validateStaff(body) {
  const errors = [];
  if (!isNonEmptyString(body.full_name, 120)) errors.push('full_name requis');
  if (!isOptionalString(body.email, 120)) errors.push('email invalide');
  if (!isOptionalString(body.phone, 40)) errors.push('phone invalide');
  if (body.role && !isOneOf(body.role, ['super_admin', 'supervisor', 'commercial'])) {
    errors.push('role invalide');
  }
  return errors;
}

function validateActivate(body) {
  const errors = [];
  if (!isNonEmptyString(body.business_id, 128)) errors.push('business_id requis');
  if (!isNonEmptyString(body.staff_id, 128)) errors.push('staff_id requis');
  if (body.price_fcfa !== undefined && !isPositiveNumber(body.price_fcfa)) {
    errors.push('price_fcfa invalide');
  }
  if (body.duration_months !== undefined) {
    const m = parseInt(body.duration_months, 10);
    if (!Number.isFinite(m) || m < 1 || m > 36) {
      errors.push('duration_months doit être entre 1 et 36');
    }
  }
  return errors;
}

function validatePing(body) {
  const errors = [];
  if (!isNonEmptyString(body.staff_id, 128)) errors.push('staff_id requis');
  const lat = Number(body.latitude);
  const lng = Number(body.longitude);
  if (!Number.isFinite(lat) || lat < -90 || lat > 90) errors.push('latitude invalide');
  if (!Number.isFinite(lng) || lng < -180 || lng > 180) errors.push('longitude invalide');
  return errors;
}

module.exports = {
  badRequest,
  validateSyncPush,
  validateStaff,
  validateActivate,
  validatePing,
  isNonEmptyString,
  isPositiveNumber,
};
