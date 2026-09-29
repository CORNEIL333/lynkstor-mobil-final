import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/id_generator.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  InventorySession? _session;
  List<InventoryLine> _lines = [];
  List<Product> _products = [];
  bool _loading = true;
  final Map<String, TextEditingController> _counts = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final business = ref.read(sessionProvider).business!;
    final db = ref.read(databaseProvider);
    final open =
        await (db.select(db.inventorySessions)
              ..where(
                (t) =>
                    t.businessId.equals(business.id) & t.status.equals('open'),
              )
              ..limit(1))
            .getSingleOrNull();
    final products = await ref.read(productServiceProvider).list(business.id);
    final tracked = products
        .where((p) => p.trackStock && !p.isService)
        .toList();

    if (open != null) {
      final lines = await (db.select(
        db.inventoryLines,
      )..where((t) => t.sessionId.equals(open.id))).get();
      for (final l in lines) {
        _counts[l.productId] = TextEditingController(
          text: l.countedQty?.toStringAsFixed(0) ?? '',
        );
      }
      setState(() {
        _session = open;
        _lines = lines;
        _products = tracked;
        _loading = false;
      });
    } else {
      setState(() {
        _products = tracked;
        _loading = false;
      });
    }
  }

  Future<void> _start() async {
    final session = ref.read(sessionProvider);
    final business = session.business!;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final id = IdGenerator.uuid();

    await db
        .into(db.inventorySessions)
        .insert(
          InventorySessionsCompanion.insert(
            id: id,
            businessId: business.id,
            name: 'Inventaire ${now.day}/${now.month}/${now.year}',
            userId: Value(session.user?.id),
            startedAt: now,
          ),
        );

    final lines = <InventoryLine>[];
    for (final p in _products) {
      final lineId = IdGenerator.uuid();
      await db
          .into(db.inventoryLines)
          .insert(
            InventoryLinesCompanion.insert(
              id: lineId,
              sessionId: id,
              productId: p.id,
              expectedQty: p.stockQty,
            ),
          );
      _counts[p.id] = TextEditingController();
      lines.add(
        InventoryLine(
          id: lineId,
          sessionId: id,
          productId: p.id,
          expectedQty: p.stockQty,
          countedQty: null,
          note: null,
          photoPath: null,
          countedAt: null,
        ),
      );
    }

    final s = await (db.select(
      db.inventorySessions,
    )..where((t) => t.id.equals(id))).getSingle();
    await ref
        .read(syncEngineProvider)
        .enqueue(
          businessId: business.id,
          entityType: 'inventory',
          entityId: id,
          operation: 'create',
          payload: {
            'session': s.toJson(),
            'lines': lines.map((row) => row.toJson()).toList(),
          },
          userId: session.user?.id,
        );
    setState(() {
      _session = s;
      _lines = lines;
    });
  }

  Future<void> _saveCount(String productId, String lineId) async {
    final raw = _counts[productId]?.text ?? '';
    final qty = double.tryParse(raw.replaceAll(',', '.'));
    if (qty == null) return;
    final db = ref.read(databaseProvider);
    await (db.update(
      db.inventoryLines,
    )..where((t) => t.id.equals(lineId))).write(
      InventoryLinesCompanion(
        countedQty: Value(qty),
        countedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _validate() async {
    if (_session == null) return;
    final session = ref.read(sessionProvider);
    final db = ref.read(databaseProvider);

    for (final line in _lines) {
      await _saveCount(line.productId, line.id);
    }

    final lines = await (db.select(
      db.inventoryLines,
    )..where((t) => t.sessionId.equals(_session!.id))).get();
    for (final line in lines) {
      if (line.countedQty == null) continue;
      final product = await db.getProduct(line.productId);
      if (product == null) continue;
      if (line.countedQty != product.stockQty) {
        await ref
            .read(productServiceProvider)
            .adjustStock(
              businessId: session.business!.id,
              productId: product.id,
              newQty: line.countedQty!,
              reason: 'Inventaire ${_session!.name}',
              userId: session.user?.id,
              type: 'inventory',
              userRole: session.role,
            );
      }
    }

    await (db.update(
      db.inventorySessions,
    )..where((t) => t.id.equals(_session!.id))).write(
      InventorySessionsCompanion(
        status: const Value('validated'),
        validatedAt: Value(DateTime.now()),
        submittedAt: Value(DateTime.now()),
      ),
    );
    final validated = await (db.select(
      db.inventorySessions,
    )..where((row) => row.id.equals(_session!.id))).getSingle();
    final validatedLines = await (db.select(
      db.inventoryLines,
    )..where((row) => row.sessionId.equals(_session!.id))).get();
    await ref
        .read(syncEngineProvider)
        .enqueue(
          businessId: session.business!.id,
          entityType: 'inventory',
          entityId: _session!.id,
          operation: 'update',
          payload: {
            'session': validated.toJson(),
            'lines': validatedLines.map((row) => row.toJson()).toList(),
          },
          userId: session.user?.id,
        );

    if (mounted) {
      showLkToast(
        context,
        'Inventaire validé — stock ajusté avec mouvements tracés.',
        tone: LkToastTone.success,
        icon: Icons.check_circle_outline,
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: KumbaLoading());

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Inventaire', 'Inventory'))),
      body: _session == null
          ? KumbaEmptyState(
              title: 'Aucun inventaire en cours',
              subtitle:
                  'Comptez vos produits, même hors ligne. Les écarts ajustent le stock à la validation.',
              icon: Icons.fact_check_outlined,
              actionLabel: 'Démarrer un inventaire',
              onAction: _start,
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _session!.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final line = _lines[i];
                      final product = _products.cast<Product?>().firstWhere(
                        (p) => p?.id == line.productId,
                        orElse: () => null,
                      );
                      final name = product?.name ?? line.productId;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                          side: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        title: Text(name),
                        subtitle: Text(
                          _session!.blindMode
                              ? 'Saisie aveugle'
                              : 'Système : ${line.expectedQty.toStringAsFixed(0)}',
                        ),
                        trailing: SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _counts[line.productId],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              hintText: '0',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                            onChanged: (_) =>
                                _saveCount(line.productId, line.id),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: KumbaButton(
                    label: 'Valider et ajuster le stock',
                    icon: Icons.verified_outlined,
                    onPressed: _validate,
                  ),
                ),
              ],
            ),
    );
  }
}
