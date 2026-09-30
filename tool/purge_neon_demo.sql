SET search_path TO lynkstor,public;
BEGIN;

-- 1.etat AVANT purge (borne de controle)
SELECT 'biz_e2e'  AS scope, count(*) FROM businesses          WHERE id LIKE 'biz-e2e-%'
UNION ALL SELECT 'licences', count(*) FROM licenses            WHERE business_id LIKE 'biz-e2e-%'
UNION ALL SELECT 'codes',    count(*) FROM registration_codes  WHERE code IN ('LYNK-TEST-2026','LYNK-E2E-AUTO')
UNION ALL SELECT 'comptes_admin', count(*) FROM staff_accounts WHERE role = 'super_admin';

-- 2. enfants -> parents (aucune FK ON DELETE CASCADE supposee)
DELETE FROM payment_intents      WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
DELETE FROM licenses             WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
DELETE FROM subscriptions        WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
DELETE FROM sync_batches         WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
DELETE FROM sync_entities         WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
DELETE FROM sync_events          WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
DELETE FROM device_sync_cursors  WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
DELETE FROM device_sync_tokens   WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
DELETE FROM cloud_backup_records WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
DELETE FROM field_activities     WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
DELETE FROM business_invitations  WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');
-- Evenements d'analytique periode test emis par les runs E2E : install_id
-- 'e2e-<runId>' (tool/verify_neon_backend.mjs). Les installs reels ont un
-- install_id uuid et ne sont JAMAIS touches.
DELETE FROM trial_analytics_events WHERE install_id LIKE 'e2e-%';
DELETE FROM users                WHERE business_id IN (SELECT id FROM businesses WHERE id LIKE 'biz-e2e-%');

-- 3. codes d'activation de demonstration / de test
DELETE FROM registration_codes WHERE code IN ('LYNK-TEST-2026','LYNK-E2E-AUTO');

-- 4. credentials EPHEMERES utilises par les runs E2E seulement : le compte de
--    demonstration (admin/admin123) et le seed E2E a identifiant fixe. On ne
--    vise JAMAIS `role = 'super_admin'` en bloc : rejouer ce script apres la
--    creation d'un vrai compte d'exploitation ne doit pas vous verrouiller
--    hors de votre propre backend (empecherait /license/issue).
DELETE FROM staff_accounts WHERE username = 'admin' AND role = 'super_admin';   
DELETE FROM staff_accounts WHERE id = 'b0000000-0000-0000-0000-000000000001';   
-- Filets de securite : tout compte staff cree par un run E2E (prefixe e2e-).   
-- Un compte d'exploitation legitime ne s'appellera jamais e2e-*.               
DELETE FROM staff_accounts WHERE username LIKE 'e2e-%';

-- Teardown complet, volontairement commente : a decommenter seulement si tu
-- veux effacer TOUT compte super_admin (y compris le tien).
-- DELETE FROM staff_accounts WHERE role = 'super_admin';

DELETE FROM businesses WHERE id LIKE 'biz-e2e-%';

-- 4b. codes orphelins generes par /admin/codes/generate pendant les runs E2E.
--     Balance APRES la suppression des boutiques/staff de test : un code genere
--     reference desormais une boutique 'used' ou un staff 'assigned' disparus.
--     Un code legitime conserve toujours sa boutique (used) ou son staff (available
--     affecte) survivants, donc seules les references cassees + les codes
--     'used'/'void' sans boutique (residus de test pur) sont visees.
DELETE FROM registration_codes
 WHERE (used_by_business IS NOT NULL AND used_by_business NOT IN (SELECT id FROM businesses))
    OR (assigned_staff   IS NOT NULL AND assigned_staff   NOT IN (SELECT id FROM staff_accounts))
    OR (used_by_business IS NULL     AND status IN ('used','void'));

-- 5.etat APRES (attendu : 0 sur les scopes de test) + inventaire restant
SELECT 'biz_e2e' AS scope, count(*) FROM businesses          WHERE id LIKE 'biz-e2e-%'
UNION ALL SELECT 'licences_e2e', count(*) FROM licenses        WHERE business_id LIKE 'biz-e2e-%'
UNION ALL SELECT 'codes_demo', count(*) FROM registration_codes  WHERE code IN ('LYNK-TEST-2026','LYNK-E2E-AUTO')
UNION ALL SELECT 'admin_demo', count(*) FROM staff_accounts      WHERE username = 'admin'
UNION ALL SELECT 'staff_restants', count(*) FROM staff_accounts
UNION ALL SELECT 'super_admin_restants', count(*) FROM staff_accounts WHERE role = 'super_admin'
UNION ALL SELECT 'codes_total', count(*) FROM registration_codes
UNION ALL SELECT 'businesses_total', count(*) FROM businesses
UNION ALL SELECT 'users_total', count(*) FROM users
UNION ALL SELECT 'subscriptions_total', count(*) FROM subscriptions
UNION ALL SELECT 'plans_restants', count(*) FROM plans
UNION ALL SELECT 'licences_totales', count(*) FROM licenses;

COMMIT;
