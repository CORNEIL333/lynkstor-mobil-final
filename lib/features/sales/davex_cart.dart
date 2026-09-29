import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/davex_tone.dart';
import '../../shared/services/sale_service.dart';

/// Écart maquette documenté : la maquette « Negocier/Négociation » (prix
/// unitaire custom par ligne, badge violet) n'a PAS d'équivalent persisté
/// dans la logique réelle (le total d'une vente est calculé par
/// BillingEngine à partir du prix catalogue). Le point d'extension réel
/// fourni par SaleService est la remise GLOBALE (CompleteSaleInput.discount)
/// → la modale « Application d'une Remise » (5/10/15/20 %) de la maquette
/// est mappée sur ce champ, avec alerte > 15 % comme la maquette.
class DavexRemise {
  const DavexRemise({required this.amount, required this.label});
  final double amount;
  final String label;
}

/// Panier recréé en provider (étape a8b) : c'est CE provider qui alimente le
/// badge Panier du [DavexAppHeader] (le badge était codé à 0 tant que le
/// panier vivait dans le State de l'ancien SaleScreen).
///
/// RÉUTILISE TEL QUEL la classe [CartLine] de SaleService (aucun modèle
/// parallèle : les lignes du panier sont directement les lignes soumises à
/// `completeSale`).
class DavexCartState {
  DavexCartState({
    List<CartLine>? lines,
    this.customer,
    this.customerName,
    this.remise,
    this.lastAdHocSaleId,
  }) : lines = lines ?? <CartLine>[];

  final List<CartLine> lines;
  final Customer? customer;

  /// Nom libre saisi dans le bandeau client (maquette : « Nom direct du
  /// client »). Utilisé comme customerName de la vente ; un crédit exige un
  /// [customer] réel (règle métier SaleService — conservée).
  final String? customerName;
  final DavexRemise? remise;

  /// Sale id de la dernière vente avec ligne libre (relance « Configurer la
  /// fiche » ; le flux adHoc→/products/new de l'écran actuel est conservé).
  final String? lastAdHocSaleId;

  int get itemCount =>
      lines.fold<int>(0, (s, l) => s + l.quantity.round());
  double get subtotal => lines.fold<double>(0, (s, l) => s + l.lineTotal);
  double get discount => remise?.amount ?? 0;
  double get total => (subtotal - discount).clamp(0, double.infinity);
  bool get isEmpty => lines.isEmpty;
  CartLine? lineFor(String? productId) =>
      lines.where((l) => l.productId == productId).firstOrNull;

  /// Libellé du panier façon maquette : nom client direct, sinon client
  /// rattaché, sinon « Panier 1 ».
  String get label {
    final direct = customerName?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final c = customer;
    if (c != null) return c.name;
    return 'Panier 1';
  }

  DavexCartState copyWith({
    List<CartLine>? lines,
    Customer? customer,
    bool clearCustomer = false,
    String? customerName,
    bool clearCustomerName = false,
    DavexRemise? remise,
    bool clearRemise = false,
    String? lastAdHocSaleId,
  }) =>
      DavexCartState(
        lines: lines ?? this.lines,
        customer: clearCustomer ? null : (customer ?? this.customer),
        customerName: clearCustomerName
            ? null
            : (customerName ?? this.customerName),
        remise: clearRemise ? null : (remise ?? this.remise),
        lastAdHocSaleId: clearCustomer
            ? null
            : (lastAdHocSaleId ?? this.lastAdHocSaleId),
      );
}

/// Notifier persistant (non autoDispose) : changer d'onglet ne vide PAS le
/// panier — comportement réel de l'ancien écran, conservé (HIG : ne jamais
/// détruire une saisie en cours sans demande explicite).
class DavexCartNotifier extends StateNotifier<DavexCartState> {
  DavexCartNotifier() : super(DavexCartState());

  /// Ajoute/incrémente. Retour false si la quantité demandée dépasse le
  /// stock disponible (toast à afficher par l'appelant, comme la maquette :
  /// « …en rupture ou la quantité demandée dépasse le stock disponible »).
  bool setQuantity(Product p, int targetQty) {
    if (targetQty < 1) return true;
    if (p.trackStock && !p.isService && targetQty > p.stockQty) return false;
    final current = List<CartLine>.from(state.lines);
    final idx = current.indexWhere((l) => l.productId == p.id);
    if (idx >= 0) {
      current[idx] = CartLine(
        productId: p.id,
        productName: p.name,
        unitPrice: p.salePrice,
        quantity: targetQty.toDouble(),
        unit: p.unit,
        costPrice: p.costPrice,
        trackStock: p.trackStock && !p.isService,
        availableStock: p.stockQty,
      );
    } else {
      current.add(
        CartLine(
          productId: p.id,
          productName: p.name,
          unitPrice: p.salePrice,
          quantity: targetQty.toDouble(),
          unit: p.unit,
          costPrice: p.costPrice,
          trackStock: p.trackStock && !p.isService,
          availableStock: p.stockQty,
        ),
      );
    }
    state = state.copyWith(lines: current);
    return true;
  }

