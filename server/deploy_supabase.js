const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://wtbmwquovcizrtggkkzn.supabase.co';
// Legacy Supabase (déprécié depuis migration Neon). La clé n'est plus
// embarquée dans le dépôt : fournir SUPABASE_ANON_KEY dans l'environnement.
const SUPABASE_KEY = process.env.SUPABASE_ANON_KEY || '';
if (!SUPABASE_KEY) {
  console.error('SUPABASE_ANON_KEY manquant (backend legacy déprécié).');
  process.exit(1);
}

console.log('🚀 Connexion au serveur Supabase Cloud...');
console.log(`🌐 URL : ${SUPABASE_URL}`);

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

async function testConnection() {
  try {
    const { data, error } = await supabase.from('businesses').select('*');
    if (error) {
      console.error('❌ Erreur de lecture Supabase :', error.message);
    } else {
      console.log('✅ Connexion à Supabase réussie !');
      console.log(`📦 Nombre de commerces enregistrés dans le Cloud : ${data ? data.length : 0}`);
      console.log('Données :', data);
    }
  } catch (err) {
    console.error('Exception :', err.message);
  }
}

testConnection();
