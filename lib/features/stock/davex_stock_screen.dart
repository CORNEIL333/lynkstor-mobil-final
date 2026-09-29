import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/permissions/permission_guard.dart';
import '../../core/permissions/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/davex_button.dart';
import '../../design_system/components/davex_filter_chip.dart';
import '../../design_system/components/davex_pressable.dart';
import '../../design_system/components/davex_quantity_selector.dart';
import '../../design_system/components/davex_search_field.dart';
import '../../design_system/components/davex_sheet.dart';
import '../../design_system/components/davex_states.dart';
import '../../design_system/components/davex_status_badge.dart';
import '../../design_system/components/davex_tone.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';
import '../ai_assistant/lynk_quick_sheet.dart';
import '../../shared/services/product_service.dart';

// ─── Écran Stock recréé depuis la maquette (StockScreen, App.tsx L3444–4631) ─
//
// Décision d'audit (processus senior, zéro fusion silencieuse) :
// RECRÉER. L'ancien `stock_screen.dart` (StockScreen) n'est PAS patché :
// il reste sur disque (fixtures de tests) mais est déréférencé du router au
// profit de cet écran. Toute la LOGIQUE est réutilisée telle quelle :
// ProductService.list/categories/update/create, adjustStock (mouvement
// obligatoire, newQty absolu), table réelle StockMovements (types
// init|sale|purchase|return|loss|damage|inventory|transfer|adjustment),
// routes existantes /products/new, /products/:id, /products/catalog,
// /purchases, /inventory, Lynk (pendingAiPromptProvider + quick sheet).
//
// Mapping maquette → unité par unité :
// - barre recherche + 3 tuiles bleues #0050FF (caméra facture, catalogue
//   métier, + produit manuel) ;
// - chips catégories actives orange #FF9800 → DavexFilterChip (token action) ;
// - bascule d'affichage express (Package) / assisté (BarChart3) ;
// - bandeau ambre « n produit(s) à finaliser » ;
// - trio de métriques Critique / Bas / Valeur ;
// - assisté : carte dégradée navy « Valeur totale du stock » + bouton
//   « + Mouvement typé », carte IA réassort, barre d'alerte ambre ;
// - cartes produits à bordure d'alerte (rouge/ambre/gris) ;
// - express : ±1 en attente (staged) + « n unité(s) modifiée(s) » + barre
//   violette collante « Appliquer N modification(s) — Motif requis » ;
// - assisté : jauge de stock colorée ;
// - modales : fiche produit (85), mouvement typé (7 motifs), motif d'apply.
//
// Écarts maquette↔logique RÉELLE documentés (aucune fabrication) :
// - bouton caméra « réception par photo de facture (OCR) » : la maquette
//   pré-remplit 3 lignes FAUSSES (Huile/Riz/Sucre) après une fausse
//   simulation de 1,5 s. Aucun moteur OCR n'existe dans le projet — la tuile
//   est mappée sur la RÉELLE route Achats (/purchases), qui est le chemin
//   authentique d'une réception facture ;
// - « Politique Commerciale » (prix fixe/négociable/free/on_order) : aucun
//   champ correspondant dans Product → NON FABRIQUÉ ;
// - « Conditionnement » (unite/carton/paquet, unitsPerPack) : aucun champ
//   persisté → le convertisseur cartons→unités de la fiche est un
//   calculateur SAISONNIER (alimente le stock visé, rien de persisté) ;
// - brouillons catalogue (catalogueStatus==='draft') : pas de tel statut →
//   mappé sur les produits actifs sans prix de vente (salePrice ≤ 0,
//   invendables tels quels) ;
// - IA « Stock Vivant Prédictif » : texte prédictif faux dans la maquette →
//   carte nourrie aux SEULS comptes réels (ruptures/bas) + relance Lynk
//   (réponses ancrées sur données locales, déjà en production) ;
// - jauge assisté : la maquette n'a pas de notion de « cible » de stock →
//   échelle visuelle 0→3×seuil de réappro (documentée, pas une donnée).
//
// Couleurs locales hors charte (pixel maquette, comme §11b Vente) : bleu
// action #0050FF, violette CTA #7C3AED, dégradés navy/violet.

const Color _posBlue = Color(0xFF0050FF);
const Color _ctaViolet = Color(0xFF7C3AED);
const Color _ctaVioletDeep = Color(0xFF6D28D9);

const LinearGradient _navyGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1E3A8A), Color(0xFF312E81)],
);

const LinearGradient _aiGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF581C87)],
);

const LinearGradient _violetGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_ctaViolet, _ctaVioletDeep],
);

/// Encres de jauge de la maquette (red-500 #F04438 / amber-500 #F79009 /
/// green-500 #12B76A) — rôles sémantiques danger/warning/success.
const Color _gaugeDanger = Color(0xFFF04438);
const Color _gaugeWarning = Color(0xFFF79009);
const Color _gaugeSuccess = Color(0xFF12B76A);

enum _StockMode { express, assiste }

enum _StockAlert { none, low, out }

// ─── Données réelles ─────────────────────────────────────────────────────────

class _StockData {
  const _StockData({required this.products, required this.categories});

  final List<Product> products;
  final List<Category> categories;

  Iterable<Product> get tracked =>
      products.where((p) => p.trackStock && !p.isService);

  int get outCount =>
          tracked.where((p) => p.stockQty <= 0).length;

  int get lowCount => tracked
      .where((p) => p.stockQty > 0 && p.stockQty <= p.lowStockThreshold)
      .length;

  /// Valeur de vente du stock (maquette : `price × stock`).
  double get saleValue =>
      tracked.fold(0.0, (sum, p) => sum + p.stockQty * p.salePrice);

  /// Brouillons : actifs, suivis, sans prix de vente → invendables au
  /// comptoir tant que le prix n'est pas saisi (mapping de catalogueStatus).
  List<Product> get drafts => products
      .where((p) => p.isActive && p.trackStock && !p.isService && p.salePrice <= 0)
      .toList();

  String categoryName(String? id) {
    for (final c in categories) {
      if (c.id == id) return c.name;
    }
    return S.tr('Sans catégorie', 'Uncategorised');
  }
}

