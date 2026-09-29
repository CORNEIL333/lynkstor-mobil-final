import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/billing/billing_engine.dart';
import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/permissions/permission_guard.dart';
import '../../core/permissions/permissions.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/utils/id_generator.dart';
import '../../core/logging/app_logger.dart';
import 'analytics_service.dart';
import 'automation_service.dart';

class CartLine {
  CartLine({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    this.unit = 'pièce',
    this.costPrice = 0,
    this.discount = 0,
    this.taxRate = 0,
    this.trackStock = true,
    this.availableStock = 0,
  });

  final String? productId;
  final String productName;
  final String unit;
  final double unitPrice;
  final double costPrice;
  double quantity;
  double discount;
  final double taxRate;
  final bool trackStock;
  final double availableStock;

  double get lineTotal => BillingEngine.roundFcfa(
    (unitPrice * quantity) - discount,
  );
}

class PaymentPart {
  PaymentPart({required this.method, required this.amount, this.methodRef});

  final String method;
  final double amount;
  final String? methodRef;
}

class CompleteSaleInput {
  CompleteSaleInput({
    required this.businessId,
    required this.lines,
    required this.payments,
    this.customerId,
    this.customerName,
    this.discount = 0,
    this.note,
    this.userId,
    this.deviceId,
    this.userRole = 'owner',
  });

  final String businessId;
  final List<CartLine> lines;
  final List<PaymentPart> payments;
  final String? customerId;
  final String? customerName;
  final double discount;
  final String? note;
  final String? userId;
  final String? deviceId;
  final String userRole;
}

class SaleService {
  SaleService({required this.db, required this.sync, this.automation});

  final AppDatabase db;
  final SyncEngine sync;
  final AutomationService? automation;

  Future<List<Sale>> list(String businessId, {DateTime? from, DateTime? to}) =>
      db.getSales(businessId, from: from, to: to);

  Future<Sale?> byId(String id) => db.getSale(id);

  Future<List<SaleItem>> items(String saleId) => db.getSaleItems(saleId);

  Future<String> billingJson(String saleId) => db.getSaleBillingJson(saleId);

  Future<List<SaleReturn>> listReturns(String businessId, {DateTime? from, DateTime? to}) =>
      db.getSaleReturns(businessId, from: from, to: to);

  Future<SaleReturn?> returnById(String id) => db.getSaleReturn(id);

  Future<List<SaleReturnItem>> returnItems(String returnId) => db.getSaleReturnItems(returnId);

  Future<void> linkAdHocItems({
    required String saleId,
    required String productId,
    required String productName,
  }) async {
    await (db.update(db.saleItems)..where(
          (t) =>
              t.saleId.equals(saleId) &
              t.productId.isNull() &
              t.productName.equals(productName),
        ))
        .write(SaleItemsCompanion(productId: Value(productId)));
  }

