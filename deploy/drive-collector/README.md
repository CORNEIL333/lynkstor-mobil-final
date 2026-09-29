# Collecteur Drive — Lynkstor période test

Dossier cible :
https://drive.google.com/drive/folders/18VAF4ZmazMKQizw_OWl2YEb5oE0wAdEw

## Déploiement (2 minutes, compte Google du dossier)

1. Ouvrir [Google Apps Script](https://script.google.com/home/start)
2. **Nouveau projet** → coller `Code.gs`
3. **Déployer** → **Nouveau déploiement**
   - Type : **Application Web**
   - Exécuter en tant que : **Moi**
   - Qui a accès : **Tout le monde**
4. **Déployer**, copier l’URL `https://script.google.com/macros/s/…/exec`
5. Coller cette URL dans `lib/core/config/app_config.dart` → `analyticsIngestUrl`

Fichiers créés dans le Drive :

| Fichier | Contenu |
|---|---|
| `Lynkstor-panel-test` | Tableur : onglets Boutiques, Envois, Evenements |
| `dumps-json/boutique-xxxxxxxx.json` | Dernier dump JSON de chaque téléphone |
