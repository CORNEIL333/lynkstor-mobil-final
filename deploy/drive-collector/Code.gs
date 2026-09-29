/**
 * Collecteur Lynkstor → Google Drive
 * Dossier : https://drive.google.com/drive/folders/18VAF4ZmazMKQizw_OWl2YEb5oE0wAdEw
 *
 * Déploiement : Extensions → Apps Script (ou script.google.com)
 * 1. Coller ce fichier
 * 2. Déployer → Nouveau déploiement → Application Web
 *    - Exécuter en tant que : Moi
 *    - Qui a accès : Tout le monde
 * 3. Copier l’URL /exec dans AppConfig.analyticsIngestUrl
 */

var FOLDER_ID = '18VAF4ZmazMKQizw_OWl2YEb5oE0wAdEw';
var SHEET_NAME = 'Lynkstor-panel-test';
var DUMP_FOLDER = 'dumps-json';

function doGet() {
  return ContentService.createTextOutput(
    JSON.stringify({ status: 'ok', service: 'lynkstor-drive-collector' }),
  ).setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  try {
    var raw = (e && e.postData && e.postData.contents) || '{}';
    var body = JSON.parse(raw);
    var result = ingest_(body);
    return ContentService.createTextOutput(JSON.stringify(result)).setMimeType(
      ContentService.MimeType.JSON,
    );
  } catch (err) {
    return ContentService.createTextOutput(
      JSON.stringify({ status: 'error', message: String(err) }),
    ).setMimeType(ContentService.MimeType.JSON);
  }
}

function ingest_(body) {
  var installId = String(body.installId || '').substring(0, 80);
  if (!installId) {
    return { status: 'error', message: 'installId requis' };
  }

  var folder = DriveApp.getFolderById(FOLDER_ID);
  var sheet = ensureSpreadsheet_(folder);
  var snap = body.snapshot || {};
  var boutique = body.boutique || {};
  var events = Array.isArray(body.events) ? body.events : [];
  var now = new Date();
  var receivedAt = now.toISOString();

  upsertBoutique_(sheet, {
    installId: installId,
    businessId: String(body.businessId || boutique.business_id || ''),
    sector: String(body.sector || boutique.secteur || snap.sector || ''),
    appVersion: String(body.appVersion || boutique.app_version || ''),
    salesCount: Number(boutique.ventes != null ? boutique.ventes : snap.salesCount || 0),
    soldFcfa: Number(boutique.ca_fcfa != null ? boutique.ca_fcfa : snap.soldFcfa || 0),
    productsCount: Number(boutique.produits != null ? boutique.produits : snap.productsCount || 0),
    catalogActivatedCount: Number(
      boutique.produits_actives != null
        ? boutique.produits_actives
        : snap.catalogActivatedCount || 0,
    ),
    customersCount: Number(boutique.clients != null ? boutique.clients : snap.customersCount || 0),
    expensesCount: Number(boutique.depenses != null ? boutique.depenses : snap.expensesCount || 0),
    eventCount: Number(boutique.nb_evenements != null ? boutique.nb_evenements : snap.eventCount || 0),
    openDays: Number(boutique.jours_ouverts != null ? boutique.jours_ouverts : snap.openDays || 0),
    lastOpenAt: String(boutique.dernier_ouverture || snap.lastOpenAt || ''),
    receivedAt: receivedAt,
  });

  appendEnvoi_(sheet, {
    receivedAt: receivedAt,
    installId: installId,
    sector: String(body.sector || snap.sector || ''),
    salesCount: Number(snap.salesCount || 0),
    soldFcfa: Number(snap.soldFcfa || 0),
    eventBatch: events.length,
    appVersion: String(body.appVersion || ''),
  });

  var accepted = 0;
  for (var i = 0; i < events.length; i++) {
    var ev = events[i] || {};
    var name = String(ev.name || '');
    var id = String(ev.id || '');
    if (!id || !name) continue;
    appendEvenement_(sheet, {
      receivedAt: receivedAt,
      installId: installId,
      eventId: id,
      eventName: name,
      createdAt: String(ev.createdAt || ''),
      properties: JSON.stringify(ev.properties || {}),
    });
    accepted++;
  }

  writeDump_(folder, installId, body, receivedAt);
  return { status: 'success', accepted: accepted, installId: installId };
}