  /// Valide une vente dans une transaction locale atomique.
  /// Une vente validée ne disparaît jamais — écriture avant succès UI.
  Future<Sale> completeSale(CompleteSaleInput input) async {
    PermissionGuard.of(input.userRole).require(AppPermission.salesCreate);
    if (input.businessId.trim().isEmpty) {
      throw const ValidationException('Commerce invalide.');
    }
    if (input.lines.isEmpty) {
      throw const ValidationException('Ajoutez au moins un article.');
    }
    if (!input.discount.isFinite || input.discount < 0) {
      throw const ValidationException('La remise globale est invalide.');
    }
    for (final line in input.lines) {
      if ((line.productId != null && line.productId!.trim().isEmpty) ||
          line.productName.trim().isEmpty) {
        throw const ValidationException('Un article de la vente est invalide.');
      }
      if (!line.quantity.isFinite || line.quantity <= 0) {
        throw ValidationException(
          'La quantité de « ${line.productName} » doit être positive.',
        );
      }
      if (!line.unitPrice.isFinite ||
          line.unitPrice < 0 ||
          !line.costPrice.isFinite ||
          line.costPrice < 0) {
        throw ValidationException(
          'Le prix de « ${line.productName} » est invalide.',
        );
      }
      final gross = line.unitPrice * line.quantity;
      if (!line.discount.isFinite ||
          line.discount < 0 ||
          line.discount > gross) {
        throw ValidationException(
          'La remise de « ${line.productName} » est invalide.',
        );
      }
    }
    for (final payment in input.payments) {
      if (payment.method.trim().isEmpty ||
          !payment.amount.isFinite ||
          payment.amount < 0) {
        throw const ValidationException('Un paiement est invalide.');
      }
      if (payment.method == 'credit' && payment.amount != 0) {
        throw const ValidationException(
          'Un paiement à crédit ne doit pas contenir de montant encaissé.',
        );
      }
    }

    final resolvedRates = <String, double>{};
    for (final line in input.lines) {
      final id = line.productId;
      if (id == null || line.taxRate > 0) continue;
      resolvedRates[id] = await db.productTaxRate(id);
    }
    final InvoiceComputation billing;
    try {
      billing = BillingEngine.compute(
        lines: [
          for (final line in input.lines)
            BillingLineInput(
              productId: line.productId,
              productName: line.productName,
              unit: line.unit,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
              discount: line.discount,
              taxRate: line.taxRate > 0
                  ? line.taxRate
                  : resolvedRates[line.productId] ?? 0,
              costPrice: line.costPrice,
              trackStock: line.trackStock,
            ),
        ],
        globalDiscount: input.discount,
        payments: [
          for (final p in input.payments)
            BillingPaymentInput(
              method: p.method,
              amount: p.amount,
              reference: p.methodRef,
            ),
        ],
      );
    } on ArgumentError catch (error) {
      throw ValidationException(error.message ?? 'Facture invalide.');
    }
    if (!billing.isBalanced) {
      throw const ValidationException(
        'Écriture comptable non équilibrée. La vente a été refusée.',
      );
    }
    final subtotal = billing.subtotalHt;
    final total = billing.totalTtc;
    final amountPaid = billing.amountPaid;
    final amountDue = billing.amountDue;
    final change = billing.changeGiven;

    // Crédit sans client interdit
    if (amountDue > 0 &&
        (input.customerId == null || input.customerId!.isEmpty)) {
      throw const ValidationException(
        'Sélectionnez un client pour une vente à crédit ou un paiement partiel.',
      );
    }

    // Agrège les doublons afin que deux lignes du même produit ne puissent
    // jamais contourner la vérification du stock.
    final requestedStock = <String, double>{};
    for (final line in input.lines) {
      final productId = line.productId;
      if (productId == null || !line.trackStock) continue;
      requestedStock.update(
        productId,
        (quantity) => quantity + line.quantity,
        ifAbsent: () => line.quantity,
      );
    }

    if (input.customerId != null && input.customerId!.isNotEmpty) {
      final customer = await db.getCustomer(input.customerId!);
      if (customer == null || customer.businessId != input.businessId) {
        throw const ValidationException(
          'Le client sélectionné n’appartient pas à ce commerce.',
        );
      }
      if (amountDue > 0 &&
          customer.creditLimit > 0 &&
          customer.balance + amountDue > customer.creditLimit) {
        throw ValidationException(
          'Limite de crédit dépassée pour ${customer.name} '
          '(limite : ${customer.creditLimit.toStringAsFixed(0)}, '
          'solde : ${customer.balance.toStringAsFixed(0)}).',
        );
      }
    }

    final now = DateTime.now();
    final saleId = IdGenerator.uuid();
    final reference = IdGenerator.businessRef('VTE');
    final idempotencyKey = IdGenerator.uuid();

    await db.transaction(() async {
      final productsById = <String, Product>{};
      for (final entry in requestedStock.entries) {
        final product = await db.getProduct(entry.key);
        if (product == null || product.businessId != input.businessId) {
          throw const ValidationException(
            'Un produit n’appartient pas à ce commerce.',
          );
        }
        productsById[product.id] = product;
        if (product.trackStock && product.stockQty < entry.value) {
          final allowNegative = await db.allowNegativeStock(input.businessId);
          if (!allowNegative) {
            throw StockException(
              'Stock insuffisant pour « ${product.name} » '
              '(disponible : ${product.stockQty}, demandé : ${entry.value}).',
            );
          }
        }
      }

      await db
          .into(db.sales)
          .insertOnConflictUpdate(
            SalesCompanion.insert(
              id: saleId,
              businessId: input.businessId,
              reference: reference,
              customerId: Value(input.customerId),
              customerName: Value(
                (input.customerName != null &&
                        input.customerName!.trim().isNotEmpty)
                    ? input.customerName
                    : 'Client de passage',
              ),
              status: Value(billing.status == 'paid' || billing.status == 'partially_paid' || billing.status == 'unpaid'
                  ? 'completed'
                  : billing.status),
              subtotal: Value(subtotal),
              discount: Value(input.discount),
              total: Value(total.toDouble()),
              amountPaid: Value(amountPaid),
              amountDue: Value(amountDue.toDouble()),
              changeGiven: Value(change.toDouble()),
              paymentMethodsJson: Value(
                jsonEncode(
                  input.payments
                      .map(
                        (p) => {
                          'method': p.method,
                          'amount': p.amount,
                          if (p.methodRef != null) 'ref': p.methodRef,
                        },
                      )
                      .toList(),
                ),
              ),
              note: Value(input.note),
              userId: Value(input.userId),
              deviceId: Value(input.deviceId),
              soldAt: now,
              createdAt: now,
              updatedAt: now,
              idempotencyKey: idempotencyKey,
            ),
          );

      for (var i = 0; i < input.lines.length; i++) {
        final line = input.lines[i];
        final billed = billing.lines[i];
        final itemId = IdGenerator.uuid();
        await db
            .into(db.saleItems)
            .insertOnConflictUpdate(
              SaleItemsCompanion.insert(
                id: itemId,
                saleId: saleId,
                productId: Value(line.productId),
                productName: line.productName,
                unit: Value(line.unit),
                quantity: line.quantity,
                unitPrice: line.unitPrice,
                costPrice: Value(line.costPrice),
                discount: Value(line.discount),
                lineTotal: billed.lineTtc,
              ),
            );
        await db.updateSaleItemTax(
          itemId: itemId,
          taxRate: billed.taxRate,
          taxAmount: billed.taxAmount,
          lineHt: billed.lineHt,
        );

        final productId = line.productId;
        final product = productId == null
            ? null
            : productsById[productId] ?? await db.getProduct(productId);
        if (product != null && product.trackStock) {
          final before = product.stockQty;
          final after = before - line.quantity;
          await db
              .into(db.stockMovements)
              .insertOnConflictUpdate(
                StockMovementsCompanion.insert(
                  id: IdGenerator.uuid(),
                  businessId: input.businessId,
                  productId: product.id,
                  type: 'sale',
                  quantity: -line.quantity,
                  qtyBefore: before,
                  qtyAfter: after,
                  referenceType: const Value('sale'),
                  referenceId: Value(saleId),
                  userId: Value(input.userId),
                  createdAt: now,
                ),
              );
          await db.updateProductRow(
            product.copyWith(
              stockQty: after,
              updatedAt: now,
              version: product.version + 1,
            ),
          );
          productsById[product.id] = product.copyWith(
            stockQty: after,
            updatedAt: now,
            version: product.version + 1,
          );
        }
      }

      for (final part in input.payments) {
        if (part.amount <= 0) continue;
        if (part.method == 'credit') continue;
        await db
            .into(db.payments)
            .insertOnConflictUpdate(
              PaymentsCompanion.insert(
                id: IdGenerator.uuid(),
                businessId: input.businessId,
                reference: IdGenerator.businessRef('PAY'),
                type: 'sale',
                relatedType: const Value('sale'),
                relatedId: Value(saleId),
                customerId: Value(input.customerId),
                amount: part.amount,
                method: part.method,
                methodRef: Value(part.methodRef),
                userId: Value(input.userId),
                paidAt: now,
                createdAt: now,
                idempotencyKey: IdGenerator.uuid(),
              ),
            );
      }

      if (amountDue > 0 && input.customerId != null) {
        final customer = await db.getCustomer(input.customerId!);
        if (customer != null) {
          final newBalance = customer.balance + amountDue;
          await db
              .into(db.debtMovements)
              .insertOnConflictUpdate(
                DebtMovementsCompanion.insert(
                  id: IdGenerator.uuid(),
                  businessId: input.businessId,
                  customerId: customer.id,
                  type: 'credit_sale',
                  amount: amountDue.toDouble(),
                  balanceBefore: customer.balance,
                  balanceAfter: newBalance,
                  relatedType: const Value('sale'),
                  relatedId: Value(saleId),
                  userId: Value(input.userId),
                  createdAt: now,
                ),
              );
          await db.updateCustomerRow(
            customer.copyWith(
              balance: newBalance,
              lastActivityAt: Value(now),
              updatedAt: now,
              version: customer.version + 1,
            ),
          );
        }
      }

      await db.insertLedgerEntries(
        businessId: input.businessId,
        journalRef: reference,
        relatedType: 'sale',
        relatedId: saleId,
        entries: [
          for (final e in billing.ledger)
            {
              'accountCode': e.accountCode,
              'accountName': e.accountName,
              'debit': e.debit,
              'credit': e.credit,
              'memo': e.memo,
            },
        ],
        userId: input.userId,
        at: now,
      );

      await db.setSaleBillingJson(saleId, jsonEncode(billing.toJson()));

      await db.insertAudit(
        AuditLogsCompanion.insert(
          id: IdGenerator.uuid(),
          businessId: input.businessId,
          userId: Value(input.userId),
          deviceId: Value(input.deviceId),
          action: 'sale.completed',
          entityType: const Value('sale'),
          entityId: Value(saleId),
          detailsJson: Value(
            jsonEncode({
              'reference': reference,
              'total': total,
              'paid': amountPaid,
              'due': amountDue,
            }),
          ),
          createdAt: now,
        ),
      );
    });

    final syncedSale = await (db.select(
      db.sales,
    )..where((t) => t.id.equals(saleId))).getSingle();
    final syncedItems = await (db.select(
      db.saleItems,
    )..where((t) => t.saleId.equals(saleId))).get();
    final syncedPayments = await (db.select(
      db.payments,
    )..where((t) => t.relatedId.equals(saleId))).get();
    final syncedStockMovements = await (db.select(
      db.stockMovements,
    )..where((t) => t.referenceId.equals(saleId))).get();
    final syncedDebtMovements = await (db.select(
      db.debtMovements,
    )..where((t) => t.relatedId.equals(saleId))).get();
    final syncedProducts = <Product>[];
    for (final productId
        in syncedItems
            .map((item) => item.productId)
            .whereType<String>()
            .toSet()) {
      final product = await db.getProduct(productId);
      if (product != null) syncedProducts.add(product);
    }
    final syncedCustomer = input.customerId == null
        ? null
        : await db.getCustomer(input.customerId!);
    await sync.enqueue(
      businessId: input.businessId,
      entityType: 'sale',
      entityId: saleId,
      operation: 'create',
      payload: {
        'sale': syncedSale.toJson(),
        'items': syncedItems.map((row) => row.toJson()).toList(),
        'payments': syncedPayments.map((row) => row.toJson()).toList(),
        'stockMovements': syncedStockMovements
            .map((row) => row.toJson())
            .toList(),
        'debtMovements': syncedDebtMovements
            .map((row) => row.toJson())
            .toList(),
        'products': syncedProducts.map((row) => row.toJson()).toList(),
        if (syncedCustomer != null) 'customer': syncedCustomer.toJson(),
        'reference': reference,
        'total': total,
        'amountPaid': amountPaid,
        'amountDue': amountDue,
        'paymentMethods': input.payments.map((p) => p.method).toList(),
        'soldAt': now.toIso8601String(),
        'idempotencyKey': idempotencyKey,
        'version': syncedSale.version,
      },
      userId: input.userId,
      deviceId: input.deviceId,
    );

    AppLogger.audit('sale.completed', userId: input.userId, entityId: saleId);
    AppAnalytics.track(
      'sale.completed',
      properties: {
        'total': total,
        'items': input.lines.length,
        'credit': amountDue > 0,
      },
    );
    final automationService = automation;
    if (automationService != null) {
      for (final productId
          in input.lines
              .map((line) => line.productId)
              .whereType<String>()
              .toSet()) {
        await automationService.evaluateProductStock(
          businessId: input.businessId,
          productId: productId,
        );
      }
      for (final line in input.lines.where((line) => line.productId == null)) {
        await automationService.notifyAdHocProduct(
          businessId: input.businessId,
          saleId: saleId,
          productName: line.productName,
          unitPrice: line.unitPrice,
          unit: line.unit,
        );
      }
    }
    return (await db.getSale(saleId))!;
  }

