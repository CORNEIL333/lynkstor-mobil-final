import 'app_strings_en.dart';

/// Chaînes UI centralisées (FR / EN).
class S {
  S._();

  static String currentLanguage = 'fr';

  static bool get isEnglish => currentLanguage == 'en';

  static String tr(String french, String english) =>
      isEnglish ? english : french;

  static String auto(String value) {
    if (!isEnglish) return value;
    return _automaticEnglish[value] ?? value;
  }

  static const Map<String, String> _automaticEnglish = {
    'Accueil': 'Home',
    'Ventes': 'Sales',
    'Stock': 'Stock',
    'Plus': 'More',
    'Assistant': 'Assistant',
    'Lynk': 'Lynk',
    'Généré par IA': 'AI generated',
    'Vendre': 'Sell',
    'Enregistrer': 'Save',
    'Annuler': 'Cancel',
    'Réessayer': 'Retry',
    'Continuer': 'Continue',
    'Valider': 'Confirm',
    'Partager': 'Share',
    'Rechercher': 'Search',
    'Montant': 'Amount',
    'Nom': 'Name',
    'Nom complet': 'Full name',
    'Téléphone': 'Phone',
    'Quartier': 'Neighborhood',
    'Client': 'Customer',
    'Créer': 'Create',
    'Ajouter': 'Add',
    'Arrivée': 'Check in',
    'Départ': 'Check out',
    'Crédit': 'Credit',
    'Dépenses': 'Expenses',
    'Vendu': 'Sold',
    'Encaissé': 'Collected',
    'Encaisser': 'Collect',
    'Copier': 'Copy',
    'Scanner': 'Scan',
    'Inventaire': 'Inventory',
    'Nouvelle vente': 'New sale',
    'Valider la vente': 'Complete sale',
    'Retour au panier': 'Back to cart',
    'Montant reçu': 'Amount received',
    'Référence Mobile Money': 'Mobile Money reference',
    'Retour / annulation': 'Return / cancellation',
    'Valider le retour': 'Confirm return',
    'Motif (obligatoire)': 'Reason (required)',
    'Imprimer / PDF': 'Print / PDF',
    'Partager le reçu': 'Share receipt',
    'Retour à l’accueil': 'Back to home',
    'Prix de vente': 'Sale price',
    'Prix d’achat': 'Cost price',
    'Prix d’achat unitaire': 'Unit cost',
    'Quantité': 'Quantity',
    'Quantité en stock': 'Stock quantity',
    'Quantité reçue': 'Quantity received',
    'Seuil stock faible': 'Low-stock threshold',
    'Unité': 'Unit',
    'Code-barres': 'Barcode',
    'Retirer la photo': 'Remove photo',
    'Description (optionnel)': 'Description (optional)',
    'Adresse / quartier': 'Address / neighborhood',
    'Montant à encaisser': 'Amount to collect',
    'Référence (optionnel)': 'Reference (optional)',
    'Créer le devis': 'Create quote',
    'Réceptionner et mettre en stock': 'Receive and add to stock',
    'Valider et ajuster le stock': 'Confirm and adjust stock',
    'Créer une sauvegarde maintenant': 'Create a backup now',
    'Export transfert téléphone': 'Phone transfer export',
    'Restaurer depuis un fichier': 'Restore from a file',
    'Télécharger le modèle': 'Download model',
    'Supprimer le modèle': 'Delete model',
    'Confidentialité et modèle': 'Privacy and model',
    'Rechercher un client…': 'Search customers…',
    'Rechercher un produit…': 'Search products…',
    'Rechercher ou scanner un code…': 'Search or scan a code…',
    'Nom, code-barres, SKU…': 'Name, barcode, SKU…',
    'Saisie manuelle — pas de push USSD opérateur':
        'Manual entry — no operator USSD push',
    'Mot de passe': 'Password',
    'Nom commercial': 'Business name',
    'Nom du propriétaire': 'Owner name',
    'Ville': 'City',
    'PIN (4 chiffres)': 'PIN (4 digits)',
    'Code donné par le commercial': 'Code provided by the agent',
    'Votre nom': 'Your name',
    'Code d’invitation': 'Invitation code',
    'PIN personnel (4 chiffres)': 'Personal PIN (4 digits)',
    'Rejoindre et ouvrir': 'Join and open',
    'Vérifier': 'Verify',
    'Choisir un fichier .kumba': 'Choose a .kumba file',
    'Vérifier et restaurer': 'Verify and restore',
    'Nouveau PIN (4 chiffres)': 'New PIN (4 digits)',
    'Nom du propriétaire (optionnel)': 'Owner name (optional)',
    'Mot de passe de transfert (et du nouvel appareil)':
        'Transfer password (and new device password)',
  };

  static String notificationTitle(String key, Map<String, dynamic> args) {
    switch (key) {
      case 'stockCriticalTitle':
        return tr('Stock critique', 'Critical stock');
      case 'adHocProductTitle':
        return tr('Produit à configurer', 'Product to configure');
      default:
        return tr('Notification', 'Notification');
    }
  }