/// Produits + catégories. autoDispose : rechargé au retour sur l'onglet et
/// après chaque ajustement (jamais de stock périmé à l'écran).
final _stockDataProvider = FutureProvider.autoDispose<_StockData?>((ref) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return null;
  final service = ref.watch(productServiceProvider);
  final products = await service.list(business.id);
  final cats = await service.categories(business.id);
  return _StockData(products: products, categories: cats);
});

_StockAlert _alertOf(Product p) {
  if (!p.trackStock || p.isService) return _StockAlert.none;
  if (p.stockQty <= 0) return _StockAlert.out;
  if (p.stockQty <= p.lowStockThreshold) return _StockAlert.low;
  return _StockAlert.none;
}

/// Libellés FR des types RÉELS de StockMovements (commentaire du schéma :
/// init|sale|purchase|return|loss|damage|inventory|transfer|adjustment).
String movementTypeLabel(String type) => switch (type) {
  'init' => S.tr('Stock initial', 'Initial stock'),
  'sale' => S.tr('Vente', 'Sale'),
  'purchase' => S.tr('Entrée (achat)', 'Receipt (purchase)'),
  'return' => S.tr('Retour', 'Return'),
  'loss' => S.tr('Perte / consommation', 'Loss / consumption'),
  'damage' => S.tr('Casse', 'Damage'),
  'inventory' => S.tr('Inventaire', 'Stock count'),
  'transfer' => S.tr('Transfert / sortie', 'Transfer / out'),
  _ => S.tr('Ajustement', 'Adjustment'),
};

String _shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

// ─── Écran ───────────────────────────────────────────────────────────────────

class DavexStockScreen extends ConsumerStatefulWidget {
  const DavexStockScreen({super.key, this.embedded = false});

  /// true : affiché dans le shell DAVEX (onglet Stock) — pas de chrome propre.
  final bool embedded;

  @override
  ConsumerState<DavexStockScreen> createState() => _DavexStockScreenState();
}