function ensureSpreadsheet_(folder) {
  var files = folder.getFilesByName(SHEET_NAME);
  var file;
  if (files.hasNext()) {
    file = files.next();
    return SpreadsheetApp.openById(file.getId());
  }
  var ss = SpreadsheetApp.create(SHEET_NAME);
  DriveApp.getFileById(ss.getId()).moveTo(folder);
  setupSheets_(ss);
  return ss;
}

function setupSheets_(ss) {
  var boutiques = ss.getActiveSheet();
  boutiques.setName('Boutiques');
  boutiques
    .getRange(1, 1, 1, 15)
    .setValues([
      [
        'install_id',
        'secteur',
        'business_id',
        'app_version',
        'ventes',
        'ca_fcfa',
        'produits',
        'produits_actives',
        'clients',
        'depenses',
        'jours_ouverts',
        'dernier_ouverture',
        'dernier_envoi',
        'nb_evenements',
        'envois',
      ],
    ])
    .setFontWeight('bold');
  boutiques.setFrozenRows(1);

  var envois = ss.insertSheet('Envois');
  envois
    .getRange(1, 1, 1, 8)
    .setValues([
      [
        'recu_at',
        'install_id',
        'secteur',
        'ventes',
        'ca_fcfa',
        'evenements_lot',
        'app_version',
        'envoi_n',
      ],
    ])
    .setFontWeight('bold');
  envois.setFrozenRows(1);

  var evenements = ss.insertSheet('Evenements');
  evenements
    .getRange(1, 1, 1, 6)
    .setValues([
      [
        'recu_at',
        'install_id',
        'event_id',
        'event_name',
        'created_at',
        'properties_json',
      ],
    ])
    .setFontWeight('bold');
  evenements.setFrozenRows(1);
}

function upsertBoutique_(ss, row) {
  var sheet = ss.getSheetByName('Boutiques');
  var data = sheet.getDataRange().getValues();
  var found = 0;
  for (var i = 1; i < data.length; i++) {
    if (String(data[i][0]) === row.installId) {
      found = i + 1;
      break;
    }
  }
  var values = [
    row.installId,
    row.sector,
    row.businessId,
    row.appVersion,
    row.salesCount,
    row.soldFcfa,
    row.productsCount,
    row.catalogActivatedCount,
    row.customersCount,
    row.expensesCount,
    row.openDays,
    row.lastOpenAt,
    row.receivedAt,
    row.eventCount,
    found ? Number(data[found - 1][14] || 0) + 1 : 1,
  ];
  if (found) {
    sheet.getRange(found, 1, 1, 15).setValues([values]);
  } else {
    sheet.appendRow(values);
  }
}

function appendEnvoi_(ss, row) {
  ss.getSheetByName('Envois').appendRow([
    row.receivedAt,
    row.installId,
    row.sector,
    row.salesCount,
    row.soldFcfa,
    row.eventBatch,
    row.appVersion,
    '',
  ]);
}

function appendEvenement_(ss, row) {
  ss.getSheetByName('Evenements').appendRow([
    row.receivedAt,
    row.installId,
    row.eventId,
    row.eventName,
    row.createdAt,
    row.properties,
  ]);
}

function writeDump_(folder, installId, body, receivedAt) {
  var dumps = ensureSubfolder_(folder, DUMP_FOLDER);
  var name = 'boutique-' + installId.substring(0, 8) + '.json';
  var payload = JSON.stringify(
    {
      recu_at: receivedAt,
      install_id: installId,
      secteur: body.sector || null,
      app_version: body.appVersion || null,
      snapshot: body.snapshot || {},
      evenements: body.events || [],
    },
    null,
    2,
  );
  var existing = dumps.getFilesByName(name);
  if (existing.hasNext()) {
    existing.next().setContent(payload);
  } else {
    dumps.createFile(name, payload, MimeType.PLAIN_TEXT);
  }
}

function ensureSubfolder_(parent, name) {
  var it = parent.getFoldersByName(name);
  if (it.hasNext()) return it.next();
  return parent.createFolder(name);
}
