import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/permissions/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/davex_button.dart';
import '../../design_system/components/davex_icon_button.dart';
import '../../design_system/components/davex_pressable.dart';
import '../../design_system/components/davex_quantity_selector.dart';
import '../../design_system/components/davex_search_field.dart';
import '../../design_system/components/davex_sheet.dart';
import '../../design_system/components/davex_states.dart';
import '../../design_system/components/davex_status_badge.dart';
import '../../design_system/components/davex_tone.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';
import '../products/barcode_scanner_screen.dart';
import 'davex_cart.dart';
import '../../shared/services/customer_service.dart';
import '../../shared/services/product_service.dart';
import '../../shared/services/sale_service.dart';

// ─── Écran Vente recréé depuis la maquette (VenteScreen, App.tsx L963–2865) ──
//
// Décision d'audit (processus senior, zéro fusion silencieuse) :
// RECRÉER. L'ancien `sale_screen.dart` (SaleScreen) n'est PAS patché :
// il reste sur disque (fixtures de tests) mais est déréférencé du router au
// profit de cet écran. Toute la LOGIQUE est réutilisée telle quelle :
// SaleService.completeSale (paiements cash/momo/transfer/crédit/mixte,
// remise globale, garde-fou crédit→client obligatoire, équilibrage
// BillingEngine), ProductService.byBarcode, CustomerService.create,
// receipt `/sale/receipt/:id`, relance fiche adHoc `/products/new`.
//
// Mapping maquette → unité par unité :
// - barre recherche + bouton scan bleu (#0050FF) → vue catalogue ;
// - tuiles produits 2 col. (pastille quantité, badge stock, prix bleu,
//   « Ajouter ») + carte pointillée « Produit hors catalogue » ;
// - fullscreen panier : bandeau client, lignes (− qty +, total ligne),
//   barre basse (Remise / Total net / Encaisser) ;
// - Encaissement : carte dégradée bleue + 4 tuiles modes de paiement + CTA
//   vert « Encaisser X FCFA » ;
// - Vente à crédit : vue dédiée client existant/nouveau, solde « X F dû » ;
// - succès plein écran 1,8 s avant ticket ;
// - modales : première vente prix brouillon, pick produit, remise %,
//   hors catalogue, rattachement client.
//
// Écarts maquette↔logique RÉELLE documentés (liste lacunes §12 doc audit) :
// - multi-paniers « 2e client » : non implémenté (SaleService = une vente à
//   la fois) — écart listé, jamais simulé ;
// - fidélité/points/coupons, devis/proforma, négociation prix unitaire :
//   aucun modèle persisté côté Drift — non fabriqués ; la remise % de la
//   maquette est mappée sur CompleteSaleInput.discount (réel) ;
// - « Mobile Money » maquette = momo projet avec référence saisie manuelle
//   (pas de push USSD — garde-fou existant conservé, note affichée) ;
// - scan : caméra réelle (BarcodeScannerScreen) au lieu du simulateur.

/// Bleu « action » pixel de la maquette Vente (`bg-blue-600` = #0050FF des
/// CTES caisse). Rôle sémantique projet le plus proche : info #1D6BFF —
/// écart ≤ 1 nuance accepté hors charte LkPalette (couleur codée locale).
const Color _posBlue = Color(0xFF0050FF);
const Color _posBlueDeep = Color(0xFF0040CC);
const LinearGradient _posBlueGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_posBlue, _posBlueDeep],
);

enum _VenteView { catalogue, panier, encaissement, credit, succes }

// ─── Données réelles ─────────────────────────────────────────────────────────

class _VenteCatalogue {
  const _VenteCatalogue({required this.products, required this.categoryNames});
  final List<Product> products;
  final Map<String, String> categoryNames;
}

/// Produits actifs + libellés de catégories (badge « Stock : n · catégorie »
/// de la maquette). autoDispose : rechargé à chaque retour sur l'onglet, ce
/// qui rafraîchit les stocks après chaque vente (pas de faux stock en vue).
final _venteCatalogueProvider =
    FutureProvider.autoDispose<_VenteCatalogue?>((ref) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return null;
  final products = await ref.watch(productServiceProvider).list(business.id);
  final cats = await ref.watch(productServiceProvider).categories(business.id);
  return _VenteCatalogue(
    products: products.where((p) => p.isActive).toList(),
    categoryNames: {for (final c in cats) c.id: c.name},
  );
});

final _venteCustomersProvider = FutureProvider.autoDispose<List<Customer>>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return const [];
  return ref.watch(customerServiceProvider).list(business.id);
});

// ─── Écran ───────────────────────────────────────────────────────────────────

class DavexVenteScreen extends ConsumerStatefulWidget {
  const DavexVenteScreen({super.key, this.embedded = false});

  /// true : affiché dans le shell DAVEX (onglet Vente) — pas de chrome propre.
  final bool embedded;

  @override
  ConsumerState<DavexVenteScreen> createState() => _DavexVenteScreenState();
}

class _DavexVenteScreenState extends ConsumerState<DavexVenteScreen> {
  _VenteView _view = _VenteView.catalogue;
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Encaissement (logique réelle conservée : montant reçu + référence momo).
  String _payMethod = 'cash';
  final _payAmountCtrl = TextEditingController();
  final _momoRefCtrl = TextEditingController();
  bool _submitting = false;
  String? _payError;

  // Crédit (maquette : vue dédiée, segment existant/nouveau).
  bool _newDebtor = false;
  final _newDebtorNameCtrl = TextEditingController();
  final _newDebtorPhoneCtrl = TextEditingController();

  // Contrôleurs des modales : créés au niveau State et NON jetés à la
  // fermeture du sheet — la future de showModalBottomSheet se résout dès
  // le pop() alors que l'animation de sortie reconstruit encore les
  // TextField (TextEditor disposed → crash en test comme en production).
  final _adhocNameCtrl = TextEditingController();
  final _adhocPriceCtrl = TextEditingController();
  final _adhocQtyCtrl = TextEditingController(text: '1');
  final _adhocUnitCtrl = TextEditingController();
  final _firstPriceCtrl = TextEditingController();
  final _remiseCustomCtrl = TextEditingController();