  Future<SaleReturn> createReturn({
    required String businessId,
    required String saleId,
    required List<
      ({String? productId, String productName, double qty, double unitPrice})
    >
    lines,
    required String reason,
    required String refundMethod,
    bool restock = true,
    String? userId,
    String? authorizedBy,
    String userRole = 'owner',
  }) async {
    PermissionGuard.of(userRole).require(AppPermission.salesReturn);
    final sale = await db.getSale(saleId);
    if (sale == null) throw const NotFoundException('Vente introuvable.');
    if (sale.businessId != businessId) {
      throw const ValidationException(
        'Cette vente n’appartient pas à ce commerce.',
      );
    }
    if (sale.status == 'cancelled' || sale.status == 'returned') {
      throw const ValidationException(
        'Cette vente est déjà annulée ou entièrement retournée.',
      );
    }
    if (lines.isEmpty) {
      throw const ValidationException(
        'Sélectionnez au moins un article à retourner.',
      );
    }
    if (reason.trim().isEmpty) {
      throw const ValidationException('Le motif du retour est obligatoire.');
    }
    if (refundMethod != 'refund' && refundMethod != 'credit_note') {
      throw const ValidationException('Le type de compensation est invalide.');
    }

    final soldItems = await db.getSaleItems(saleId);
    final soldByProduct =
        <String, ({double qty, double amount, String name})>{};
    for (final item in soldItems) {
      final key = item.productId ?? 'name:${item.productName}';
      final existing = soldByProduct[key];
      soldByProduct[key] = (
        qty: (existing?.qty ?? 0) + item.quantity,
        amount: (existing?.amount ?? 0) + item.lineTotal,
        name: item.productName,
      );
    }

    final priorReturns =
        await (db.select(db.saleReturns)..where(
              (t) => t.saleId.equals(saleId) & t.status.equals('completed'),
            ))
            .get();
    final alreadyReturned = <String, double>{};
    var priorReturnTotal = 0.0;
    for (final prior in priorReturns) {
      priorReturnTotal += prior.total;
      final priorItems = await (db.select(
        db.saleReturnItems,
      )..where((t) => t.returnId.equals(prior.id))).get();
      for (final item in priorItems) {
        final key = item.productId ?? 'name:${item.productName}';
        alreadyReturned.update(
          key,
          (quantity) => quantity + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
    }

    final requested = <String, double>{};
    for (final line in lines) {
      if (!line.qty.isFinite ||
          line.qty <= 0 ||
          !line.unitPrice.isFinite ||
          line.unitPrice < 0) {
        throw const ValidationException(
          'Une quantité ou un prix de retour est invalide.',
        );
      }
      final key = line.productId ?? 'name:${line.productName}';
      final sold = soldByProduct[key];
      if (sold == null) {
        throw ValidationException(
          '« ${line.productName} » ne fait pas partie de cette vente.',
        );
      }
      requested.update(
        key,
        (quantity) => quantity + line.qty,
        ifAbsent: () => line.qty,
      );
    }

    for (final entry in requested.entries) {
      final sold = soldByProduct[entry.key]!;
      final remaining = sold.qty - (alreadyReturned[entry.key] ?? 0);
      if (entry.value > remaining + 0.000001) {
        throw ValidationException(
          'Quantité retournée trop élevée pour « ${sold.name} » '
          '(reste retournable : ${remaining.toStringAsFixed(2)}).',
        );
      }
    }

    final normalizedLines =
        <
          ({
            String? productId,
            String productName,
            double qty,
            double unitPrice,
          })
        >[];
    for (final line in lines) {
      final key = line.productId ?? 'name:${line.productName}';
      final sold = soldByProduct[key]!;
      normalizedLines.add((
        productId: line.productId,
        productName: sold.name,
        qty: line.qty,
        unitPrice: sold.qty == 0 ? 0 : sold.amount / sold.qty,
      ));
    }
    final total = normalizedLines.fold<double>(
      0,
      (s, l) => s + l.qty * l.unitPrice,
    );
    if (total <= 0 || priorReturnTotal + total > sale.total + 0.01) {
      throw const ValidationException(
        'Le montant du retour dépasse le montant remboursable de la vente.',
      );
    }
    final now = DateTime.now();
    final returnId = IdGenerator.uuid();
    final isFullReturn = priorReturnTotal + total >= sale.total - 0.01;

    await db.transaction(() async {
      await db
          .into(db.saleReturns)
          .insertOnConflictUpdate(
            SaleReturnsCompanion.insert(
              id: returnId,
              businessId: businessId,
              saleId: saleId,
              reference: IdGenerator.businessRef('RET'),
              reason: reason,
              total: total,
              refundMethod: refundMethod,
              restock: Value(restock),
              authorizedBy: Value(authorizedBy),
              userId: Value(userId),
              createdAt: now,
            ),
          );

      for (final line in normalizedLines) {
        await db
            .into(db.saleReturnItems)
            .insertOnConflictUpdate(
              SaleReturnItemsCompanion.insert(
                id: IdGenerator.uuid(),
                returnId: returnId,
                productId: Value(line.productId),
                productName: line.productName,
                quantity: line.qty,
                unitPrice: line.unitPrice,
                lineTotal: line.qty * line.unitPrice,
              ),
            );

        if (restock && line.productId != null) {
          final product = await db.getProduct(line.productId!);
          if (product != null && product.trackStock) {
            final after = product.stockQty + line.qty;
            await db
                .into(db.stockMovements)
                .insertOnConflictUpdate(
                  StockMovementsCompanion.insert(
                    id: IdGenerator.uuid(),
                    businessId: businessId,
                    productId: product.id,
                    type: 'return',
                    quantity: line.qty,
                    qtyBefore: product.stockQty,
                    qtyAfter: after,
                    referenceType: const Value('sale_return'),
                    referenceId: Value(returnId),
                    userId: Value(userId),
                    createdAt: now,
                  ),
                );
            await db.updateProductRow(
              product.copyWith(
                stockQty: after,
                updatedAt: now,
                version: product.version + 1,
              ),
            );
          }
        }
      }

      var debtReduction = 0.0;
      if (sale.customerId != null && sale.amountDue > priorReturnTotal) {
        final customer = await db.getCustomer(sale.customerId!);
        if (customer != null && customer.businessId == businessId) {
          final plannedReduction = total
              .clamp(0, sale.amountDue - priorReturnTotal)
              .toDouble();
          debtReduction = plannedReduction
              .clamp(0, customer.balance)
              .toDouble();
          if (debtReduction > 0) {
            final newBalance = customer.balance - debtReduction;
            await db
                .into(db.debtMovements)
                .insertOnConflictUpdate(
                  DebtMovementsCompanion.insert(
                    id: IdGenerator.uuid(),
                    businessId: businessId,
                    customerId: customer.id,
                    type: 'adjustment',
                    amount: -debtReduction,
                    balanceBefore: customer.balance,
                    balanceAfter: newBalance,
                    relatedType: const Value('sale_return'),
                    relatedId: Value(returnId),
                    note: const Value('Réduction de dette suite à un retour'),
                    userId: Value(userId),
                    createdAt: now,
                  ),
                );
            await db.updateCustomerRow(
              customer.copyWith(
                balance: newBalance,
                lastActivityAt: Value(now),
                updatedAt: now,
                version: customer.version + 1,
              ),
            );
          }
        }
      }

      final cashRefund = total - debtReduction;
      if (refundMethod == 'refund' && cashRefund > 0.001) {
        await db
            .into(db.payments)
            .insertOnConflictUpdate(
              PaymentsCompanion.insert(
                id: IdGenerator.uuid(),
                businessId: businessId,
                reference: IdGenerator.businessRef('RMB'),
                type: 'refund',
                relatedType: const Value('sale_return'),
                relatedId: Value(returnId),
                customerId: Value(sale.customerId),
                amount: cashRefund,
                method: 'refund',
                userId: Value(userId),
                paidAt: now,
                createdAt: now,
                idempotencyKey: IdGenerator.uuid(),
              ),
            );
      }

      final originalLedger = await db.ledgerFor(businessId: businessId, relatedId: saleId);
      if (originalLedger.isNotEmpty) {
        final factor = sale.total > 0 ? (total / sale.total) : 1.0;
        final reversed = BillingEngine.reverseProportion(
          original: [
            for (final e in originalLedger)
              LedgerPosting(
                accountCode: e['accountCode'] as String? ?? '',
                accountName: e['accountName'] as String? ?? '',
                debit: (e['debit'] as num?)?.toDouble() ?? 0,
                credit: (e['credit'] as num?)?.toDouble() ?? 0,
                memo: 'Avoir $returnId',
              ),
          ],
          factor: factor,
        );
        if (reversed.isNotEmpty) {
          await db.insertLedgerEntries(
            businessId: businessId,
            journalRef: IdGenerator.businessRef('AV'),
            relatedType: 'sale_return',
            relatedId: returnId,
            entries: [
              for (final e in reversed)
                {
                  'accountCode': e.accountCode,
                  'accountName': e.accountName,
                  'debit': e.debit,
                  'credit': e.credit,
                  'memo': e.memo,
                },
            ],
            userId: userId,
            at: now,
          );
        }
      }

      await (db.update(db.sales)..where((t) => t.id.equals(saleId))).write(
        SalesCompanion(
          status: Value(isFullReturn ? 'returned' : 'partially_returned'),
          updatedAt: Value(now),
          version: Value(sale.version + 1),
        ),
      );

      await db.insertAudit(
        AuditLogsCompanion.insert(
          id: IdGenerator.uuid(),
          businessId: businessId,
          userId: Value(userId),
          action: 'sale.returned',
          entityType: const Value('sale_return'),
          entityId: Value(returnId),
          detailsJson: Value(
            jsonEncode({'saleId': saleId, 'total': total, 'reason': reason}),
          ),
          createdAt: now,
        ),
      );
    });

    final syncedReturn = await (db.select(
      db.saleReturns,
    )..where((t) => t.id.equals(returnId))).getSingle();
    final syncedReturnItems = await (db.select(
      db.saleReturnItems,
    )..where((t) => t.returnId.equals(returnId))).get();
    final syncedReturnPayments = await (db.select(
      db.payments,
    )..where((t) => t.relatedId.equals(returnId))).get();
    final syncedReturnStock = await (db.select(
      db.stockMovements,
    )..where((t) => t.referenceId.equals(returnId))).get();
    final syncedReturnDebts = await (db.select(
      db.debtMovements,
    )..where((t) => t.relatedId.equals(returnId))).get();
    final syncedReturnProducts = <Product>[];
    for (final productId
        in syncedReturnItems
            .map((item) => item.productId)
            .whereType<String>()
            .toSet()) {
      final product = await db.getProduct(productId);
      if (product != null) syncedReturnProducts.add(product);
    }
    final syncedReturnedSale = await (db.select(
      db.sales,
    )..where((t) => t.id.equals(saleId))).getSingle();
    final syncedReturnCustomer = sale.customerId == null
        ? null
        : await db.getCustomer(sale.customerId!);
    await sync.enqueue(
      businessId: businessId,
      entityType: 'sale_return',
      entityId: returnId,
      operation: 'create',
      payload: {
        'saleReturn': syncedReturn.toJson(),
        'items': syncedReturnItems.map((row) => row.toJson()).toList(),
        'payments': syncedReturnPayments.map((row) => row.toJson()).toList(),
        'stockMovements': syncedReturnStock.map((row) => row.toJson()).toList(),
        'debtMovements': syncedReturnDebts.map((row) => row.toJson()).toList(),
        'products': syncedReturnProducts.map((row) => row.toJson()).toList(),
        'sale': syncedReturnedSale.toJson(),
        if (syncedReturnCustomer != null)
          'customer': syncedReturnCustomer.toJson(),
        'saleId': saleId,
        'total': total,
        'refundMethod': refundMethod,
        'restock': restock,
        'version': 1,
      },
      userId: userId,
    );
    final automationService = automation;
    if (automationService != null) {
      for (final productId
          in normalizedLines
              .map((line) => line.productId)
              .whereType<String>()
              .toSet()) {
        await automationService.evaluateProductStock(
          businessId: businessId,
          productId: productId,
        );
      }
    }

    return (await (db.select(
      db.saleReturns,
    )..where((t) => t.id.equals(returnId))).getSingle());
  }
}