  void addAdHoc({
    required String name,
    required double unitPrice,
    required int quantity,
    required String unit,
  }) {
    final current = List<CartLine>.from(state.lines)
      ..add(
        CartLine(
          productId: null,
          productName: name,
          unitPrice: unitPrice,
          quantity: quantity.toDouble(),
          unit: unit,
          trackStock: false,
        ),
      );
    state = state.copyWith(lines: current);
  }

  /// −1 sous 1 supprime la ligne (maquette : updateQty).
  void changeQuantity(String? productId, int delta) {
    final idx = state.lines.indexWhere((l) => l.productId == productId);
    if (idx < 0) return;
    changeQuantityAt(idx, delta);
  }

  /// Variation par index : indispensable pour les lignes hors catalogue
  /// (productId == null — plusieurs lignes libres ne doivent pas se confondre).
  void changeQuantityAt(int index, int delta) {
    if (index < 0 || index >= state.lines.length) return;
    final l = state.lines[index];
    final newQty = l.quantity + delta;
    if (newQty < 1) {
      removeAt(index);
      return;
    }
    final current = List<CartLine>.from(state.lines);
    current[index] = CartLine(
      productId: l.productId,
      productName: l.productName,
      unitPrice: l.unitPrice,
      quantity: newQty,
      unit: l.unit,
      costPrice: l.costPrice,
      discount: l.discount,
      trackStock: l.trackStock,
      availableStock: l.availableStock,
    );
    state = state.copyWith(lines: current);
  }

  /// Remplace la quantité d'une ligne par index (produit requis pour le
  /// contrôle de stock ; les lignes libres passent directement par ici).
  bool setQuantityAt(int index, Product? p, int targetQty) {
    if (index < 0 || index >= state.lines.length) return true;
    if (targetQty < 1) {
      removeAt(index);
      return true;
    }
    if (p != null && p.trackStock && !p.isService && targetQty > p.stockQty) {
      return false;
    }
    final l = state.lines[index];
    final current = List<CartLine>.from(state.lines);
    current[index] = CartLine(
      productId: l.productId,
      productName: l.productName,
      unitPrice: l.unitPrice,
      quantity: targetQty.toDouble(),
      unit: l.unit,
      costPrice: l.costPrice,
      discount: l.discount,
      trackStock: l.trackStock,
      availableStock: l.availableStock,
    );
    state = state.copyWith(lines: current);
    return true;
  }

  void removeAt(int index) {
    final current = List<CartLine>.from(state.lines)..removeAt(index);
    state = state.copyWith(lines: current);
  }

  /// « Vider » (maquette) : vide les lignes et la remise, garde le client.
  void clearCart() => state = state.copyWith(
    lines: <CartLine>[],
    clearRemise: true,
  );

  /// Après encaissement réussi : on repart d'un panier neuf, client inclus.
  void reset({String? adHocSaleId}) => state = DavexCartState(
    lastAdHocSaleId: adHocSaleId,
  );

  void attachCustomer(Customer? c, {String? name}) => state = state.copyWith(
    customer: c,
    clearCustomer: c == null,
    customerName: name,
    clearCustomerName: c == null && name == null,
  );

  void setRemise(DavexRemise? r) =>
      state = state.copyWith(remise: r, clearRemise: r == null);

  /// Contrôle avant paiement : ligne dont la quantité dépasse le stock
  /// (le stock a pu bouger depuis l'ajout — jamais de faux succès).
  String? stockError(List<Product> products) {
    for (final l in state.lines) {
      final id = l.productId;
      if (id == null || !l.trackStock) continue;
      final p = products.where((x) => x.id == id).firstOrNull;
      if (p != null && p.trackStock && l.quantity > p.stockQty) {
        return '${l.productName} : stock réduit à ${_fmt(p.stockQty)} '
            '— retirez ou ajustez la ligne.';
      }
    }
    return null;
  }

  static String _fmt(double v) =>
      MoneyFormat.format(v, showCurrency: false);
}

final davexCartProvider =
    StateNotifierProvider<DavexCartNotifier, DavexCartState>(
  (ref) => DavexCartNotifier(),
);

/// Badge Panier du header DAVEX (a8b) — nombre d'articles en caisse.
final davexCartBadgeProvider = Provider<int>(
  (ref) => ref.watch(davexCartProvider.select((s) => s.itemCount)),
);

/// Teinte du bandeau client du panier (rattache la palette au domaine).
DavexTone davexCartCustomerTone(bool hasCustomer) =>
    hasCustomer ? DavexTone.info : DavexTone.neutral;