  // Succès : total figé pour l'affichage plein écran (1,8 s puis ticket).
  double _successTotal = 0;
  String _successCartLabel = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _payAmountCtrl.dispose();
    _momoRefCtrl.dispose();
    _newDebtorNameCtrl.dispose();
    _newDebtorPhoneCtrl.dispose();
    _adhocNameCtrl.dispose();
    _adhocPriceCtrl.dispose();
    _adhocQtyCtrl.dispose();
    _adhocUnitCtrl.dispose();
    _firstPriceCtrl.dispose();
    _remiseCustomCtrl.dispose();
    super.dispose();
  }

  DavexCartState get _cart => ref.read(davexCartProvider);
  DavexCartNotifier get _notifier => ref.read(davexCartProvider.notifier);

  // Accesseurs utilisés par les vues enfants (même fichier) : évitent
  // d'appeler setState/@protected depuis une autre classe.
  void _setView(_VenteView v) => setState(() => _view = v);
  void _setQuery(String v) => setState(() => _query = v);
  void _setPayMethod(String m) => setState(() => _payMethod = m);
  void _setNewDebtor(bool v) => setState(() => _newDebtor = v);

  List<Product> get _allProducts =>
      ref.read(_venteCatalogueProvider).valueOrNull?.products ?? const [];

  List<Product> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      final fav = _allProducts.where((p) => p.isFavorite).toList();
      return fav.isEmpty ? _allProducts : [...fav, ..._allProducts.where((p) => !p.isFavorite)];
    }
    return _allProducts
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              (p.sku?.toLowerCase().contains(q) ?? false) ||
              (p.barcode?.contains(_query.trim()) ?? false),
        )
        .toList();
  }

  // ─── Interactions catalogue ────────────────────────────────────────────────

  void _toast(String msg, {LkToastTone tone = LkToastTone.neutral, IconData? icon}) {
    if (!mounted) return;
    showLkToast(context, msg, tone: tone, icon: icon);
  }

  void _addProduct(Product p, {int? targetQty}) {
    final current = _cart.lineFor(p.id)?.quantity.round() ?? 0;
    final qty = targetQty ?? current + 1;
    if (qty < 1) return;
    if (!_notifier.setQuantity(p, qty)) {
      _toast(
        S.tr(
          '${p.name} est en rupture ou la quantité demandée dépasse le stock disponible.',
          '${p.name} is out of stock or the requested quantity exceeds available stock.',
        ),
        tone: LkToastTone.warning,
        icon: Icons.inventory_2_outlined,
      );
      return;
    }
    HapticFeedback.selectionClick();
  }

  Future<void> _openPicker(Product p) async {
    var qty = (_cart.lineFor(p.id)?.quantity.round() ?? 0).clamp(1, 9999);
    await showDavexSheet<void>(
      context,
      title: S.tr('Ajouter au panier', 'Add to cart'),
      initialChildSize: 0.5,
      builder: (sheetContext, _) => _PickerBody(
        product: p,
        quantity: qty,
        onQuantityChanged: (v) => qty = v,
      ),
    );
    if (!mounted) return;
    _addProduct(p, targetQty: qty);
  }

  /// Fiche maquette : prix ≤ 0 = brouillon interne → modale « premier prix ».
  Future<void> _tapProduct(Product p) async {
    if (p.salePrice <= 0) {
      await _firstSalePrice(p);
      return;
    }
    await _openPicker(p);
  }

  Future<void> _firstSalePrice(Product p) async {
    _firstPriceCtrl.clear();
    double? result;
    await showDavexSheet<void>(
      context,
      title: S.tr(
        'Prix de première vente',
        'First-sale price',
      ),
      initialChildSize: 0.5,
      builder: (sheetContext, _) => _FirstSalePriceBody(
        product: p,
        controller: _firstPriceCtrl,
        onValid: (v) => result = v,
      ),
    );
    final price = result;
    if (!mounted || price == null) return;
    final business = ref.read(sessionProvider).business;
    if (business == null) return;
    try {
      await ref.read(productServiceProvider).update(
        p,
        ProductInput(
          name: p.name,
          salePrice: price,
          costPrice: p.costPrice,
          unit: p.unit,
          categoryId: p.categoryId,
          barcode: p.barcode,
          sku: p.sku,
          stockQty: p.stockQty,
          lowStockThreshold: p.lowStockThreshold,
          trackStock: p.trackStock,
          isService: p.isService,
          description: p.description,
          photoPath: p.photoPath,
        ),
        userId: ref.read(sessionProvider).user?.id,
      );
      ref.invalidate(_venteCatalogueProvider);
    } on AppException catch (e) {
      _toast(e.message, tone: LkToastTone.danger);
    }
  }

  Future<void> _addAdHoc() async {
    _adhocNameCtrl.text = _query.trim();
    _adhocPriceCtrl.clear();
    _adhocQtyCtrl.text = '1';
    _adhocUnitCtrl.text = S.tr('pièce', 'piece');
    String? name;
    double? price;
    int? qty;
    String? unit;
    await showDavexSheet<void>(
      context,
      title: S.tr('Produit hors catalogue', 'Uncatalogued product'),
      initialChildSize: 0.6,
      builder: (sheetContext, _) => _AdHocBody(
        nameCtrl: _adhocNameCtrl,
        priceCtrl: _adhocPriceCtrl,
        qtyCtrl: _adhocQtyCtrl,
        unitCtrl: _adhocUnitCtrl,
        onConfirm: (n, p, q, u) {
          name = n;
          price = p;
          qty = q;
          unit = u;
        },
      ),
    );
    if (name == null || price == null || qty == null || !mounted) return;
    _notifier.addAdHoc(
      name: name!,
      unitPrice: price!,
      quantity: qty!,
      unit: unit ?? S.tr('pièce', 'piece'),
    );
    _searchCtrl.clear();
    setState(() => _query = '');
    HapticFeedback.selectionClick();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    final business = ref.read(sessionProvider).business;
    if (code == null || business == null || !mounted) return;
    final byCode = await ref
        .read(productServiceProvider)
        .byBarcode(business.id, code);
    if (!mounted) return;
    if (byCode != null) {
      _addProduct(byCode);
      _toast(
        S.tr('${byCode.name} ajouté au panier', '${byCode.name} added to cart'),
        tone: LkToastTone.success,
        icon: Icons.add_shopping_cart_rounded,
      );
    } else {
      // Maquette : code inconnu → saisie hors catalogue.
      _toast(
        S.tr(
          'Aucun produit pour le code $code — complétez une fiche ou vendez-le hors catalogue.',
          'No product for code $code — complete a record or sell it uncatalogued.',
        ),
        tone: LkToastTone.warning,
        icon: Icons.barcode_reader,
      );
      _addAdHoc();
    }
  }

  // ─── Encaissement / crédit (logique réelle conservée) ──────────────────────

  void _openPayment() {
    final err = _notifier.stockError(_allProducts);
    if (err != null) {
      _toast(err, tone: LkToastTone.warning, icon: Icons.inventory_2_outlined);
      return;
    }
    _payAmountCtrl.text = _cart.total.toStringAsFixed(0);
    setState(() {
      _view = _VenteView.encaissement;
      _payError = null;
    });
  }

  Future<void> _complete({bool viaCredit = false}) async {
    final session = ref.read(sessionProvider);
    final business = session.business;
    if (business == null) return;
    if (!session.canSell) {
      final sub = session.subscription;
      setState(() {
        _payError =
            'Abonnement ${sub.statusLabel.toLowerCase()} (forfait ${sub.planName}). '
            'Contactez votre agent commercial Lynkstor pour renouveler.';
      });
      HapticFeedback.heavyImpact();
      return;
    }

    final method = viaCredit ? 'credit' : _payMethod;
    final cart = _cart;
    final total = cart.total;

    // Crédit → client réel obligatoire (rèelle SaleService ; jamais simulé).
    Customer? customer = cart.customer;
    if (method == 'credit' || method == 'mixed') {
      if (customer == null) {
        setState(() {
          if (!viaCredit) _view = _VenteView.credit;
          _payError = method == 'credit'
              ? S.tr(
                  'Sélectionnez un client pour une vente à crédit.',
                  'Select a customer for a credit sale.',
                )
              : null;
        });
        return;
      }
    }

    final paid = MoneyFormat.parse(_payAmountCtrl.text) ?? total;
    List<PaymentPart> payments;
    if (method == 'credit') {
      payments = [PaymentPart(method: 'credit', amount: 0)];
    } else if (method == 'mixed') {
      payments = [
        PaymentPart(method: 'cash', amount: paid),
        if (paid < total) PaymentPart(method: 'credit', amount: 0),
      ];
    } else {
      payments = [
        PaymentPart(
          method: method,
          amount: paid,
          methodRef: _momoRefCtrl.text.isEmpty ? null : _momoRefCtrl.text,
        ),
      ];
    }

    setState(() {
      _submitting = true;
      _payError = null;
    });

    try {
      final hasAdHoc = cart.lines.any((l) => l.productId == null);
      final sale = await ref
          .read(saleServiceProvider)
          .completeSale(
            CompleteSaleInput(
              businessId: business.id,
              lines: List.of(cart.lines),
              payments: payments,
              customerId: customer?.id,
              customerName: customer?.name ?? cart.customerName,
              discount: cart.discount,
              userId: session.user?.id,
              userRole: session.role,
            ),
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _notifier.reset(adHocSaleId: hasAdHoc ? sale.id : null);
      setState(() {
        _successTotal = sale.total;
        _successCartLabel = cart.label;
        _view = _VenteView.succes;
        _submitting = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
      final adHocSaleId = ref.read(davexCartProvider).lastAdHocSaleId;
      if (adHocSaleId != null &&
          session.can(AppPermission.productsManage) &&
          session.can(AppPermission.customersManage)) {
        // Maquette « Initialiser le stock maintenant ? » → fiche réelle.
        final configure = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(S.tr('Compléter la fiche ?', 'Complete the record?')),
            content: Text(
              S.tr(
                'L\'article libre a été vendu. Ajoutez maintenant son stock, '
                'sa photo et son fournisseur pour le publier au catalogue.',
                'The free item was sold. Add its stock, photo and supplier '
                'now to publish it in the catalog.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(S.tr('Plus tard', 'Later')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(S.tr('Configurer', 'Configure')),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (configure == true) {
          final uri = Uri(
            path: '/products/new',
            queryParameters: {'saleId': adHocSaleId},
          );
          context.pushReplacement(uri.toString());
          return;
        }
      }
      context.pushReplacement('/sale/receipt/${sale.id}');
    } on AppException catch (e) {
      setState(() {
        _payError = e.message;
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _payError = e.toString();
        _submitting = false;
      });
    }
  }

  Future<void> _createAndSellCredit() async {
    final name = _newDebtorNameCtrl.text.trim();
    if (name.isEmpty) return;
    final business = ref.read(sessionProvider).business;
    if (business == null) return;
    setState(() => _submitting = true);
    try {
      final customer = await ref.read(customerServiceProvider).create(
        business.id,
        CustomerInput(name: name, phone: _newDebtorPhoneCtrl.text.trim()),
        userId: ref.read(sessionProvider).user?.id,
        userRole: ref.read(sessionProvider).role,
      );
      if (!mounted) return;
      _notifier.attachCustomer(customer);
      await _complete(viaCredit: true);
    } on AppException catch (e) {
      setState(() {
        _payError = e.message;
        _submitting = false;
      });
    }
  }

  // ─── Modales davex ─────────────────────────────────────────────────────────

  Future<void> _openRemise() async {
    final subtotal = _cart.subtotal;
    var pct = 0;
    _remiseCustomCtrl.clear();
    await showDavexSheet<void>(
      context,
      title: S.tr("Application d'une Remise", 'Apply a discount'),
      initialChildSize: 0.5,
      builder: (sheetContext, _) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final amount = pct == 0
              ? (MoneyFormat.parse(_remiseCustomCtrl.text) ?? 0)
              : (subtotal * pct / 100).roundToDouble();
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  S.tr(
                    'Panier : ${MoneyFormat.format(subtotal)}',
                    'Cart: ${MoneyFormat.format(subtotal)}',
                  ),
                  style: TextStyle(
                    color: LkPalette.of(context).info,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final p in const [5, 10, 15, 20]) ...[
                      Expanded(
                        child: _RemiseChip(
                          pct: p,
                          selected: pct == p,
                          onTap: () => setSheetState(
                            () => pct = pct == p ? 0 : p,
                          ),
                        ),
                      ),
                      if (p != 20) const SizedBox(width: 8),
                    ],
                  ],
                ),
                if (pct > 15) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: LkPalette.of(context).warningBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: LkPalette.of(context).warning.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: LkPalette.of(context).warningFg,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            S.tr(
                              'Remise > 15 % — accord du gérant recommandé.',
                              'Discount > 15% — manager approval recommended.',
                            ),
                            style: TextStyle(
                              color: LkPalette.of(context).warningFg,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: _remiseCustomCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setSheetState(() => pct = 0),
                  decoration: InputDecoration(
                    labelText: S.tr(
                      'Remise libre (FCFA)',
                      'Custom discount (FCFA)',
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: LkPalette.of(context).infoBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        S.tr('Montant de la remise', 'Discount amount'),
                        style: TextStyle(
                          color: LkPalette.of(context).text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '- ${MoneyFormat.format(amount)}',
                        style: const TextStyle(
                          color: _posBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                DavexButton(
                  label: S.tr('Appliquer cette remise', 'Apply this discount'),
                  expand: true,
                  onPressed: () {
                    _notifier.setRemise(
                      amount <= 0
                          ? null
                          : DavexRemise(
                              amount: amount.clamp(0, subtotal),
                              label: pct > 0
                                  ? '- $pct %'
                                  : S.tr('Remise', 'Discount'),
                            ),
                    );
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openClientSheet() async {
    final customers = ref.read(_venteCustomersProvider).valueOrNull ?? const [];
    await showDavexSheet<void>(
      context,
      title: S.tr('Rattacher un client', 'Attach a customer'),
      initialChildSize: 0.65,
      builder: (sheetContext, controller) => _CustomerSheetBody(
        controller: controller,
        customers: customers,
        current: _cart.customer,
        onPick: (c) {
          _notifier.attachCustomer(c, name: c?.name);
          Navigator.pop(sheetContext);
        },
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final asyncCatalogue = ref.watch(_venteCatalogueProvider);
    final p = LkPalette.of(context);

    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : p.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        top: !widget.embedded,
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          child: switch (_view) {
            _VenteView.catalogue => _CatalogueView(
              key: const ValueKey('cat'),
              state: this,
              asyncCatalogue: asyncCatalogue,
            ),
            _VenteView.panier => _PanierView(key: const ValueKey('cart'), state: this),
            _VenteView.encaissement =>
              _EncaissementView(key: const ValueKey('pay'), state: this),
            _VenteView.credit => _CreditView(key: const ValueKey('credit'), state: this),
            _VenteView.succes => _SuccesView(key: const ValueKey('ok'), state: this),
          },
        ),
      ),
    );
  }
}

// ─── Vues plein écran ────────────────────────────────────────────────────────

class _CatalogueView extends ConsumerWidget {
  const _CatalogueView({
    super.key,
    required this.state,
    required this.asyncCatalogue,
  });

  final _DavexVenteScreenState state;
  final AsyncValue<_VenteCatalogue?> asyncCatalogue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LkPalette.of(context);
    final cart = ref.watch(davexCartProvider);

    return Column(
      children: [
        // lk-sale-top : recherche + scan (maquette L1828–1893).
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(bottom: BorderSide(color: p.borderDecorative)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: DavexSearchField(
                  controller: state._searchCtrl,
                  hintText: S.tr(
                    'Rechercher un produit…',
                    'Search a product…',
                  ),
                  onChanged: state._setQuery,
                  onSubmitted: (v) async {
                    final business = ref.read(sessionProvider).business;
                    if (business == null) return;
                    final byCode = await ref
                        .read(productServiceProvider)
                        .byBarcode(business.id, v.trim());
                    if (byCode != null) {
                      state._addProduct(byCode);
                      state._searchCtrl.clear();
                      state._setQuery('');
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Bouton scan bleu #0050FF de la maquette.
              DavexPressable(
                onTap: state._scan,
                semanticLabel: S.tr('Scanner', 'Scan'),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _posBlue,
                    borderRadius: BorderRadius.circular(
                      LkColors.radiusMedium,
                    ),
                  ),
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: asyncCatalogue.when(
            loading: () => const DavexLoading(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: DavexStateView(
                title: S.tr('Catalogue indisponible', 'Catalog unavailable'),
                message: S.tr(
                  'Impossible de charger les produits. Réessayez.',
                  'Could not load products. Try again.',
                ),
                icon: Icons.error_outline,
                actionLabel: S.tr('Réessayer', 'Retry'),
                onAction: () => ref.invalidate(_venteCatalogueProvider),
              ),
            ),
            data: (catalogue) {
              if (catalogue == null) {
                return DavexStateView(
                  title: S.tr('Aucun commerce', 'No business'),
                  message: S.tr(
                    'Créez ou rejoignez un commerce pour ouvrir la caisse.',
                    'Create or join a business to open the register.',
                  ),
                  icon: Icons.storefront_outlined,
                );
              }
              final products = state._filtered;
              return ColoredBox(
                color: p.canvas,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          state._query.trim().isEmpty
                              ? S.tr(
                                  'Produits pour ${cart.label}',
                                  'Products for ${cart.label}',
                                )
                              : S.tr(
                                  'Résultats (${products.length})',
                                  'Results (${products.length})',
                                ),
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // Carte pointillée « Produit hors catalogue ».
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _HorsCatalogueCard(onTap: state._addAdHoc),
                          ),
                          if (products.isEmpty)
                            DavexStateView(
                              title: S.tr(
                                'Aucun produit',
                                'No products',
                              ),
                              message: S.tr(
                                'Vendez un article hors catalogue ou activez '
                                'des produits de votre secteur.',
                                'Sell an uncatalogued item or activate '
                                'products from your sector.',
                              ),
                              icon: Icons.search_off,
                            )
                          else
                            _ProductsGrid(state: state, products: products),
                        ]),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // Barre basse « VOIR LE PANIER » (maquette L2023–2039).
        if (!cart.isEmpty) _VoirPanierBar(state: state),
      ],
    );
  }
}

class _ProductsGrid extends StatelessWidget {
  const _ProductsGrid({required this.state, required this.products});

  final _DavexVenteScreenState state;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: products.length,
      itemBuilder: (context, i) =>
          _ProductCard(state: state, product: products[i]),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.state, required this.product});

  final _DavexVenteScreenState state;
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LkPalette.of(context);
    final cart = ref.watch(davexCartProvider);
    final line = cart.lineFor(product.id);
    final inCart = line != null;
    final low =
        product.trackStock &&
        !product.isService &&
        product.stockQty <= product.lowStockThreshold;
    final categoryName = ref
        .watch(_venteCatalogueProvider)
        .valueOrNull
        ?.categoryNames[product.categoryId];

    return DavexPressable(
      // Écart maquette documenté : le stepper direct « Express » du cartiau
      // est remplacé par le sélecteur (popup maquette) — le provider panier
      // reconstruirait la carte sous le doigt pendant un +/- rapide.
      onTap: () => state._tapProduct(product),
      semanticLabel: product.name,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(LkColors.radiusLarge),
          border: Border.all(
            color: inCart ? _posBlue : p.borderDecorative,
          ),
          boxShadow: [p.shadowCard],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _posBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        product.name.isNotEmpty
                            ? product.name.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: _posBlue,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (product.isFavorite) ...[
                      const Spacer(),
                      Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: LkColors.accent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (product.sku != null || product.barcode != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      product.sku ?? product.barcode!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _posBlue,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                if (product.salePrice <= 0)
                  Text(
                    S.tr(
                      'Prix à saisir à la première vente',
                      'Set a price at first sale',
                    ),
                    style: TextStyle(
                      color: p.warningFg,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    MoneyFormat.format(product.salePrice),
                    style: const TextStyle(
                      color: _posBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (product.isService)
                      DavexStatusBadge.text(
                        S.tr('Service', 'Service'),
                        tone: DavexTone.info,
                      )
                    else if (low)
                      DavexStatusBadge.text(
                        S.tr('Stock faible', 'Low stock'),
                        tone: DavexTone.warning,
                      )
                    else
                      DavexStatusBadge.text(
                        S.tr('En stock', 'In stock'),
                        tone: DavexTone.success,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  product.isService
                      ? S.tr('Sans stock', 'No stock')
                      : (categoryName == null
                            ? 'Stock : ${MoneyFormat.format(product.stockQty, showCurrency: false)}'
                            : 'Stock : ${MoneyFormat.format(product.stockQty, showCurrency: false)} · $categoryName'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textSecondary, fontSize: 10),
                ),
                const SizedBox(height: 8),
                DavexButton(
                  label: S.tr('Ajouter', 'Add'),
                  icon: Icons.add_shopping_cart_rounded,
                  expand: true,
                  onPressed: () => state._tapProduct(product),
                ),
              ],
            ),
            if (inCart)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: _posBlue,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${line.quantity.round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// (extension fantôme supprimée)

class _HorsCatalogueCard extends StatelessWidget {
  const _HorsCatalogueCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return DavexPressable(
      onTap: onTap,
      semanticLabel: S.tr('Produit hors catalogue', 'Uncatalogued product'),
      child: CustomPaint(
        painter: _DashedBorder(color: p.borderControl),
        child: Container(
          height: 76,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, color: _posBlue, size: 22),
              const SizedBox(width: 8),
              Text(
                S.tr(
                  'Produit hors catalogue',
                  'Uncatalogued product',
                ),
                style: const TextStyle(
                  color: _posBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          const Radius.circular(LkColors.radiusLarge),
        ),
      );
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

class _VoirPanierBar extends ConsumerWidget {
  const _VoirPanierBar({required this.state});

  final _DavexVenteScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(davexCartProvider);
    return Container(
      decoration: BoxDecoration(
        color: LkPalette.of(context).surface,
        border: Border(
          top: BorderSide(color: LkPalette.of(context).borderDecorative),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: DavexPressable(
        onTap: () {
          HapticFeedback.mediumImpact();
          state._setView(_VenteView.panier);
        },
        semanticLabel: S.tr('Voir le panier', 'View cart'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(
            gradient: _posBlueGradient,
            borderRadius: BorderRadius.circular(LkColors.radiusXl),
            boxShadow: [
              BoxShadow(
                color: _posBlue.withValues(alpha: 0.30),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_cart_outlined,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.tr('VOIR LE PANIER', 'VIEW CART'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(
                      S.tr(
                        '${cart.itemCount} article${cart.itemCount > 1 ? 's' : ''} · ${cart.label}',
                        '${cart.itemCount} item(s) · ${cart.label}',
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                MoneyFormat.format(cart.total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanierView extends ConsumerWidget {
  const _PanierView({super.key, required this.state});

  final _DavexVenteScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LkPalette.of(context);
    final cart = ref.watch(davexCartProvider);

    return ColoredBox(
      color: p.canvas,
      child: Column(
        children: [
          // Header blanc + bandeau client (maquette L1393–1584).
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(bottom: BorderSide(color: p.borderDecorative)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    DavexIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: S.tr('Retour à la caisse', 'Back to register'),
                      onPressed: () =>
                          state._setView(_VenteView.catalogue),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              cart.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DavexStatusBadge.text(
                            S.tr(
                              '${cart.itemCount} article${cart.itemCount > 1 ? 's' : ''}',
                              '${cart.itemCount} item(s)',
                            ),
                            tone: DavexTone.info,
                          ),
                        ],
                      ),
                    ),
                    if (!cart.isEmpty)
                      TextButton.icon(
                        onPressed: () {
                          state._notifier.clearCart();
                          HapticFeedback.lightImpact();
                        },
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 18, color: p.danger),
                        label: Text(
                          S.tr('Vider', 'Clear'),
                          style: TextStyle(color: p.danger, fontSize: 13),
                        ),
                      ),
                    DavexIconButton(
                      icon: Icons.close_rounded,
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonLabel,
                      onPressed: () => state._setView(
                        _VenteView.catalogue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _BandeauClient(state: state),
              ],
            ),
          ),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: p.surfaceMuted,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(
                              Icons.shopping_cart_outlined,
                              size: 30,
                              color: p.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            S.tr('Ce panier est vide', 'This cart is empty'),
                            style: TextStyle(
                              color: p.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            S.tr(
                              'Sélectionnez des produits dans le catalogue pour composer la vente.',
                              'Pick products from the catalog to compose the sale.',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          DavexButton(
                            label: S.tr(
                              'Retour au Catalogue',
                              'Back to catalog',
                            ),
                            variant: DavexButtonVariant.secondary,
                            onPressed: () => state._setView(
                              _VenteView.catalogue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        _CartLineTile(state: state, index: i),
                  ),
          ),
          if (!cart.isEmpty) _PanierBottomBar(state: state),
        ],
      ),
    );
  }
}

class _BandeauClient extends ConsumerWidget {
  const _BandeauClient({required this.state});

  final _DavexVenteScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(davexCartProvider);
    final attached = cart.customer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF101A2E), Color(0xFF1D2B45)],
        ),
        borderRadius: BorderRadius.circular(LkColors.radiusLarge),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            alignment: Alignment.center,
            child: attached != null
                ? Text(
                    attached.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : const Icon(
                    Icons.person_outline_rounded,
                    color: Colors.white70,
                    size: 16,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: attached != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attached.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        attached.balance > 0
                            ? S.tr(
                                'Solde dû : ${MoneyFormat.format(attached.balance)}',
                                'Balance due: ${MoneyFormat.format(attached.balance)}',
                              )
                            : S.tr('Compte soldé', 'Account settled'),
                        style: TextStyle(
                          color: attached.balance > 0
                              ? const Color(0xFFFFB4AB)
                              : const Color(0xFF9FE7C5),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : TextFormField(
                    // initialValue : contrôleur interne stable (un TextField
                    // avec controller recréé au build perdrait le focus à
                    // chaque frappe — piègle classique HIG/drag).
                    initialValue: cart.customerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    onChanged: (v) =>
                        state._notifier.attachCustomer(null, name: v),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: S.tr(
                        'Nom direct du client (ex: M. Etoa, Hôtel Sawa…)',
                        'Direct customer name (e.g. M. Etoa, Hôtel Sawa…)',
                      ),
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12.5,
                      ),
                      prefixIcon: const Icon(
                        Icons.person_search_outlined,
                        color: Colors.white54,
                        size: 18,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          DavexPressable(
            onTap: state._openClientSheet,
            semanticLabel: S.tr('Rattacher un client', 'Attach a customer'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: _posBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_alt_outlined,
                      color: Colors.white, size: 14),
                  const SizedBox(width: 5),
                  Text(
                    attached != null
                        ? S.tr('Changer', 'Change')
                        : S.tr('Client', 'Customer'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.state, required this.index});

  final _DavexVenteScreenState state;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LkPalette.of(context);
    final cart = ref.watch(davexCartProvider);
    final line = cart.lines[index];
    final lineProduct = state._allProducts
        .where((x) => x.id == line.productId)
        .firstOrNull;
    final overStock =
        lineProduct != null &&
        lineProduct.trackStock &&
        line.quantity > lineProduct.stockQty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(LkColors.radiusLarge),
        border: Border.all(
          color: overStock ? p.danger : p.borderDecorative,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  line.productName.isNotEmpty
                      ? line.productName.substring(0, 1).toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: _posBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (line.productId == null)
                      DavexStatusBadge.text(
                        S.tr('Hors catalogue', 'Uncatalogued'),
                        tone: DavexTone.neutral,
                      )
                    else
                      Text(
                        '${MoneyFormat.format(line.unitPrice)} / ${line.unit}',
                        style: const TextStyle(
                          color: _posBlue,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (overStock)
                      Text(
                        S.tr(
                          'Stock insuffisant',
                          'Insufficient stock',
                        ),
                        style: TextStyle(
                          color: p.danger,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                MoneyFormat.format(line.lineTotal),
                style: TextStyle(
                  color: p.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Supprimer la ligne (poubelle, cible 44 — HIG).
              DavexIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: S.tr('Retirer la ligne', 'Remove line'),
                size: 40,
                onPressed: () {
                  state._notifier.removeAt(index);
                  HapticFeedback.lightImpact();
                },
              ),
              // − qty + : piloté par INDEX (les lignes hors catalogue partagent
              // productId == null — une variation par id les confondrait).
              DavexQuantitySelector(
                value: line.quantity.round(),
                onDecrease: () => state._notifier.changeQuantityAt(index, -1),
                onIncrease: () {
                  if (!state._notifier.setQuantityAt(
                    index,
                    lineProduct,
                    line.quantity.round() + 1,
                  )) {
                    state._toast(
                      S.tr(
                        'Quantité supérieure au stock disponible.',
                        'Quantity exceeds available stock.',
                      ),
                      tone: LkToastTone.warning,
                      icon: Icons.inventory_2_outlined,
                    );
                  }
                },
              ),
              // Miroir visuel du total ligne (maquette : chip prix à droite).
              Text(
                line.productId == null
                    ? S.tr('Libre', 'Free')
                    : '${line.quantity.round()} × ${MoneyFormat.format(line.unitPrice)}',
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanierBottomBar extends ConsumerWidget {
  const _PanierBottomBar({required this.state});

  final _DavexVenteScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LkPalette.of(context);
    final cart = ref.watch(davexCartProvider);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.borderDecorative)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        children: [
          if (cart.remise != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${cart.remise!.label} :',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '- ${MoneyFormat.format(cart.remise!.amount)}',
                    style: const TextStyle(
                      color: _posBlue,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.tr('Total Net (${cart.label})', 'Net total (${cart.label})'),
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      MoneyFormat.format(cart.total),
                      style: TextStyle(
                        color: p.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              DavexButton(
                label: S.tr('Remise', 'Discount'),
                icon: Icons.local_offer_outlined,
                variant: DavexButtonVariant.secondary,
                onPressed: state._openRemise,
              ),
              const SizedBox(width: 8),
              DavexButton(
                label: S.tr('Encaisser', 'Checkout'),
                icon: Icons.payments_outlined,
                onPressed: state._openPayment,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Encaissement (maquette L1300–1387) ──────────────────────────────────────

/// CTA vert « Encaisser X FCFA » pixel de la maquette (bg-emerald-500).
/// DavexButton ne couvre que les 4 variantes de la charte ; cette unité
/// codée en pixels dans la maquette est recréée localement avec les
/// tokens sémantiques projet (success / onAction-like encre foncée).
class _PayCta extends StatelessWidget {
  const _PayCta({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final enabled = onPressed != null && !busy;
    return DavexPressable(
      onTap: enabled ? onPressed : null,
      semanticLabel: label,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: enabled
                ? [p.success, const Color(0xFF0EA86B)]
                : [p.disabledBg, p.disabledBg],
          ),
          borderRadius: BorderRadius.circular(LkColors.radiusLarge),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: p.success.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(icon ?? Icons.lock_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return DavexPressable(
      onTap: onTap,
      semanticLabel: title,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _posBlue.withValues(alpha: 0.06) : p.surface,
          borderRadius: BorderRadius.circular(LkColors.radiusLarge),
          border: Border.all(
            color: selected ? _posBlue : p.borderDecorative,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? _posBlue
                    : p.info.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : _posBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 18,
              color: selected ? _posBlue : p.borderControl,
            ),
          ],
        ),
      ),
    );
  }
}

class _EncaissementView extends ConsumerWidget {
  const _EncaissementView({super.key, required this.state});

  final _DavexVenteScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LkPalette.of(context);
    final cart = ref.watch(davexCartProvider);
    final isMomo = state._payMethod == 'mtn_momo' ||
        state._payMethod == 'orange_money';
    final isMixed = state._payMethod == 'mixed';

    return ColoredBox(
      color: p.canvas,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(bottom: BorderSide(color: p.borderDecorative)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
            child: Row(
              children: [
                DavexIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: S.tr('Retour au panier', 'Back to cart'),
                  onPressed: () => state._setView(_VenteView.panier),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.tr('Encaissement', 'Checkout'),
                    style: TextStyle(
                      color: p.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Carte dégradée « Total à encaisser » (maquette L1300–1320).
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: _posBlueGradient,
                    borderRadius: BorderRadius.circular(LkColors.radiusXl),
                    boxShadow: [
                      BoxShadow(
                        color: _posBlue.withValues(alpha: 0.30),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.tr('Montant total à encaisser', 'Total to collect'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        MoneyFormat.format(cart.total),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        S.tr(
                          '${cart.itemCount} article${cart.itemCount > 1 ? 's' : ''} · ${cart.label}',
                          '${cart.itemCount} item(s) · ${cart.label}',
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  S.tr('Mode de paiement', 'Payment method'),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                // 4 tuiles maquette : Espèces, Mobile Money, Crédit, Mixte.
                _MethodTile(
                  title: S.tr('Espèces', 'Cash'),
                  subtitle: S.tr(
                    'Paiement comptant au comptoir',
                    'Over-the-counter cash payment',
                  ),
                  icon: Icons.payments_outlined,
                  selected: state._payMethod == 'cash',
                  onTap: () => state._setPayMethod('cash'),
                ),
                const SizedBox(height: 8),
                _MethodTile(
                  title: S.tr('Mobile Money', 'Mobile Money'),
                  subtitle: S.tr(
                    'MTN MoMo / Orange Money — référence saisie',
                    'MTN MoMo / Orange Money — manual reference',
                  ),
                  icon: Icons.smartphone_rounded,
                  selected: isMomo,
                  onTap: () => state._setPayMethod(
                    state._payMethod == 'orange_money'
                        ? 'orange_money'
                        : 'mtn_momo',
                  ),
                ),
                if (isMomo) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text(
                            S.tr('MTN MoMo', 'MTN MoMo'),
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: state._payMethod == 'mtn_momo',
                          onSelected: (_) =>
                              state._setPayMethod('mtn_momo'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(
                            S.tr('Orange Money', 'Orange Money'),
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: state._payMethod == 'orange_money',
                          onSelected: (_) =>
                              state._setPayMethod('orange_money'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _MethodTile(
                  title: S.tr('Vente à crédit', 'Credit sale'),
                  subtitle: S.tr(
                    'Client solvable, échéance ultérieure',
                    'Solvent customer, pay later',
                  ),
                  icon: Icons.account_balance_outlined,
                  selected: state._payMethod == 'credit',
                  onTap: () => state._setView(_VenteView.credit),
                ),
                const SizedBox(height: 8),
                _MethodTile(
                  title: S.tr('Mixte (espèces + crédit)', 'Mixed (cash + credit)'),
                  subtitle: S.tr(
                    'Un acompte en espèces, le reste à crédit',
                    'Cash part now, balance on credit',
                  ),
                  icon: Icons.swap_horiz_rounded,
                  selected: isMixed,
                  onTap: () => state._setPayMethod('mixed'),
                ),
                const SizedBox(height: 16),
                // Montant reçu (cash/mixte/momo) — pré-rempli au total.
                if (state._payMethod != 'credit') ...[
                  TextField(
                    controller: state._payAmountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: isMixed
                          ? S.tr(
                              'Acompte reçu en espèces (FCFA)',
                              'Cash down payment (FCFA)',
                            )
                          : S.tr(
                              'Montant reçu (FCFA)',
                              'Amount received (FCFA)',
                            ),
                      prefixIcon: const Icon(Icons.calculate_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (isMomo) ...[
                  // Écart maquette documenté : pas de push USSD réel dans la
                  // logique projet — la référence transaction est saisie.
                  TextField(
                    controller: state._momoRefCtrl,
                    decoration: InputDecoration(
                      labelText: S.tr(
                        'Référence de la transaction',
                        'Transaction reference',
                      ),
                      hintText: S.tr(
                        'ex. RCT7f8a21b9…',
                        'e.g. RCT7f8a21b9…',
                      ),
                      prefixIcon: const Icon(Icons.receipt_long_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.warningBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: p.warningFg,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            S.tr(
                              'Le paiement est reçu sur votre compte marchand ; '
                              'enregistrez ici la référence affichée par le client.',
                              'Payment lands on your merchant account; record '
                              'here the reference shown by the customer.',
                            ),
                            style: TextStyle(
                              color: p.warningFg,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (isMixed && cart.customer == null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.infoBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person_add_alt_1, size: 15, color: p.infoFg),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            S.tr(
                              'Le solde à crédit sera rattaché au client du panier.',
                              'The credit balance is tied to the cart customer.',
                            ),
                            style: TextStyle(
                              color: p.infoFg,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (state._payError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.dangerBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.danger.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 16, color: p.dangerFg),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state._payError!,
                            style: TextStyle(
                              color: p.dangerFg,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _PayCta(
                  label: S.tr(
                    'Encaisser ${MoneyFormat.format(cart.total)}',
                    'Collect ${MoneyFormat.format(cart.total)}',
                  ),
                  busy: state._submitting,
                  onPressed: state._submitting ? null : state._complete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Vente à crédit (maquette L2119–2473) ────────────────────────────────────

class _CreditView extends ConsumerWidget {
  const _CreditView({super.key, required this.state});

  final _DavexVenteScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LkPalette.of(context);
    final cart = ref.watch(davexCartProvider);
    final customers =
        ref.watch(_venteCustomersProvider).valueOrNull ?? const <Customer>[];
    // Créanciers d'abord (maquette : dette affichée sur chaque ligne).
    final debtors = customers.where((c) => c.balance > 0).toList()
      ..sort((a, b) => b.balance.compareTo(a.balance));
    final others = customers.where((c) => c.balance <= 0).toList();
    final rows = [...debtors, ...others];

    return ColoredBox(
      color: p.canvas,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(bottom: BorderSide(color: p.borderDecorative)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
            child: Row(
              children: [
                DavexIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: S.tr('Retour à lencaissement', 'Back to checkout'),
                  onPressed: () => state._setView(_VenteView.encaissement),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.tr('Vente à crédit', 'Credit sale'),
                    style: TextStyle(
                      color: p.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: _posBlueGradient,
                    borderRadius: BorderRadius.circular(LkColors.radiusXl),
                    boxShadow: [
                      BoxShadow(
                        color: _posBlue.withValues(alpha: 0.30),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.tr(
                          'Montant total à créditer',
                          'Total to credit',
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        MoneyFormat.format(cart.total),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        S.tr(
                          'Le solde dû du client sera augmenté de ce montant.',
                          "The customer's balance due increases by this amount.",
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Segment maquette : client existant / nouveau client.
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: p.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      for (final (label, isNew) in [
                        (S.tr('Client existant', 'Existing customer'), false),
                        (S.tr('Nouveau client', 'New customer'), true),
                      ]) ...[
                        Expanded(
                          child: DavexPressable(
                            onTap: () => state._setNewDebtor(isNew),
                            semanticLabel: label,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: state._newDebtor == isNew
                                    ? p.surface
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: state._newDebtor == isNew
                                    ? [p.shadowCard]
                                    : const [],
                              ),
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: state._newDebtor == isNew
                                      ? p.text
                                      : p.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (state._newDebtor) ...[
                  // Nom libre bandeau accepté aussi (customerName) — la
                  // création réelle exige un nom (CustomerService.create).
                  TextField(
                    controller: state._newDebtorNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: S.tr('Nom du client *', 'Customer name *'),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: state._newDebtorPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: S.tr('Téléphone (facultatif)', 'Phone (optional)'),
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ] else if (rows.isEmpty)
                  DavexStateView(
                    title: S.tr('Aucun client', 'No customers'),
                    message: S.tr(
                      'Créez dabord un client (onglet Client) pour enregistrer '
                      'une vente à crédit.',
                      'Create a customer first to record a credit sale.',
                    ),
                    icon: Icons.people_outline_rounded,
                    actionLabel: S.tr(
                      'Nouveau client',
                      'New customer',
                    ),
                    onAction: () => state._setNewDebtor(true),
                  )
                else
                  ...rows.map((c) {
                    final selected = cart.customer?.id == c.id;
                    final owes = c.balance > 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DavexPressable(
                        onTap: () {
                          state._notifier.attachCustomer(c);
                          state._setNewDebtor(false);
                        },
                        semanticLabel: c.name,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected
                                ? _posBlue.withValues(alpha: 0.06)
                                : p.surface,
                            borderRadius:
                                BorderRadius.circular(LkColors.radiusLarge),
                            border: Border.all(
                              color: selected ? _posBlue : p.borderDecorative,
                              width: selected ? 1.6 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    _posBlue.withValues(alpha: 0.10),
                                child: Text(
                                  c.name.isNotEmpty
                                      ? c.name.substring(0, 1).toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: _posBlue,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.text,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (c.phone != null &&
                                        c.phone!.isNotEmpty)
                                      Text(
                                        c.phone!,
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              DavexStatusBadge.text(
                                owes
                                    ? S.tr(
                                        '${MoneyFormat.format(c.balance, showCurrency: false)} F dû',
                                        '${MoneyFormat.format(c.balance, showCurrency: false)} F owed',
                                      )
                                    : S.tr('Soldé', 'Settled'),
                                tone: owes
                                    ? DavexTone.danger
                                    : DavexTone.success,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 14),
                if (state._payError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.dangerBg,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: p.danger.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 16, color: p.dangerFg),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state._payError!,
                            style: TextStyle(
                              color: p.dangerFg,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _PayCta(
                  label: S.tr(
                    'Confirmer la vente à crédit',
                    'Confirm credit sale',
                  ),
                  icon: Icons.how_to_reg_outlined,
                  busy: state._submitting,
                  onPressed: state._submitting
                      ? null
                      : () {
                          if (state._newDebtor) {
                            state._createAndSellCredit();
                          } else if (cart.customer == null) {
                            state._toast(
                              S.tr(
                                'Sélectionnez un client pour le crédit.',
                                'Select a customer for the credit.',
                              ),
                              tone: LkToastTone.warning,
                              icon: Icons.person_outline_rounded,
                            );
                          } else {
                            state._complete(viaCredit: true);
                          }
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Succès plein écran (maquette : check vert, 1,8 s) ──────────────────────

class _SuccesView extends StatelessWidget {
  const _SuccesView({super.key, required this.state});

  final _DavexVenteScreenState state;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return ColoredBox(
      color: p.canvas,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF12B76A).withValues(alpha: 0.25),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 44,
                  color: Color(0xFF12B76A),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                S.tr('Vente confirmée !', 'Sale confirmed!'),
                style: TextStyle(
                  color: p.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                MoneyFormat.format(state._successTotal),
                style: const TextStyle(
                  color: Color(0xFF12B76A),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                S.tr(
                  '« ${state._successCartLabel} » · ouverture du ticket…',
                  '“${state._successCartLabel}” · opening receipt…',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Corps de modales ────────────────────────────────────────────────────────

class _RemiseChip extends StatelessWidget {
  const _RemiseChip({
    required this.pct,
    required this.selected,
    required this.onTap,
  });

  final int pct;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return DavexPressable(
      onTap: onTap,
      semanticLabel: '- $pct %',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _posBlue : p.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _posBlue : Colors.transparent,
          ),
        ),
        child: Text(
          '- $pct %',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : p.text,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PickerBody extends StatefulWidget {
  const _PickerBody({
    required this.product,
    required this.quantity,
    required this.onQuantityChanged,
  });

  final Product product;
  final int quantity;
  final ValueChanged<int> onQuantityChanged;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  late int _qty = widget.quantity;

  int get _max {
    final p = widget.product;
    if (p.isService || !p.trackStock) return 9999;
    return p.stockQty < 1 ? 1 : p.stockQty.round();
  }

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final lineTotal = widget.product.salePrice * _qty;
    final capped = _qty >= _max;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${MoneyFormat.format(widget.product.salePrice)} / ${widget.product.unit}',
            style: const TextStyle(
              color: _posBlue,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!widget.product.isService && widget.product.trackStock) ...[
            const SizedBox(height: 2),
            Text(
              S.tr(
                'Stock disponible : ${MoneyFormat.format(widget.product.stockQty, showCurrency: false)}',
                'Available stock: ${MoneyFormat.format(widget.product.stockQty, showCurrency: false)}',
              ),
              style: TextStyle(color: p.textSecondary, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DavexQuantitySelector(
                value: _qty,
                canDecrease: _qty > 1,
                canIncrease: !capped,
                onDecrease: () {
                  if (_qty <= 1) return;
                  setState(() => _qty--);
                  widget.onQuantityChanged(_qty);
                },
                onIncrease: () {
                  if (capped) return;
                  setState(() => _qty++);
                  widget.onQuantityChanged(_qty);
                },
              ),
            ],
          ),
          if (capped) ...[
            const SizedBox(height: 8),
            Text(
              S.tr(
                'Quantité maximale atteinte (stock disponible).',
                'Maximum quantity reached (available stock).',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.warningFg,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.infoBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  S.tr('Total ligne', 'Line total'),
                  style: TextStyle(
                    color: p.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  MoneyFormat.format(lineTotal),
                  style: const TextStyle(
                    color: _posBlue,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DavexButton(
            label: S.tr('Ajouter au panier', 'Add to cart'),
            icon: Icons.add_shopping_cart_rounded,
            expand: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
        ),
      ),
    );
  }
}

class _FirstSalePriceBody extends StatefulWidget {
  const _FirstSalePriceBody({
    required this.product,
    required this.controller,
    required this.onValid,
  });

  final Product product;
  final TextEditingController controller;
  final ValueChanged<double> onValid;

  @override
  State<_FirstSalePriceBody> createState() => _FirstSalePriceBodyState();
}

class _FirstSalePriceBodyState extends State<_FirstSalePriceBody> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            S.tr(
              'Ce produit na pas encore de prix de vente. Saisissez le prix '
              'appliqué au client — il sera enregistré sur la fiche.',
              'This product has no selling price yet. Enter the price applied '
              'to the customer — it will be saved on the record.',
            ),
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: widget.controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: S.tr('Prix de vente (FCFA)', 'Selling price (FCFA)'),
              prefixIcon: const Icon(Icons.sell_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 14),
          DavexButton(
            label: S.tr('Valider ce prix', 'Confirm this price'),
            icon: Icons.check_rounded,
            expand: true,
            onPressed: () {
              final price = MoneyFormat.parse(widget.controller.text) ?? 0;
              if (price <= 0) {
                setState(
                  () => _error = S.tr(
                    'Saisissez un prix supérieur à 0.',
                    'Enter a price greater than 0.',
                  ),
                );
                return;
              }
              widget.onValid(price);
              Navigator.pop(context);
            },
          ),
        ],
        ),
      ),
    );
  }
}

class _AdHocBody extends StatefulWidget {
  const _AdHocBody({
    required this.nameCtrl,
    required this.priceCtrl,
    required this.qtyCtrl,
    required this.unitCtrl,
    required this.onConfirm,
  });

  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController unitCtrl;
  final void Function(String name, double price, int qty, String unit)
      onConfirm;

  @override
  State<_AdHocBody> createState() => _AdHocBodyState();
}

class _AdHocBodyState extends State<_AdHocBody> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    // SingleChildScrollView : la remontée du clavier réduit le sheet ; un
    // Column nu déborde (RenderFlex overflow) sur petits écrans.
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            S.tr(
              'Vendez un article sans fiche : il entre au panier comme ligne '
              'libre, puis vous pourrez créer sa fiche après la vente.',
              'Sell an item without a record: it enters the cart as a free '
              'line; you can create its record after the sale.',
            ),
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.nameCtrl,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: S.tr('Désignation *', 'Item name *'),
              prefixIcon: const Icon(Icons.inventory_2_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.priceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: S.tr('Prix *', 'Price *'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: TextField(
                  controller: widget.qtyCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: S.tr('Qté', 'Qty'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: widget.unitCtrl,
                  decoration: InputDecoration(
                    labelText: S.tr('Unité', 'Unit'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: p.dangerFg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          DavexButton(
            label: S.tr('Ajouter au panier', 'Add to cart'),
            icon: Icons.add_shopping_cart_rounded,
            expand: true,
            onPressed: () {
              final name = widget.nameCtrl.text.trim();
              final price = MoneyFormat.parse(widget.priceCtrl.text) ?? 0;
              final qty =
                  int.tryParse(widget.qtyCtrl.text.trim().isEmpty
                      ? '1'
                      : widget.qtyCtrl.text.trim()) ??
                  0;
              if (name.isEmpty || price <= 0 || qty < 1) {
                setState(
                  () => _error = S.tr(
                    'Désignation, prix (> 0) et quantité (≥ 1) sont requis.',
                    'Name, price (> 0) and quantity (≥ 1) are required.',
                  ),
                );
                return;
              }
              final unit = widget.unitCtrl.text.trim();
              widget.onConfirm(
                name,
                price,
                qty,
                unit.isEmpty ? S.tr('pièce', 'piece') : unit,
              );
              Navigator.pop(context);
            },
          ),
        ],
        ),
      ),
    );
  }
}

class _CustomerSheetBody extends ConsumerWidget {
  const _CustomerSheetBody({
    required this.controller,
    required this.customers,
    required this.current,
    required this.onPick,
  });

  final ScrollController controller;
  final List<Customer> customers;
  final Customer? current;
  final ValueChanged<Customer?> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LkPalette.of(context);
    if (customers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: DavexStateView(
          title: S.tr('Aucun client', 'No customers'),
          message: S.tr(
            'Le registre clients est vide. Utilisez le nom direct dans le '
            'bandeau du panier pour cet article.',
            'The customer register is empty. Use the direct name in the cart '
            'banner for this item.',
          ),
          icon: Icons.people_outline_rounded,
        ),
      );
    }
    return ListView.separated(
      controller: controller,
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: customers.length + (current != null ? 2 : 1),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        // Option « détacher » + recherche nom direct en pied de liste.
        if (i >= customers.length) {
          if (current != null && i == customers.length) {
            return DavexPressable(
              onTap: () => onPick(null),
              semanticLabel: S.tr('Détacher', 'Detach'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.dangerBg,
                  borderRadius: BorderRadius.circular(LkColors.radiusLarge),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_off_rounded, size: 18, color: p.dangerFg),
                    const SizedBox(width: 10),
                    Text(
                      S.tr(
                        'Détacher le client rattaché',
                        'Detach the attached customer',
                      ),
                      style: TextStyle(
                        color: p.dangerFg,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              S.tr(
                'Astuce : le champ « Nom direct » du bandeau panier '
                'enregistre un client non encore au registre.',
                'Tip: the cart banner "Direct name" field records a customer '
                'not yet in the register.',
              ),
              style: TextStyle(color: p.textSecondary, fontSize: 11.5),
            ),
          );
        }
        final c = customers[i];
        final selected = current?.id == c.id;
        final owes = c.balance > 0;
        return DavexPressable(
          onTap: () => onPick(c),
          semanticLabel: c.name,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? p.infoBg : p.surface,
              borderRadius: BorderRadius.circular(LkColors.radiusLarge),
              border: Border.all(
                color: selected ? p.info : p.borderDecorative,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: _posBlue.withValues(alpha: 0.10),
                  child: Text(
                    c.name.isNotEmpty ? c.name.substring(0, 1).toUpperCase() : '?',
                    style: const TextStyle(
                      color: _posBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (c.phone != null && c.phone!.isNotEmpty)
                        Text(
                          c.phone!,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                if (owes)
                  DavexStatusBadge.text(
                    S.tr(
                      '${MoneyFormat.format(c.balance, showCurrency: false)} F dû',
                      '${MoneyFormat.format(c.balance, showCurrency: false)} F owed',
                    ),
                    tone: DavexTone.danger,
                  )
                else
                  DavexStatusBadge.text(
                    S.tr('Soldé', 'Settled'),
                    tone: DavexTone.success,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
