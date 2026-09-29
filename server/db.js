const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');

// En Docker : monter un volume sur /app/data pour persister la base
const dataDir = process.env.DATA_DIR || __dirname;
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}
const dbPath = path.join(dataDir, 'kumba_central.db');
const db = new sqlite3.Database(dbPath);

db.serialize(() => {
  db.run('PRAGMA foreign_keys = ON');
  // 1. Table Commerces (Businesses) avec Coordonnées GPS
  db.run(`
    CREATE TABLE IF NOT EXISTS businesses (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      sector TEXT DEFAULT 'general',
      phone TEXT,
      owner_name TEXT,
      status TEXT DEFAULT 'active',
      latitude REAL DEFAULT 5.3484,
      longitude REAL DEFAULT -4.0305,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);

  // 2. Table Utilisateurs Clients
  db.run(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      business_id TEXT,
      full_name TEXT NOT NULL,
      phone TEXT,
      role TEXT DEFAULT 'seller',
      status TEXT DEFAULT 'active',
      last_login_at DATETIME,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(business_id) REFERENCES businesses(id)
    )
  `);

  // 3. Table Abonnements
  db.run(`
    CREATE TABLE IF NOT EXISTS subscriptions (
      id TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      plan_name TEXT DEFAULT 'PRO',
      status TEXT DEFAULT 'active',
      price_fcfa REAL DEFAULT 15000,
      started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      expires_at DATETIME,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(business_id) REFERENCES businesses(id)
    )
  `);

  // 4. Table Comptes Personnel / Staff (Admin, Superviseur, Commercial Terrain)
  db.run(`
    CREATE TABLE IF NOT EXISTS staff_accounts (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE,
      password_hash TEXT,
      full_name TEXT NOT NULL,
      email TEXT,
      phone TEXT,
      role TEXT CHECK(role IN ('super_admin', 'supervisor', 'commercial')) DEFAULT 'commercial',
      status TEXT DEFAULT 'active',
      current_lat REAL,
      current_lng REAL,
      last_ping_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);

  // Migration douce si la table existait sans username/password_hash
  db.run("ALTER TABLE staff_accounts ADD COLUMN username TEXT", () => {});
  db.run("ALTER TABLE staff_accounts ADD COLUMN password_hash TEXT", () => {});

  // 5. Table Clés / Codes d'Activation uniques attribués par commercial
  db.run(`
    CREATE TABLE IF NOT EXISTS activation_codes (
      code TEXT PRIMARY KEY,
      staff_id TEXT NOT NULL,
      created_by_staff_id TEXT,
      plan_name TEXT DEFAULT 'PRO (Mensuel)',
      duration_months INTEGER DEFAULT 1,
      status TEXT CHECK(status IN ('available', 'used', 'revoked', 'expired')) DEFAULT 'available',
      business_id TEXT,
      activated_at DATETIME,
      expires_at DATETIME,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(staff_id) REFERENCES staff_accounts(id),
      FOREIGN KEY(business_id) REFERENCES businesses(id)
    )
  `);

  // 6. Table Activités & Encaissements Terrain
  db.run(`
    CREATE TABLE IF NOT EXISTS field_activities (
      id TEXT PRIMARY KEY,
      staff_id TEXT NOT NULL,
      business_id TEXT NOT NULL,
      activity_type TEXT CHECK(activity_type IN ('activation', 'collection', 'visit')) DEFAULT 'activation',
      amount_collected_fcfa REAL DEFAULT 0,
      notes TEXT,
      latitude REAL,
      longitude REAL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(staff_id) REFERENCES staff_accounts(id),
      FOREIGN KEY(business_id) REFERENCES businesses(id)
    )
  `);

  // 7. Table Événements Sync
  db.run(`
    CREATE TABLE IF NOT EXISTS sync_events (
      id TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      entity_type TEXT,
      entity_id TEXT,
      operation TEXT,
      payload_json TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);

  // 8. Table Synthèse Ventes
  db.run(`
    CREATE TABLE IF NOT EXISTS sales_summary (
      id TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      amount_fcfa REAL NOT NULL,
      payment_method TEXT DEFAULT 'Espèces',
      sold_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);

  // Journal anti-rejeu des callbacks de paiement.
  db.run(`
    CREATE TABLE IF NOT EXISTS payment_webhook_events (
      transaction_id TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      payload_hash TEXT NOT NULL,
      received_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(business_id) REFERENCES businesses(id)
    )
  `);

  // Initialisation des données de démonstration avec géolocalisation réelle (Zone Abidjan)
  db.get("SELECT COUNT(*) as count FROM businesses", (err, row) => {
    if (!err && row.count === 0) {
      console.log('🌱 Base centrale vide — Injection des commerces et coordonnées GPS...');

      db.run("INSERT INTO businesses (id, name, sector, phone, owner_name, status, latitude, longitude) VALUES ('biz-01', 'Alimentation Générale la Grâce', 'epicerie', '+2250708091011', 'Kouamé Jean', 'active', 5.3484, -4.0305)");
      db.run("INSERT INTO businesses (id, name, sector, phone, owner_name, status, latitude, longitude) VALUES ('biz-02', 'Pharmacie & Parfumerie du Centre', 'pharmacie', '+2250504030201', 'Dr. Aminata Diallo', 'active', 5.3261, -4.0211)");
      db.run("INSERT INTO businesses (id, name, sector, phone, owner_name, status, latitude, longitude) VALUES ('biz-03', 'Boutique Quincaillerie Moderne', 'quincaillerie', '+221776543210', 'Mamadou Ndiaye', 'active', 5.3598, -3.9891)");
      db.run("INSERT INTO businesses (id, name, sector, phone, owner_name, status, latitude, longitude) VALUES ('biz-04', 'Dépôt de Boissons le Jardin', 'grossiste', '+22890112233', 'Kofi Messan', 'active', 5.3712, -4.0150)");

      db.run("INSERT INTO users (id, business_id, full_name, phone, role, status) VALUES ('u-01', 'biz-01', 'Kouamé Jean', '+2250708091011', 'owner', 'active')");
      db.run("INSERT INTO users (id, business_id, full_name, phone, role, status) VALUES ('u-02', 'biz-01', 'Yao Marc', '+2250102030405', 'seller', 'active')");
      db.run("INSERT INTO users (id, business_id, full_name, phone, role, status) VALUES ('u-03', 'biz-02', 'Dr. Aminata Diallo', '+2250504030201', 'owner', 'active')");
      db.run("INSERT INTO users (id, business_id, full_name, phone, role, status) VALUES ('u-04', 'biz-03', 'Mamadou Ndiaye', '+221776543210', 'owner', 'active')");
      db.run("INSERT INTO users (id, business_id, full_name, phone, role, status) VALUES ('u-05', 'biz-04', 'Kofi Messan', '+22890112233', 'owner', 'suspended')");

      db.run("INSERT INTO subscriptions (id, business_id, plan_name, status, price_fcfa, expires_at) VALUES ('sub-01', 'biz-01', 'PRO (Mensuel)', 'active', 15000, '2026-12-31')");
      db.run("INSERT INTO subscriptions (id, business_id, plan_name, status, price_fcfa, expires_at) VALUES ('sub-02', 'biz-02', 'ENTERPRISE (Annuel)', 'active', 150000, '2027-06-30')");
      db.run("INSERT INTO subscriptions (id, business_id, plan_name, status, price_fcfa, expires_at) VALUES ('sub-03', 'biz-03', 'STARTER', 'active', 5000, '2026-09-15')");
      db.run("INSERT INTO subscriptions (id, business_id, plan_name, status, price_fcfa, expires_at) VALUES ('sub-04', 'biz-04', 'GRATUIT (Essai)', 'expired', 0, '2026-07-01')");

      db.run("INSERT INTO sales_summary (id, business_id, amount_fcfa, payment_method) VALUES ('s-1', 'biz-01', 125000, 'Espèces')");
      db.run("INSERT INTO sales_summary (id, business_id, amount_fcfa, payment_method) VALUES ('s-2', 'biz-01', 450000, 'Orange Money')");
      db.run("INSERT INTO sales_summary (id, business_id, amount_fcfa, payment_method) VALUES ('s-3', 'biz-02', 890000, 'MTN MoMo')");
      db.run("INSERT INTO sales_summary (id, business_id, amount_fcfa, payment_method) VALUES ('s-4', 'biz-03', 340000, 'Espèces')");
      db.run("INSERT INTO sales_summary (id, business_id, amount_fcfa, payment_method) VALUES ('s-5', 'biz-04', 620000, 'Wave')");
    }
  });

  // Insertion des comptes Staff avec identifiants (mot de passe par défaut : "Password123")
  db.run("INSERT OR IGNORE INTO staff_accounts (id, username, password_hash, full_name, email, phone, role, status, current_lat, current_lng) VALUES ('st-01', 'kone', 'Password123', 'Amadou Koné', 'kone@lynkstor.com', '+2250701020304', 'commercial', 'active', 5.3510, -4.0280)");
  db.run("INSERT OR IGNORE INTO staff_accounts (id, username, password_hash, full_name, email, phone, role, status, current_lat, current_lng) VALUES ('st-02', 'bamba', 'Password123', 'Sandrine Bamba', 'bamba@lynkstor.com', '+2250505060708', 'commercial', 'active', 5.3300, -4.0180)");
  db.run("INSERT OR IGNORE INTO staff_accounts (id, username, password_hash, full_name, email, phone, role, status) VALUES ('st-03', 'kouassi', 'Password123', 'Marc Kouassi', 'kouassi@lynkstor.com', '+2250102030405', 'supervisor', 'active')");
  db.run("INSERT OR IGNORE INTO staff_accounts (id, username, password_hash, full_name, email, phone, role, status) VALUES ('st-04', 'admin', 'Password123', 'Super Admin Lynkstor', 'admin@lynkstor.com', '+2250000000000', 'super_admin', 'active')");

  // Mettre à jour les mots de passe si manquants (pour comptes existants)
  db.run("UPDATE staff_accounts SET username = 'kone', password_hash = 'Password123' WHERE id = 'st-01' AND (password_hash IS NULL OR password_hash = '')");
  db.run("UPDATE staff_accounts SET username = 'bamba', password_hash = 'Password123' WHERE id = 'st-02' AND (password_hash IS NULL OR password_hash = '')");
  db.run("UPDATE staff_accounts SET username = 'kouassi', password_hash = 'Password123' WHERE id = 'st-03' AND (password_hash IS NULL OR password_hash = '')");
  db.run("UPDATE staff_accounts SET username = 'admin', password_hash = 'Password123' WHERE id = 'st-04' AND (password_hash IS NULL OR password_hash = '')");

  // Seed des codes d'activation uniques par commercial
  db.run("INSERT OR IGNORE INTO activation_codes (code, staff_id, created_by_staff_id, plan_name, duration_months, status) VALUES ('KMB-KONE-8821', 'st-01', 'st-04', 'PRO (Mensuel)', 1, 'available')");
  db.run("INSERT OR IGNORE INTO activation_codes (code, staff_id, created_by_staff_id, plan_name, duration_months, status) VALUES ('KMB-KONE-9012', 'st-01', 'st-04', 'PRO (Mensuel)', 1, 'available')");
  db.run("INSERT OR IGNORE INTO activation_codes (code, staff_id, created_by_staff_id, plan_name, duration_months, status, business_id, activated_at) VALUES ('KMB-KONE-7701', 'st-01', 'st-04', 'PRO (Mensuel)', 1, 'used', 'biz-01', '2026-07-20 10:30:00')");
  db.run("INSERT OR IGNORE INTO activation_codes (code, staff_id, created_by_staff_id, plan_name, duration_months, status) VALUES ('KMB-BAMB-3341', 'st-02', 'st-03', 'STARTER', 1, 'available')");
  db.run("INSERT OR IGNORE INTO activation_codes (code, staff_id, created_by_staff_id, plan_name, duration_months, status) VALUES ('KMB-BAMB-5562', 'st-02', 'st-03', 'ENTERPRISE (Annuel)', 12, 'available')");
  db.run("INSERT OR IGNORE INTO activation_codes (code, staff_id, created_by_staff_id, plan_name, duration_months, status, business_id, activated_at) VALUES ('KMB-BAMB-1102', 'st-02', 'st-03', 'STARTER', 1, 'used', 'biz-03', '2026-07-22 14:15:00')");
  db.run("INSERT OR IGNORE INTO activation_codes (code, staff_id, created_by_staff_id, plan_name, duration_months, status) VALUES ('KMB-DEMO-0001', 'st-01', 'st-04', 'PRO (Mensuel)', 1, 'available')");

  db.run("INSERT OR IGNORE INTO field_activities (id, staff_id, business_id, activity_type, amount_collected_fcfa, notes, latitude, longitude) VALUES ('act-1', 'st-01', 'biz-01', 'activation', 15000, 'Abonnement PRO renouvelé en espèces', 5.3484, -4.0305)");
  db.run("INSERT OR IGNORE INTO field_activities (id, staff_id, business_id, activity_type, amount_collected_fcfa, notes, latitude, longitude) VALUES ('act-2', 'st-02', 'biz-03', 'activation', 5000, 'Abonnement STARTER encaissé Wave', 5.3598, -3.9891)");
});

module.exports = db;