class _DavexStockScreenState extends ConsumerState<DavexStockScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _categoryId; // null = « Tous »
  _StockMode _mode = _StockMode.express;

  /// Ajustements staged express : productId → nouvelle quantité VISÉE.
  /// Rien n'est écrit tant que « Appliquer » n'a pas été confirmé avec un
  /// motif (adjustStock exige newQty + reason — logique réelle conservée).
  final Map<String, double> _staged = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _canAdjust =>
      PermissionGuard.of(ref.read(sessionProvider).role).allows(
        AppPermission.stockAdjust,
      );

  double _displayQty(Product p) => _staged[p.id] ?? p.stockQty;

  void _stage(Product p, double delta) {
    HapticFeedback.selectionClick();
    final target = (_displayQty(p) + delta).clamp(0, double.infinity).toDouble();
    setState(() {
      if (target == p.stockQty) {
        _staged.remove(p.id);
      } else {
        _staged[p.id] = target;
      }
    });
  }

  int get _stagedCount => _staged.length;

  Future<void> _applyStaged(String motif) async {
    final business = ref.read(sessionProvider).business;
    if (business == null || _staged.isEmpty) return;
    final entries = Map<String, double>.of(_staged);
    var applied = 0;
    String? failure;
    for (final e in entries.entries) {
      try {
        await ref.read(productServiceProvider).adjustStock(
          businessId: business.id,
          productId: e.key,
          newQty: e.value,
          reason: motif,
          userId: ref.read(sessionProvider).user?.id,
          userRole: ref.read(sessionProvider).role,
        );
        applied++;
      } on Object catch (err) {
        failure ??= err.toString();
      }
    }
    if (!mounted) return;
    // Échec partiel : les quantités visées restent staged (le rechargement
    // afficherait un écart inexpliqué — l'utilisateur peut réessayer).
    if (failure == null) setState(_staged.clear);
    ref.invalidate(_stockDataProvider);
    if (failure != null) {
      showLkToast(
        context,
        S.tr(
          '$applied sur ${entries.length} appliqué(s) — $failure',
          '$applied of ${entries.length} applied — $failure',
        ),
        tone: LkToastTone.warning,
      );
    } else {
      showLkToast(
        context,
        S.tr(
          '$applied mouvement(s) de stock enregistré(s).',
          '$applied stock movement(s) recorded.',
        ),
        tone: LkToastTone.success,
      );
    }
  }

  void _openReasonSheet() {
    if (_stagedCount == 0) return;
    if (!_canAdjust) {
      showLkToast(
        context,
        S.tr(
          'Votre rôle ne permet pas d\'ajuster le stock.',
          'Your role cannot adjust stock.',
        ),
        tone: LkToastTone.warning,
      );
      return;
    }
    showDavexSheet<void>(
      context,
      title: S.tr(
        'Appliquer $_stagedCount modification(s)',
        'Apply $_stagedCount change(s)',
      ),
      initialChildSize: 0.5,
      builder: (context, controller) => _ReasonSheet(
        scrollController: controller,
        stagedCount: _stagedCount,
        onConfirm: (motif) {
          Navigator.of(context).pop();
          _applyStaged(motif);
        },
      ),
    );
  }

  void _openProductSheet(Product p) {
    HapticFeedback.lightImpact();
    showDavexSheet<void>(
      context,
      title: S.tr('Fiche produit', 'Product sheet'),
      builder: (context, controller) =>
          _ProductSheet(product: p, scrollController: controller),
    );
  }

  void _openMovementSheet({Product? preset}) {
    showDavexSheet<void>(
      context,
      title: S.tr('Mouvement de stock typé', 'Typed stock movement'),
      builder: (context, controller) =>
          _MovementSheet(preset: preset, scrollController: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final async = ref.watch(_stockDataProvider);

    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : p.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        top: !widget.embedded,
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: async.when(
                loading: () => const DavexLoading(),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: DavexStateView(
                    title: S.tr('Erreur', 'Error'),
                    message: e.toString(),
                    icon: Icons.error_outline,
                  ),
                ),
                data: (data) => data == null
                    ? DavexStateView(
                        title: S.tr(
                          'Aucun commerce actif',
                          'No active business',
                        ),
                      )
                    : _buildList(context, data),
              ),
            ),
            if (_mode == _StockMode.express && _stagedCount > 0 && _canAdjust)
              _ApplyBar(count: _stagedCount, onApply: _openReasonSheet),
          ],
        ),
      ),
    );
  }

  // Barre haute maquette : recherche + 3 tuiles bleues, chips catégories,
  // compteur + bascule express/assisté.
  Widget _buildTopBar(BuildContext context) {
    final p = LkPalette.of(context);
    final session = ref.watch(sessionProvider);
    final canManageProducts = PermissionGuard.of(
      session.role,
    ).allows(AppPermission.productsManage);
    final data = ref.watch(_stockDataProvider).maybeWhen(
      data: (d) => d,
      orElse: () => null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: DavexSearchField(
                  controller: _searchCtrl,
                  hintText: S.tr(
                    'Rechercher un produit…',
                    'Search a product…',
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              const SizedBox(width: 10),
              _BlueActionTile(
                icon: Icons.request_quote_outlined,
                semanticLabel: S.tr(
                  'Réception facture (achats)',
                  'Invoice receipt (purchases)',
                ),
                // Maquette : caméra OCR simulée (3 lignes fausses). Réel :
                // une réception facture passe par la route Achats.
                onTap: () => context.push('/purchases'),
              ),
              if (canManageProducts) ...[
                const SizedBox(width: 8),
                _BlueActionTile(
                  icon: Icons.menu_book_outlined,
                  semanticLabel: S.tr(
                    'Catalogue métier',
                    'Sector catalogue',
                  ),
                  onTap: () => context.push('/products/catalog'),
                ),
              ],
              const SizedBox(width: 8),
              _BlueActionTile(
                icon: Icons.add,
                semanticLabel: S.tr('Nouveau produit', 'New product'),
                onTap: () => context.push('/products/new'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (data != null && data.categories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                DavexFilterChip(
                  label: S.tr('Tous', 'All'),
                  active: _categoryId == null,
                  onTap: () => setState(() => _categoryId = null),
                ),
                for (final c in data.categories) ...[
                  const SizedBox(width: 8),
                  DavexFilterChip(
                    label: c.name,
                    active: _categoryId == c.id,
                    onTap: () => setState(() => _categoryId = c.id),
                  ),
                ],
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(
            children: [
              Text(
                S.tr(
                  '${_filtered(data)?.length ?? 0} résultat(s)',
                  '${_filtered(data)?.length ?? 0} result(s)',
                ),
                style: TextStyle(color: p.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              _DisplaySwitch(
                mode: _mode,
                onChanged: (m) {
                  HapticFeedback.selectionClick();
                  setState(() => _mode = m);
                },
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: p.borderDecorative),
      ],
    );
  }

  List<Product>? _filtered(_StockData? data) {
    if (data == null) return null;
    final q = _query.toLowerCase();
    return data.products.where((prod) {
      if (_categoryId != null && prod.categoryId != _categoryId) return false;
      if (q.isEmpty) return true;
      return prod.name.toLowerCase().contains(q) ||
          (prod.sku?.toLowerCase().contains(q) ?? false) ||
          (prod.barcode?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Widget _buildList(BuildContext context, _StockData data) {
    final visible = _filtered(data) ?? const <Product>[];
    final p = LkPalette.of(context);

    if (data.products.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DavexStateView(
            title: S.tr('Aucun produit', 'No products yet'),
            message: S.tr(
              'Ajoute ton premier produit ou active des articles du catalogue métier.',
              'Add your first product or activate sector-catalogue items.',
            ),
            icon: Icons.inventory_2_outlined,
            actionLabel: S.tr('Ajouter un produit', 'Add a product'),
            onAction: () => context.push('/products/new'),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: p.action,
      onRefresh: () async => ref.invalidate(_stockDataProvider),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, _stagedCount > 0 ? 96 : 28),
        children: [
          if (data.drafts.isNotEmpty && _categoryId == null && _query.isEmpty)
            _DraftBanner(
              count: data.drafts.length,
              onComplete: () => _openProductSheet(data.drafts.first),
            ),
          _MetricTrio(
            outCount: data.outCount,
            lowCount: data.lowCount,
            saleValue: data.saleValue,
          ),
          if (_mode == _StockMode.assiste)
            _AssisteHeader(
              saleValue: data.saleValue,
              outCount: data.outCount,
              lowCount: data.lowCount,
              onMovement: _openMovementSheet,
              onAskLynk: () {
                ref.read(pendingAiPromptProvider.notifier).state = S.tr(
                  'Que dois-je réapprovisionner en priorité ?',
                  'What should I restock first?',
                );
                showLynkQuickSheet(context);
              },
            ),
          const SizedBox(height: 4),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: DavexStateView(
                title: S.tr('Aucun résultat', 'No result'),
                message: S.tr(
                  'Aucun produit ne correspond à cette recherche.',
                  'No product matches this search.',
                ),
                icon: Icons.search_off,
              ),
            )
          else
            for (final prod in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _StockProductCard(
                  product: prod,
                  categoryName: data.categoryName(prod.categoryId),
                  mode: _mode,
                  displayQty: _displayQty(prod),
                  staged: _staged.containsKey(prod.id),
                  canAdjust: _canAdjust,
                  onTap: () => _openProductSheet(prod),
                  onDecrease: () => _stage(prod, -1),
                  onIncrease: () => _stage(prod, 1),
                ),
              ),
        ],
      ),
    );
  }
}

// ─── Barre haute ─────────────────────────────────────────────────────────────

/// Tuile bleue #0050FF des 3 actions maquette (caméra/catalogue/+).
class _BlueActionTile extends StatelessWidget {
  const _BlueActionTile({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return DavexPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: _posBlue,
          borderRadius: BorderRadius.circular(LkColors.radiusMedium),
          boxShadow: AppColors.isDark(context) ? null : [p.shadowCard],
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

/// Bascule express (grille) / assisté (analyse) — `.lk-stock-display-switch`.
class _DisplaySwitch extends StatelessWidget {
  const _DisplaySwitch({required this.mode, required this.onChanged});

  final _StockMode mode;
  final ValueChanged<_StockMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.borderControl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, Icons.grid_view_rounded, _StockMode.express,
              S.tr('Vue rapide (ajuster ±)', 'Quick view (adjust ±)')),
          _segment(context, Icons.show_chart_rounded, _StockMode.assiste,
              S.tr('Analyse et alertes', 'Analysis and alerts')),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    IconData icon,
    _StockMode value,
    String tooltip,
  ) {
    final p = LkPalette.of(context);
    final active = mode == value;
    return Tooltip(
      message: tooltip,
      child: DavexPressable(
        onTap: () => onChanged(value),
        semanticLabel: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 40,
          height: 32,
          decoration: BoxDecoration(
            color: active ? p.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 17,
            color: active ? p.text : p.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─── Blocs de la liste ───────────────────────────────────────────────────────

/// Bandeau ambre « n produit(s) à finaliser » (brouillons = sans prix).
class _DraftBanner extends StatelessWidget {
  const _DraftBanner({required this.count, required this.onComplete});

  final int count;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.warningBg,
        borderRadius: BorderRadius.circular(LkColors.radiusLarge),
        border: Border.all(color: p.warning.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.tr(
              '$count produit(s) à finaliser',
              '$count product(s) to complete',
            ),
            style: TextStyle(
              color: p.warningFg,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.tr(
              'Ces fiches n\'ont pas de prix de vente : définissez-le pour les vendre au comptoir.',
              'These items have no sale price: set one to sell them at the counter.',
            ),
            style: TextStyle(color: p.warningFg, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          DavexButton(
            label: S.tr(
              'Compléter le premier produit',
              'Complete first product',
            ),
            icon: Icons.edit_note_rounded,
            onPressed: onComplete,
          ),
        ],
      ),
    );
  }
}

/// Trio Critique / Bas / Valeur (`.lk-stock-metrics`).
class _MetricTrio extends StatelessWidget {
  const _MetricTrio({
    required this.outCount,
    required this.lowCount,
    required this.saleValue,
  });

  final int outCount;
  final int lowCount;
  final double saleValue;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Row(
      children: [
        Expanded(child: _metric(context, p, DavexTone.danger,
            S.tr('Critique', 'Critical'), '$outCount')),
        const SizedBox(width: 8),
        Expanded(child: _metric(context, p, DavexTone.warning,
            S.tr('Bas', 'Low'), '$lowCount')),
        const SizedBox(width: 8),
        Expanded(
          child: _metric(
            context,
            p,
            DavexTone.success,
            S.tr('Valeur', 'Value'),
            '${MoneyFormat.format(saleValue, showCurrency: false)} F',
            small: true,
          ),
        ),
      ],
    );
  }

  Widget _metric(
    BuildContext context,
    LkPalette p,
    DavexTone tone,
    String label,
    String value, {
    bool small = false,
  }) {
    final colors = davexToneColors(p, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(LkColors.radiusLarge),
        border: Border.all(color: colors.fg.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.fg,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.fg,
              fontSize: small ? 13 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartes assisté : valorisation navy + « + Mouvement typé », IA réassort
/// (comptes RÉELS + relance Lynk), barre d'alerte ambre.
class _AssisteHeader extends StatelessWidget {
  const _AssisteHeader({
    required this.saleValue,
    required this.outCount,
    required this.lowCount,
    required this.onMovement,
    required this.onAskLynk,
  });

  final double saleValue;
  final int outCount;
  final int lowCount;
  final VoidCallback onMovement;
  final VoidCallback onAskLynk;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final alerts = outCount + lowCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        // Carte valorisation (dégradé blue-900 → indigo-900).
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: _navyGradient,
            borderRadius: BorderRadius.circular(LkColors.radiusLarge),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.tr(
                        'Valeur totale du stock',
                        'Total stock value',
                      ),
                      style: const TextStyle(
                        color: Color(0xFFBFDBFE),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      MoneyFormat.format(saleValue),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              DavexPressable(
                onTap: onMovement,
                semanticLabel: S.tr(
                  'Mouvement typé',
                  'Typed movement',
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.trending_up_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      SizedBox(width: 5),
                      Text(
                        '+ Mouvement typé',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Carte « assistant IA » : maquette = texte prédictif fictif ; ici
        // uniquement des comptes RÉELS + question ancrée posée à Lynk.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: _aiGradient,
            borderRadius: BorderRadius.circular(LkColors.radiusLarge),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _ctaViolet.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.smart_toy_outlined,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.tr('Assistant réassort', 'Restock assistant'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alerts == 0
                          ? S.tr(
                              'Aucune alerte : tout est au-dessus du seuil.',
                              'No alerts: everything is above threshold.',
                            )
                          : S.tr(
                              '$outCount en rupture, $lowCount sous le seuil de réappro.',
                              '$outCount out of stock, $lowCount below threshold.',
                            ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (alerts > 0)
                TextButton(
                  onPressed: onAskLynk,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text(S.tr('Demander à Lynk', 'Ask Lynk')),
                ),
            ],
          ),
        ),
        if (alerts > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: p.warningBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: davexToneColors(p, DavexTone.warning).fg,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.tr(
                      '$alerts produit(s) à réapprovisionner.',
                      '$alerts product(s) to restock.',
                    ),
                    style: TextStyle(
                      color: davexToneColors(p, DavexTone.warning).fg,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

// La suite (cartes produits, jauge, barre d'application, fiche produit,
// mouvement typé, motif) est dans la partie 2 de ce fichier.

// ─── Carte produit ───────────────────────────────────────────────────────────

class _StockProductCard extends StatelessWidget {
  const _StockProductCard({
    required this.product,
    required this.categoryName,
    required this.mode,
    required this.displayQty,
    required this.staged,
    required this.canAdjust,
    required this.onTap,
    required this.onDecrease,
    required this.onIncrease,
  });

  final Product product;
  final String categoryName;
  final _StockMode mode;
  final double displayQty;
  final bool staged;
  final bool canAdjust;
  final VoidCallback onTap;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final alert = _alertOf(product);
    final borderColor = switch (alert) {
      _StockAlert.out =>
        (AppColors.isDark(context) ? _gaugeDanger : const Color(0xFFFEE2E2))
            .withValues(alpha: AppColors.isDark(context) ? 0.5 : 1),
      _StockAlert.low =>
        (AppColors.isDark(context) ? _gaugeWarning : const Color(0xFFFEF3C7))
            .withValues(alpha: AppColors.isDark(context) ? 0.5 : 1),
      _StockAlert.none => p.borderControl,
    };
    final trackable =
        product.trackStock && !product.isService && !product.isDeleted;

    return DavexPressable(
      onTap: onTap,
      semanticLabel: product.name,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(LkColors.radiusLarge),
          border: Border.all(color: borderColor),
          boxShadow: AppColors.isDark(context) ? null : [p.shadowCard],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$categoryName · ${MoneyFormat.format(product.salePrice)}'
                        '${product.isActive ? '' : ' · ${S.tr('Inactif', 'Inactive')}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _statusRow(context, alert, trackable),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (mode == _StockMode.express && trackable && canAdjust)
                  DavexQuantitySelector(
                    value: displayQty,
                    canDecrease: displayQty > 0,
                    onDecrease: onDecrease,
                    onIncrease: onIncrease,
                  )
                else
                  _qtyChip(context, p, alert, trackable),
              ],
            ),
            if (staged)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  S.tr(
                    '${_diffLabel()} unité(s) modifiée(s) — pas encore appliqué',
                    '${_diffLabel()} unit(s) changed — not applied yet',
                  ),
                  style: TextStyle(
                    color: _ctaViolet,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (mode == _StockMode.assiste && trackable) ...[
              const SizedBox(height: 8),
              _GaugeBar(stockQty: product.stockQty, threshold: product.lowStockThreshold),
            ],
          ],
        ),
      ),
    );
  }

  String _diffLabel() {
    final d = displayQty - product.stockQty;
    return d > 0 ? '+${d.toStringAsFixed(0)}' : d.toStringAsFixed(0);
  }

  Widget _statusRow(BuildContext context, _StockAlert alert, bool trackable) {
    if (product.isService) {
      return DavexStatusBadge.text(
        S.tr('Service', 'Service'),
        tone: DavexTone.neutral,
      );
    }
    if (!trackable) {
      return DavexStatusBadge.text(
        S.tr('Stock non suivi', 'Stock untracked'),
        tone: DavexTone.neutral,
      );
    }
    return switch (alert) {
      _StockAlert.out => DavexStatusBadge.text(
        S.tr('Rupture', 'Out of stock'),
        tone: DavexTone.danger,
      ),
      _StockAlert.low => DavexStatusBadge.text(
        S.tr('Bas', 'Low'),
        tone: DavexTone.warning,
      ),
      _StockAlert.none => DavexStatusBadge.text(
        S.tr('Disponible', 'Available'),
        tone: DavexTone.success,
      ),
    };
  }

  Widget _qtyChip(BuildContext context, LkPalette p, _StockAlert alert, bool trackable) {
    final colors = !trackable
        ? davexToneColors(p, DavexTone.neutral)
        : switch (alert) {
            _StockAlert.out => davexToneColors(p, DavexTone.danger),
            _StockAlert.low => davexToneColors(p, DavexTone.warning),
            _StockAlert.none => davexToneColors(p, DavexTone.success),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        trackable
            ? '${product.stockQty.toStringAsFixed(0)} ${product.unit}'
            : '—',
        style: TextStyle(
          color: colors.fg,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Jauge assisté : échelle visuelle 0 → 3×seuil de réappro (convention
/// documentée — la maquette n'a pas de cible de stock dans son modèle).
class _GaugeBar extends StatelessWidget {
  const _GaugeBar({required this.stockQty, required this.threshold});

  final double stockQty;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final ceiling = threshold <= 0 ? 10.0 : threshold * 3;
    final fraction = (stockQty / ceiling).clamp(0.0, 1.0);
    final color = stockQty <= 0
        ? _gaugeDanger
        : stockQty <= threshold
        ? _gaugeWarning
        : _gaugeSuccess;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(height: 6, color: p.surfaceMuted),
          FractionallySizedBox(
            widthFactor: fraction < 0.04 ? 0.04 : fraction,
            child: Container(height: 6, color: color),
          ),
        ],
      ),
    );
  }
}

/// Barre violette collante « Appliquer N modification(s) — Motif requis ».
class _ApplyBar extends StatelessWidget {
  const _ApplyBar({required this.count, required this.onApply});

  final int count;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: DavexPressable(
          onTap: onApply,
          semanticLabel: S.tr(
            'Appliquer $count modification(s)',
            'Apply $count change(s)',
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: _violetGradient,
              borderRadius: BorderRadius.circular(LkColors.radiusLarge),
            ),
            child: Row(
              children: [
                const Icon(Icons.checklist_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.tr(
                          'Appliquer $count modification(s)',
                          'Apply $count change(s)',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        S.tr(
                          'Motif obligatoire — rien n\'est écrit avant confirmation.',
                          'Reason required — nothing is written before confirmation.',
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Modale : motif d'application des changements staged ────────────────────

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({
    required this.scrollController,
    required this.stagedCount,
    required this.onConfirm,
  });

  final ScrollController scrollController;
  final int stagedCount;
  final ValueChanged<String> onConfirm;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final _motifCtrl = TextEditingController();

  static const List<String> _presets = [
    'Réception fournisseur',
    'Correction d\'inventaire',
    'Casse / perte',
    'Vendu hors système',
    'Consommation interne',
  ];

  @override
  void dispose() {
    _motifCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final valid = _motifCtrl.text.trim().isNotEmpty;
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.tr(
              'Chaque ajustement crée un mouvement de stock tracé. Le motif est obligatoire.',
              'Each adjustment creates a tracked stock movement. The reason is required.',
            ),
            style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _presets)
                DavexFilterChip(
                  label: preset,
                  active: _motifCtrl.text == preset,
                  onTap: () {
                    _motifCtrl.text = preset;
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _motifCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: S.tr('Motif (obligatoire)', 'Reason (required)'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          DavexButton(
            label: S.tr(
              'Appliquer ${widget.stagedCount} modification(s)',
              'Apply ${widget.stagedCount} change(s)',
            ),
            icon: Icons.check_rounded,
            expand: true,
            onPressed: valid
                ? () => widget.onConfirm(_motifCtrl.text.trim())
                : null,
          ),
        ],
      ),
    );
  }
}

// ─── Modale : fiche produit (image, prix, stock, convertisseur, mouvements) ─

class _ProductSheet extends ConsumerStatefulWidget {
  const _ProductSheet({required this.product, required this.scrollController});

  final Product product;
  final ScrollController scrollController;

  @override
  ConsumerState<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends ConsumerState<_ProductSheet> {
  late Product _current = widget.product;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _packUnitsCtrl;
  late final TextEditingController _cartonsCtrl;
  late final TextEditingController _motifCtrl;
  late double _targetQty = _current.stockQty;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: _current.salePrice.toStringAsFixed(0),
    );
    _packUnitsCtrl = TextEditingController(text: '12');
    _cartonsCtrl = TextEditingController();
    _motifCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _packUnitsCtrl.dispose();
    _cartonsCtrl.dispose();
    _motifCtrl.dispose();
    super.dispose();
  }

  ProductInput get _asInput => ProductInput(
    name: _current.name,
    salePrice: _current.salePrice,
    description: _current.description,
    categoryId: _current.categoryId,
    sku: _current.sku,
    barcode: _current.barcode,
    unit: _current.unit,
    costPrice: _current.costPrice,
    wholesalePrice: _current.wholesalePrice,
    stockQty: _current.stockQty,
    lowStockThreshold: _current.lowStockThreshold,
    trackStock: _current.trackStock,
    isService: _current.isService,
    photoPath: _current.photoPath,
  );

  Future<void> _savePrice() async {
    final price = MoneyFormat.parse(_priceCtrl.text);
    if (price == null || !price.isFinite || price < 0) {
      showLkToast(
        context,
        S.tr('Prix invalide.', 'Invalid price.'),
        tone: LkToastTone.danger,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await ref.read(productServiceProvider).update(
        _current,
        ProductInput(
          name: _asInput.name,
          salePrice: price,
          description: _asInput.description,
          categoryId: _asInput.categoryId,
          sku: _asInput.sku,
          barcode: _asInput.barcode,
          unit: _asInput.unit,
          costPrice: _asInput.costPrice,
          wholesalePrice: _asInput.wholesalePrice,
          stockQty: _asInput.stockQty,
          lowStockThreshold: _asInput.lowStockThreshold,
          trackStock: _asInput.trackStock,
          isService: _asInput.isService,
          photoPath: _asInput.photoPath,
        ),
        userId: ref.read(sessionProvider).user?.id,
      );
      if (!mounted) return;
      setState(() => _current = updated);
      ref.invalidate(_stockDataProvider);
      showLkToast(
        context,
        price > 0
            ? S.tr('Prix enregistré.', 'Price saved.')
            : S.tr(
                'Prix à 0 : la fiche reste « à finaliser ».',
                'Price is 0: the sheet stays “to complete”.',
              ),
        tone: price > 0 ? LkToastTone.success : LkToastTone.warning,
      );
    } on Object catch (e) {
      if (mounted) {
        showLkToast(context, e.toString(), tone: LkToastTone.danger);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyStock() async {
    final motif = _motifCtrl.text.trim();
    if (motif.isEmpty) {
      showLkToast(
        context,
        S.tr(
          'Un motif est obligatoire pour ajuster le stock.',
          'A reason is required to adjust stock.',
        ),
        tone: LkToastTone.warning,
      );
      return;
    }
    if (!PermissionGuard.of(
      ref.read(sessionProvider).role,
    ).allows(AppPermission.stockAdjust)) {
      showLkToast(
        context,
        S.tr(
          'Votre rôle ne permet pas d\'ajuster le stock.',
          'Your role cannot adjust stock.',
        ),
        tone: LkToastTone.warning,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(productServiceProvider).adjustStock(
        businessId: _current.businessId,
        productId: _current.id,
        newQty: _targetQty,
        reason: motif,
        userId: ref.read(sessionProvider).user?.id,
        userRole: ref.read(sessionProvider).role,
      );
      if (!mounted) return;
      setState(() {
        _current = _current.copyWith(stockQty: _targetQty);
        _motifCtrl.clear();
      });
      ref.invalidate(_stockDataProvider);
      setState(() => _movements = null);
      showLkToast(
        context,
        S.tr('Stock ajusté.', 'Stock adjusted.'),
        tone: LkToastTone.success,
      );
    } on Object catch (e) {
      if (mounted) {
        showLkToast(context, e.toString(), tone: LkToastTone.danger);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<StockMovement>? _movements;
  bool _movementsLoading = false;

  Future<void> _loadMovements() async {
    if (_movementsLoading) return;
    setState(() => _movementsLoading = true);
    final db = ref.read(databaseProvider);
    final rows = await (db.select(db.stockMovements)
          ..where((t) => t.productId.equals(_current.id))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(8))
        .get();
    if (!mounted) return;
    setState(() {
      _movements = rows;
      _movementsLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final dark = AppColors.isDark(context);
    final trackable = _current.trackStock && !_current.isService;
    final changed = _targetQty != _current.stockQty;

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Photo (maquette : zone image ; réel : photoPath + fiche complète).
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: dark ? p.surfaceMuted : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(LkColors.radiusLarge),
              border: Border.all(color: p.borderControl),
            ),
            clipBehavior: Clip.antiAlias,
            child: _current.photoPath != null && File(_current.photoPath!).existsSync()
                ? Image.file(File(_current.photoPath!), fit: BoxFit.cover)
                : Icon(
                    Icons.inventory_2_outlined,
                    size: 34,
                    color: p.textSecondary,
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            _current.name,
            style: TextStyle(
              color: p.text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_current.unit} · ${S.tr('Seuil de réappro', 'Restock threshold')} '
            '${_current.lowStockThreshold.toStringAsFixed(0)}'
            '${(_current.sku ?? '').isEmpty ? '' : ' · ${_current.sku}'}',
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          // Prix (carte bleue maquette).
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark
                  ? _posBlue.withValues(alpha: 0.12)
                  : const Color(0xFFEFF5FF),
              borderRadius: BorderRadius.circular(LkColors.radiusLarge),
              border: Border.all(color: _posBlue.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.tr('Prix de vente', 'Sale price'),
                  style: const TextStyle(
                    color: _posBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixText: 'FCFA',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    DavexButton(
                      label: S.tr('Enregistrer', 'Save'),
                      variant: DavexButtonVariant.secondary,
                      busy: _saving,
                      onPressed: _saving ? null : _savePrice,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (trackable) ...[
            const SizedBox(height: 14),
            // Stock visé : stepper + raccourcis ±10 (maquette).
            Text(
              S.tr('Ajuster le stock', 'Adjust stock'),
              style: TextStyle(
                color: p.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                DavexPressable(
                  onTap: () => setState(
                    () => _targetQty = (_targetQty - 10).clamp(0, double.infinity).toDouble(),
                  ),
                  semanticLabel: '-10',
                  child: _quickBtn(context, '−10'),
                ),
                const SizedBox(width: 8),
                DavexQuantitySelector(
                  value: _targetQty,
                  canDecrease: _targetQty > 0,
                  onDecrease: () => setState(
                    () => _targetQty = (_targetQty - 1).clamp(0, double.infinity).toDouble(),
                  ),
                  onIncrease: () => setState(() => _targetQty += 1),
                ),
                const SizedBox(width: 8),
                DavexPressable(
                  onTap: () => setState(() => _targetQty += 10),
                  semanticLabel: '+10',
                  child: _quickBtn(context, '+10'),
                ),
                const Spacer(),
                Text(
                  '${S.tr('Actuel', 'Current')} ${_current.stockQty.toStringAsFixed(0)}',
                  style: TextStyle(color: p.textSecondary, fontSize: 12),
                ),
              ],
            ),
            if (changed) ...[
              const SizedBox(height: 8),
              Text(
                S.tr(
                  'Nouveau stock visé : ${_targetQty.toStringAsFixed(0)} ${_current.unit}',
                  'Target stock: ${_targetQty.toStringAsFixed(0)} ${_current.unit}',
                ),
                style: TextStyle(
                  color: _ctaViolet,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _motifCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                isDense: true,
                labelText: S.tr('Motif (obligatoire)', 'Reason (required)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DavexButton(
              label: S.tr('Ajuster le stock', 'Adjust stock'),
              icon: Icons.balance_rounded,
              expand: true,
              busy: _saving,
              onPressed: changed && !_saving ? _applyStock : null,
            ),
            const SizedBox(height: 14),
            // Convertisseur cartons → unités : calcul temporaire (aucun
            // champ conditionnement dans le modèle — écart documenté).
            Text(
              S.tr(
                'Convertisseur carton → unités',
                'Carton → units converter',
              ),
              style: TextStyle(
                color: p.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              S.tr(
                'Les valeurs saisies ne sont pas enregistrées : le résultat alimente seulement le stock visé.',
                'Entered values are not saved: the result only feeds the target stock.',
              ),
              style: TextStyle(color: p.textSecondary, fontSize: 11.5, height: 1.35),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _packUnitsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: S.tr(
                        'Unités / carton',
                        'Units / carton',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cartonsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: S.tr('Cartons', 'Cartons'),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '= ${_packTotal().toStringAsFixed(0)} ${_current.unit}',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                DavexButton(
                  label: S.tr(
                    'Ajouter au stock visé',
                    'Add to target stock',
                  ),
                  variant: DavexButtonVariant.secondary,
                  onPressed: _packTotal() > 0
                      ? () => setState(() => _targetQty += _packTotal())
                      : null,
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          // Historique des mouvements RÉELS (table StockMovements).
          Row(
            children: [
              Text(
                S.tr('Derniers mouvements', 'Recent movements'),
                style: TextStyle(
                  color: p.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (_movements == null && !_movementsLoading)
                TextButton(
                  onPressed: _loadMovements,
                  child: Text(S.tr('Charger', 'Load')),
                ),
            ],
          ),
          if (_movementsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: DavexLoading(),
            )
          else if (_movements != null)
            if (_movements!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  S.tr(
                    'Aucun mouvement enregistré.',
                    'No movement recorded.',
                  ),
                  style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                ),
              )
            else
              for (final m in _movements!) _movementRow(context, p, m),
          const SizedBox(height: 14),
          DavexButton(
            label: S.tr('Ouvrir la fiche complète', 'Open full sheet'),
            variant: DavexButtonVariant.ghost,
            icon: Icons.open_in_new_rounded,
            expand: true,
            onPressed: () {
              final router = GoRouter.of(context);
              final id = _current.id;
              Navigator.of(context).pop();
              router.push('/products/$id');
            },
          ),
        ],
      ),
    );
  }

  double _packTotal() {
    final per = MoneyFormat.parse(_packUnitsCtrl.text) ?? 0;
    final cartons = MoneyFormat.parse(_cartonsCtrl.text) ?? 0;
    if (!per.isFinite || !cartons.isFinite || per <= 0 || cartons <= 0) {
      return 0;
    }
    return (per * cartons).floorToDouble();
  }

  Widget _quickBtn(BuildContext context, String label) {
    final p = LkPalette.of(context);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.borderControl),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: p.text,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _movementRow(BuildContext context, LkPalette p, StockMovement m) {
    final positive = m.quantity >= 0;
    final color = positive ? _gaugeSuccess : _gaugeDanger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            positive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${positive ? '+' : ''}${m.quantity.toStringAsFixed(0)} '
              '· ${movementTypeLabel(m.type)}'
              '${(m.note ?? '').isEmpty ? '' : ' · ${m.note}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.text, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _shortDate(m.createdAt),
            style: TextStyle(color: p.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── Modale : mouvement de stock typé (7 motifs maquette → types réels) ─────

class _Motif {
  const _Motif(this.labelFr, this.labelEn, this.icon, this.type, this.sign);

  final String labelFr;
  final String labelEn;
  final IconData icon;

  /// Type RÉEL écrit dans StockMovements.type (schéma : purchase, transfer,
  /// return, damage, loss, adjustment).
  final String type;

  /// +1 entrée, −1 sortie, 0 = direction choisie par l'utilisateur.
  final int sign;
}

const List<_Motif> _motifs = [
  _Motif('Entrée', 'Receipt', Icons.inbox_rounded, 'purchase', 1),
  _Motif('Sortie', 'Issue', Icons.outbox_rounded, 'transfer', -1),
  _Motif('Retour client', 'Customer return', Icons.assignment_return_outlined, 'return', 1),
  _Motif('Retour fournisseur', 'Supplier return', Icons.local_shipping_outlined, 'return', -1),
  _Motif('Casse', 'Damage', Icons.no_meals_outlined, 'damage', -1),
  _Motif('Consommation', 'Consumption', Icons.local_cafe_outlined, 'loss', -1),
  _Motif('Ajustement', 'Adjustment', Icons.balance_outlined, 'adjustment', 0),
];

class _MovementSheet extends ConsumerStatefulWidget {
  const _MovementSheet({required this.preset, required this.scrollController});

  final Product? preset;
  final ScrollController scrollController;

  @override
  ConsumerState<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends ConsumerState<_MovementSheet> {
  String? _productId;
  int _motifIndex = 0;
  int _adjustSign = 1;
  final _qtyCtrl = TextEditingController(text: '10');
  final _commentCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _productId = widget.preset?.id;
  }

  @override
  void dispose() {
    // Jamais de dispose ici des contrôleurs utilisés par un champ pendant
    // l'animation de sortie : ce State vit dans le sheet, dispose n'est
    // appelé qu'après démontage réel (fin d'animation) — sûr contrairement
    // au pattern « dispose après await » de la v1.
    _qtyCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(Product product, double target, _Motif motif) async {
    setState(() => _saving = true);
    try {
      await ref.read(productServiceProvider).adjustStock(
        businessId: product.businessId,
        productId: product.id,
        newQty: target,
        reason: _commentCtrl.text.trim().isNotEmpty
            ? _commentCtrl.text.trim()
            : S.tr(motif.labelFr, motif.labelEn),
        userId: ref.read(sessionProvider).user?.id,
        type: motif.type,
        userRole: ref.read(sessionProvider).role,
      );
      if (!mounted) return;
      ref.invalidate(_stockDataProvider);
      Navigator.of(context).pop();
      showLkToast(
        context,
        S.tr(
          'Mouvement « ${motif.labelFr} » enregistré.',
          '“${motif.labelEn}” movement recorded.',
        ),
        tone: LkToastTone.success,
      );
    } on Object catch (e) {
      if (mounted) {
        showLkToast(context, e.toString(), tone: LkToastTone.danger);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final data = ref.watch(_stockDataProvider).maybeWhen(
      data: (d) => d,
      orElse: () => null,
    );
    final tracked =
        (data?.products ?? const <Product>[])
            .where((prod) => prod.trackStock && !prod.isService && !prod.isDeleted)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (tracked.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: DavexStateView(
          title: S.tr(
            'Aucun produit suivi en stock',
            'No stock-tracked product',
          ),
          message: S.tr(
            'Active le suivi de stock d\'un produit pour enregistrer des mouvements.',
            'Enable stock tracking on a product to record movements.',
          ),
          icon: Icons.inventory_2_outlined,
        ),
      );
    }
    final selected =
        tracked.firstWhere((prod) => prod.id == _productId, orElse: () => tracked.first);
    final motif = _motifs[_motifIndex];
    final sign = motif.sign == 0 ? _adjustSign : motif.sign;
    final qty = MoneyFormat.parse(_qtyCtrl.text) ?? 0;
    final target = selected.stockQty + sign * qty;
    final valid = qty > 0 && qty.isFinite && target >= 0;

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Produit concerné (+ stock actuel affiché, maquette).
          DropdownButtonFormField<String>(
            initialValue: selected.id,
            decoration: InputDecoration(
              labelText: S.tr('Produit', 'Product'),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final prod in tracked)
                DropdownMenuItem(
                  value: prod.id,
                  child: Text(
                    '${prod.name} · ${prod.stockQty.toStringAsFixed(0)} ${prod.unit}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _productId = v),
          ),
          const SizedBox(height: 14),
          Text(
            S.tr('Motif du mouvement', 'Movement reason'),
            style: TextStyle(
              color: p.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _motifs.length; i++)
                    SizedBox(
                      width: width,
                      child: _MotifTile(
                        motif: _motifs[i],
                        selected: i == _motifIndex,
                        onTap: () => setState(() => _motifIndex = i),
                      ),
                    ),
                ],
              );
            },
          ),
          if (motif.sign == 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  S.tr('Direction', 'Direction'),
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: Text(S.tr('Ajouter', 'Add')),
                  selected: _adjustSign == 1,
                  onSelected: (_) => setState(() => _adjustSign = 1),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(S.tr('Retirer', 'Remove')),
                  selected: _adjustSign == -1,
                  onSelected: (_) => setState(() => _adjustSign = -1),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: S.tr('Quantité', 'Quantity'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _commentCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: S.tr('Commentaire (optionnel)', 'Comment (optional)'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          // Aperçu avant/après — pas de faux succès : si la cible est
          // négative, la validation est bloquée.
          Builder(
            builder: (context) {
              final preview =
                  '${selected.stockQty.toStringAsFixed(0)} → '
                  '${target.toStringAsFixed(0)} ${selected.unit}';
              return Text(
                valid
                    ? preview
                    : '$preview · '
                          '${S.tr('blocé : stock négatif ou quantité invalide', 'blocked: negative stock or invalid quantity')}',
                style: TextStyle(
                  color: valid ? p.text : p.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // CTA violet maquette (« Valider le Mouvement de Stock »).
          DavexPressable(
            onTap: valid && !_saving
                ? () => _submit(selected, target, motif)
                : null,
            semanticLabel: S.tr(
              'Valider le mouvement de stock',
              'Confirm stock movement',
            ),
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: _violetGradient,
                borderRadius: BorderRadius.circular(LkColors.radiusMedium),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      S.tr(
                        'Valider le mouvement de stock',
                        'Confirm stock movement',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MotifTile extends StatelessWidget {
  const _MotifTile({
    required this.motif,
    required this.selected,
    required this.onTap,
  });

  final _Motif motif;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final signLabel = motif.sign > 0
        ? '+'
        : motif.sign < 0
        ? '−'
        : '±';
    final signColor = motif.sign > 0
        ? _gaugeSuccess
        : motif.sign < 0
        ? _gaugeDanger
        : _ctaViolet;
    return DavexPressable(
      onTap: onTap,
      semanticLabel: S.tr(motif.labelFr, motif.labelEn),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _ctaViolet.withValues(alpha: 0.10)
              : p.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _ctaViolet : p.borderControl,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              motif.icon,
              size: 17,
              color: selected ? _ctaViolet : p.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                S.tr(motif.labelFr, motif.labelEn),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: signColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                signLabel,
                style: TextStyle(
                  color: signColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