  static String notificationBody(String key, Map<String, dynamic> args) {
    final product = '${args['product'] ?? ''}';
    final stock = _number(args['stock']);
    final threshold = _number(args['threshold']);
    final supplier = '${args['supplier'] ?? ''}';
    switch (key) {
      case 'stockCriticalSupplierBody':
        return tr(
          '$product est à $stock (seuil $threshold). Préparer un message pour $supplier.',
          '$product is at $stock (threshold $threshold). Prepare a message for $supplier.',
        );
      case 'stockCriticalNoSupplierBody':
        return tr(
          '$product est à $stock (seuil $threshold). Configurez son fournisseur.',
          '$product is at $stock (threshold $threshold). Configure its supplier.',
        );
      case 'adHocProductBody':
        return tr(
          '$product a été vendu sans fiche stock. Ajoutez-le maintenant au catalogue.',
          '$product was sold without a stock record. Add it to the catalog now.',
        );
      default:
        return key;
    }
  }

  static String _number(Object? value) {
    if (value is num) {
      return value % 1 == 0
          ? value.toInt().toString()
          : value.toStringAsFixed(2);
    }
    return '$value';
  }

  static String get appName =>
      currentLanguage == 'en' ? SEn.appName : 'Lynkstor Business';
  static String get tagline => currentLanguage == 'en'
      ? SEn.tagline
      : 'Votre commerce, dans votre téléphone';

  static String get home => currentLanguage == 'en' ? SEn.home : 'Accueil';
  static String get sales => currentLanguage == 'en' ? SEn.sales : 'Ventes';
  static String get stock => currentLanguage == 'en' ? SEn.stock : 'Stock';
  static String get more => currentLanguage == 'en' ? SEn.more : 'Plus';
  static String get assistant =>
      currentLanguage == 'en' ? 'Assistant' : 'Assistant';
  static String get sell => currentLanguage == 'en' ? SEn.sell : 'Vendre';
  static String get save => currentLanguage == 'en' ? SEn.save : 'Enregistrer';
  static String get cancel => currentLanguage == 'en' ? SEn.cancel : 'Annuler';
  static String get retry => currentLanguage == 'en' ? SEn.retry : 'Réessayer';
  static String get continueLabel =>
      currentLanguage == 'en' ? SEn.continueLabel : 'Continuer';
  static String get validate =>
      currentLanguage == 'en' ? SEn.validate : 'Valider';
  static String get share => currentLanguage == 'en' ? SEn.share : 'Partager';
  static String get search =>
      currentLanguage == 'en' ? SEn.search : 'Rechercher';
  static String get offline => currentLanguage == 'en'
      ? SEn.offline
      : 'Mode hors ligne — vos données restent sur cet appareil';
  static String get permissionDenied =>
      currentLanguage == 'en' ? SEn.permissionDenied : 'Permission refusée';
  static String get moduleDisabled => currentLanguage == 'en'
      ? SEn.moduleDisabled
      : 'Module désactivé pour ce commerce';
  static String get loading =>
      currentLanguage == 'en' ? SEn.loading : 'Chargement…';
  static String get emptySales =>
      currentLanguage == 'en' ? SEn.emptySales : 'Aucune vente pour l’instant';
  static String get emptyProducts =>
      currentLanguage == 'en' ? SEn.emptyProducts : 'Aucun produit';
  static String get emptyCustomers =>
      currentLanguage == 'en' ? SEn.emptyCustomers : 'Aucun client';
  static String get emptyDebts =>
      currentLanguage == 'en' ? SEn.emptyDebts : 'Aucune dette en cours';
  static String get newSale =>
      currentLanguage == 'en' ? SEn.newSale : 'Nouvelle vente';
  static String get checkout =>
      currentLanguage == 'en' ? SEn.checkout : 'Encaisser';
  static String get saleSuccess =>
      currentLanguage == 'en' ? SEn.saleSuccess : 'Vente enregistrée';
  static String get returnSale =>
      currentLanguage == 'en' ? SEn.returnSale : 'Retour / annulation';
  static String get backup =>
      currentLanguage == 'en' ? SEn.backup : 'Sauvegardes';
  static String get restore =>
      currentLanguage == 'en' ? SEn.restore : 'Restaurer';
  static String get lock => currentLanguage == 'en' ? SEn.lock : 'Verrouiller';
  static String get enterPin => currentLanguage == 'en'
      ? SEn.enterPin
      : 'Entrez votre PIN pour continuer';
  static String get wrongPin =>
      currentLanguage == 'en' ? SEn.wrongPin : 'PIN incorrect';
  static String get createBusiness =>
      currentLanguage == 'en' ? SEn.createBusiness : 'Créer mon commerce';
  static String get joinBusiness =>
      currentLanguage == 'en' ? SEn.joinBusiness : 'Rejoindre un commerce';
  static String get restoreData =>
      currentLanguage == 'en' ? SEn.restoreData : 'Restaurer mes données';
  static String get demo =>
      currentLanguage == 'en' ? SEn.demo : 'Découvrir avec une démonstration';
  static String get accessDeniedDetail => currentLanguage == 'en'
      ? SEn.accessDeniedDetail
      : 'Votre rôle ne permet pas d’accéder à cette fonction. Contactez le propriétaire.';
}
