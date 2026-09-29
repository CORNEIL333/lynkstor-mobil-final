const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://wtbmwquovcizrtggkkzn.supabase.co';
// Legacy Supabase (déprécié). Clé non embarquée : fournir SUPABASE_ANON_KEY.
const SUPABASE_KEY = process.env.SUPABASE_ANON_KEY || '';
if (!SUPABASE_KEY) {
  console.error('SUPABASE_ANON_KEY manquant (backend legacy déprécié).');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

async function publishDashboard() {
  console.log('🚀 Publication du Dashboard Web Admin sur Supabase Storage...');

  const bucketName = 'dashboard';

  // 1. Créer le bucket public s'il n'existe pas
  const { data: bucket, error: bErr } = await supabase.storage.createBucket(bucketName, {
    public: true
  });

  if (bErr && !bErr.message.includes('already exists')) {
    console.log('Bucket Info:', bErr.message);
  } else {
    console.log('✅ Bucket Storage public "dashboard" prêt.');
  }

  // 2. Téléverser les fichiers statiques de server/public
  const publicDir = path.join(__dirname, 'public');
  const files = ['index.html', 'styles.css', 'admin.js', 'lynkstor_logo_light.png', 'lynkstor_logo_dark.png'];

  for (const file of files) {
    const filePath = path.join(publicDir, file);
    if (fs.existsSync(filePath)) {
      const fileBuffer = fs.readFileSync(filePath);
      let contentType = 'text/html';
      if (file.endsWith('.css')) contentType = 'text/css';
      if (file.endsWith('.js')) contentType = 'application/javascript';
      if (file.endsWith('.png')) contentType = 'image/png';

      const { data, error } = await supabase.storage
        .from(bucketName)
        .upload(file, fileBuffer, {
          contentType,
          upsert: true
        });

      if (error) {
        console.error(`❌ Erreur téléversement ${file} :`, error.message);
      } else {
        console.log(`✅ Fichier publié sur Supabase Storage : ${file}`);
      }
    }
  }

  const publicUrl = `${SUPABASE_URL}/storage/v1/object/public/${bucketName}/index.html`;
  console.log('\n🎉 ======================================================');
  console.log(`🌐 VOTRE DASHBOARD ADMIN LYNKSTOR EST PUBLIÉ SUR SUPABASE !`);
  console.log(`👉 URL d'accès direct : ${publicUrl}`);
  console.log('======================================================\n');
}

publishDashboard();
