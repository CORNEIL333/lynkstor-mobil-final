/// Moteur unique de facturation — source de vérité pour HT, TVA, TTC, paiements.
///
/// Choix métier (voir docs/BILLING_ENGINE.md) — ne pas recalculer ailleurs :
/// - Arrondi : à l’unité FCFA la plus proche, **au niveau de chaque ligne**
///   puis somme (jamais d’arrondi seulement en fin de facture).
/// - Prix catalogue = TTC affiché (`pricesIncludeTax: true` par défaut) pour
///   ne pas gonfler les prix existants de +19,25 %.
/// - Remise ligne d’abord (sur le TTC de ligne), puis remise globale répartie
///   au **prorata du TTC** après remises ligne. La remise globale réduit donc
///   la base taxable. Ensuite extraction HT / taxe (prix TTC) ou application
///   de la taxe (prix HT).
/// - Coût de revient : figé à la vente (`costPrice` de la ligne), pas de
///   CMUP/FIFO live tant que le métier n’a pas tranché.
library;

class BillingLineInput {
  const BillingLineInput({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.productId,
    this.unit = 'pièce',
    this.discount = 0,
    this.taxRate = 0,
    this.costPrice = 0,
    this.trackStock = true,
  });

  final String? productId;
  final String productName;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double taxRate;
  final double costPrice;
  final bool trackStock;
}

class BillingPaymentInput {
  const BillingPaymentInput({
    required this.method,
    required this.amount,
    this.reference,
  });

  final String method;
  final double amount;
  final String? reference;
}

class BillingLineResult {
  const BillingLineResult({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitPriceTtc,
    required this.unitPriceHt,
    required this.discount,
    required this.lineHt,
    required this.taxRate,
    required this.taxAmount,
    required this.lineTtc,
    required this.costPrice,
    required this.trackStock,
  });

  final String? productId;
  final String productName;
  final String unit;
  final double quantity;
  final double unitPriceTtc;
  final double unitPriceHt;
  final double discount;
  final double lineHt;
  final double taxRate;
  final double taxAmount;
  final double lineTtc;
  final double costPrice;
  final bool trackStock;

  Map<String, Object?> toJson() => {
    'productId': productId,
    'productName': productName,
    'unit': unit,
    'quantity': quantity,
    'unitPriceTtc': unitPriceTtc,
    'unitPriceHt': unitPriceHt,
    'discount': discount,
    'lineHt': lineHt,
    'taxRate': taxRate,
    'taxAmount': taxAmount,
    'lineTtc': lineTtc,
    'costPrice': costPrice,
    'trackStock': trackStock,
  };

  factory BillingLineResult.fromJson(Map<String, dynamic> json) {
    return BillingLineResult(
      productId: json['productId'] as String?,
      productName: json['productName'] as String? ?? '',
      unit: json['unit'] as String? ?? 'pièce',
      quantity: _asDouble(json['quantity']),
      unitPriceTtc: _asDouble(json['unitPriceTtc']),
      unitPriceHt: _asDouble(json['unitPriceHt']),
      discount: _asDouble(json['discount']),
      lineHt: _asDouble(json['lineHt']),
      taxRate: _asDouble(json['taxRate']),
      taxAmount: _asDouble(json['taxAmount']),
      lineTtc: _asDouble(json['lineTtc']),
      costPrice: _asDouble(json['costPrice']),
      trackStock: json['trackStock'] == true,
    );
  }
}

class TaxBucket {
  const TaxBucket({
    required this.rate,
    required this.baseHt,
    required this.taxAmount,
  });

  final double rate;
  final double baseHt;
  final double taxAmount;
}

class LedgerPosting {
  const LedgerPosting({
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    this.memo,
  });

  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;
  final String? memo;
}

class InvoiceComputation {
  const InvoiceComputation({
    required this.lines,
    required this.subtotalHt,
    required this.lineDiscounts,
    required this.globalDiscount,
    required this.taxTotal,
    required this.taxBuckets,
    required this.totalTtc,
    required this.amountPaid,
    required this.amountDue,
    required this.changeGiven,
    required this.status,
    required this.ledger,
  });

  final List<BillingLineResult> lines;
  final double subtotalHt;
  final double lineDiscounts;
  final double globalDiscount;
  final double taxTotal;
  final List<TaxBucket> taxBuckets;
  final double totalTtc;
  final double amountPaid;
  final double amountDue;
  final double changeGiven;
  final String status;
  final List<LedgerPosting> ledger;

  bool get isBalanced {
    final debit = ledger.fold<double>(0, (s, e) => s + e.debit);
    final credit = ledger.fold<double>(0, (s, e) => s + e.credit);
    return BillingEngine.roundFcfa(debit - credit).abs() < 0.5;
  }

  Map<String, Object?> toJson() => {
    'subtotalHt': subtotalHt,
    'lineDiscounts': lineDiscounts,
    'globalDiscount': globalDiscount,
    'taxTotal': taxTotal,
    'totalTtc': totalTtc,
    'amountPaid': amountPaid,
    'amountDue': amountDue,
    'changeGiven': changeGiven,
    'status': status,
    'taxBuckets': [
      for (final b in taxBuckets)
        {'rate': b.rate, 'baseHt': b.baseHt, 'taxAmount': b.taxAmount},
    ],
    'lines': [for (final l in lines) l.toJson()],
    'ledger': [
      for (final e in ledger)
        {
          'accountCode': e.accountCode,
          'accountName': e.accountName,
          'debit': e.debit,
          'credit': e.credit,
          'memo': e.memo,
        },
    ],
  };

  factory InvoiceComputation.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] as List? ?? const [];
    final lines = [
      for (final raw in rawLines)
        BillingLineResult.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
    final rawBuckets = json['taxBuckets'] as List? ?? const [];
    final buckets = [
      for (final raw in rawBuckets)
        TaxBucket(
          rate: _asDouble((raw as Map)['rate']),
          baseHt: _asDouble(raw['baseHt']),
          taxAmount: _asDouble(raw['taxAmount']),
        ),
    ];
    final rawLedger = json['ledger'] as List? ?? const [];
    final ledger = [
      for (final raw in rawLedger)
        LedgerPosting(
          accountCode: (raw as Map)['accountCode'] as String? ?? '',
          accountName: raw['accountName'] as String? ?? '',
          debit: _asDouble(raw['debit']),
          credit: _asDouble(raw['credit']),
          memo: raw['memo'] as String?,
        ),
    ];
    return InvoiceComputation(
      lines: lines,
      subtotalHt: _asDouble(json['subtotalHt']),
      lineDiscounts: _asDouble(json['lineDiscounts']),
      globalDiscount: _asDouble(json['globalDiscount']),
      taxTotal: _asDouble(json['taxTotal']),
      taxBuckets: buckets,
      totalTtc: _asDouble(json['totalTtc']),
      amountPaid: _asDouble(json['amountPaid']),
      amountDue: _asDouble(json['amountDue']),
      changeGiven: _asDouble(json['changeGiven']),
      status: json['status'] as String? ?? 'paid',
      ledger: ledger,
    );
  }

  InvoiceComputation copyWith({
    double? amountPaid,
    double? amountDue,
    double? changeGiven,
    String? status,
    List<LedgerPosting>? ledger,
  }) {
    return InvoiceComputation(
      lines: lines,
      subtotalHt: subtotalHt,
      lineDiscounts: lineDiscounts,
      globalDiscount: globalDiscount,
      taxTotal: taxTotal,
      taxBuckets: taxBuckets,
      totalTtc: totalTtc,
      amountPaid: amountPaid ?? this.amountPaid,
      amountDue: amountDue ?? this.amountDue,
      changeGiven: changeGiven ?? this.changeGiven,
      status: status ?? this.status,
      ledger: ledger ?? this.ledger,
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

class BillingEngine {
  BillingEngine._();

  /// Prix saisi = TTC affiché au client (usage boutiques Afrique de l’Ouest).
  static const bool defaultPricesIncludeTax = true;

  static double roundFcfa(num value) {
    if (!value.isFinite) return 0;
    return value.roundToDouble();
  }

  static InvoiceComputation compute({
    required List<BillingLineInput> lines,
    double globalDiscount = 0,
    List<BillingPaymentInput> payments = const [],
    bool pricesIncludeTax = defaultPricesIncludeTax,
  }) {
    if (lines.isEmpty) {
      throw ArgumentError('Une facture doit contenir au moins une ligne.');
    }
    if (!globalDiscount.isFinite || globalDiscount < 0) {
      throw ArgumentError('La remise globale est invalide.');
    }

    final raw = <_MutableLine>[];
    for (final line in lines) {
      if (!line.quantity.isFinite || line.quantity <= 0) {
        throw ArgumentError('Quantité invalide pour « ${line.productName} ».');
      }
      if (!line.unitPrice.isFinite || line.unitPrice < 0) {
        throw ArgumentError('Prix invalide pour « ${line.productName} ».');
      }
      if (!line.discount.isFinite || line.discount < 0) {
        throw ArgumentError('Remise invalide pour « ${line.productName} ».');
      }
      if (!line.taxRate.isFinite || line.taxRate < 0 || line.taxRate > 100) {
        throw ArgumentError(
          'Taux de taxe invalide pour « ${line.productName} ».',
        );
      }
      final rate = line.taxRate > 1 ? line.taxRate / 100 : line.taxRate;
      final grossTtc = roundFcfa(line.unitPrice * line.quantity);
      if (line.discount > grossTtc) {
        throw ArgumentError(
          'La remise de « ${line.productName} » dépasse le total de ligne.',
        );
      }
      final afterLineDiscount = roundFcfa(grossTtc - line.discount);
      raw.add(
        _MutableLine(
          input: BillingLineInput(
            productId: line.productId,
            productName: line.productName,
            unit: line.unit,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            discount: line.discount,
            taxRate: rate,
            costPrice: line.costPrice,
            trackStock: line.trackStock,
          ),
          ttcAfterLineDiscount: afterLineDiscount,
          lineDiscount: roundFcfa(line.discount),
        ),
      );
    }

    final ttcAfterLines = raw.fold<double>(
      0,
      (s, l) => s + l.ttcAfterLineDiscount,
    );
    final global = roundFcfa(globalDiscount);
    if (global > ttcAfterLines) {
      throw ArgumentError('La remise globale dépasse le sous-total.');
    }

    // Répartition de la remise globale au prorata du TTC après remise ligne.
    var allocated = 0.0;
    for (var i = 0; i < raw.length; i++) {
      final share = ttcAfterLines == 0
          ? 0.0
          : roundFcfa(global * raw[i].ttcAfterLineDiscount / ttcAfterLines);
      raw[i].globalShare = i == raw.length - 1
          ? roundFcfa(global - allocated)
          : share;
      allocated += raw[i].globalShare;
      raw[i].ttcNet = roundFcfa(
        raw[i].ttcAfterLineDiscount - raw[i].globalShare,
      );
      final rate = raw[i].input.taxRate;
      if (pricesIncludeTax && rate > 0) {
        raw[i].ht = roundFcfa(raw[i].ttcNet / (1 + rate));
        raw[i].tax = roundFcfa(raw[i].ttcNet - raw[i].ht);
      } else if (!pricesIncludeTax && rate > 0) {
        raw[i].ht = raw[i].ttcNet;
        raw[i].tax = roundFcfa(raw[i].ht * rate);
        raw[i].ttcNet = roundFcfa(raw[i].ht + raw[i].tax);
      } else {
        raw[i].ht = raw[i].ttcNet;
        raw[i].tax = 0;
      }
    }

    final results = <BillingLineResult>[
      for (final line in raw)
        BillingLineResult(
          productId: line.input.productId,
          productName: line.input.productName,
          unit: line.input.unit,
          quantity: line.input.quantity,
          unitPriceTtc: roundFcfa(line.input.unitPrice),
          unitPriceHt: line.input.quantity == 0
              ? 0
              : roundFcfa(line.ht / line.input.quantity),
          discount: line.lineDiscount,
          lineHt: line.ht,
          taxRate: line.input.taxRate,
          taxAmount: line.tax,
          lineTtc: line.ttcNet,
          costPrice: roundFcfa(line.input.costPrice),
          trackStock: line.input.trackStock,
        ),
    ];

    final subtotalHt = results.fold<double>(0, (s, l) => s + l.lineHt);
    final taxTotal = results.fold<double>(0, (s, l) => s + l.taxAmount);
    final totalTtc = results.fold<double>(0, (s, l) => s + l.lineTtc);
    final lineDiscounts = raw.fold<double>(0, (s, l) => s + l.lineDiscount);

    final buckets = <double, TaxBucket>{};
    for (final line in results) {
      final existing = buckets[line.taxRate];
      buckets[line.taxRate] = TaxBucket(
        rate: line.taxRate,
        baseHt: roundFcfa((existing?.baseHt ?? 0) + line.lineHt),
        taxAmount: roundFcfa((existing?.taxAmount ?? 0) + line.taxAmount),
      );
    }

    var amountPaid = 0.0;
    for (final payment in payments) {
      if (payment.method == 'credit') continue;
      if (!payment.amount.isFinite || payment.amount < 0) {
        throw ArgumentError('Paiement invalide.');
      }
      amountPaid = roundFcfa(amountPaid + payment.amount);
    }
    final amountDue = roundFcfa(
      (totalTtc - amountPaid).clamp(0, double.infinity),
    );
    final changeGiven = roundFcfa(
      (amountPaid - totalTtc).clamp(0, double.infinity),
    );
    final status = deriveStatus(
      totalTtc: totalTtc,
      amountPaid: amountPaid,
      amountDue: amountDue,
    );

    final ledger = buildLedger(
      totalHt: subtotalHt,
      taxTotal: taxTotal,
      totalTtc: totalTtc,
      amountPaid: amountPaid,
      amountDue: amountDue,
      payments: payments,
    );

    return InvoiceComputation(
      lines: results,
      subtotalHt: subtotalHt,
      lineDiscounts: lineDiscounts,
      globalDiscount: global,
      taxTotal: taxTotal,
      taxBuckets: buckets.values.toList()
        ..sort((a, b) => b.rate.compareTo(a.rate)),
      totalTtc: totalTtc,
      amountPaid: amountPaid,
      amountDue: amountDue,
      changeGiven: changeGiven,
      status: status,
      ledger: ledger,
    );
  }

  static String deriveStatus({
    required double totalTtc,
    required double amountPaid,
    required double amountDue,
    bool cancelled = false,
    bool credited = false,
  }) {
    if (cancelled) return 'cancelled';
    if (credited) return 'credited';
    if (amountDue <= 0 && amountPaid >= totalTtc) return 'paid';
    if (amountPaid > 0 && amountDue > 0) return 'partially_paid';
    if (amountPaid <= 0 && amountDue > 0) return 'unpaid';
    return 'paid';
  }

  static List<LedgerPosting> buildLedger({
    required double totalHt,
    required double taxTotal,
    required double totalTtc,
    required double amountPaid,
    required double amountDue,
    required List<BillingPaymentInput> payments,
  }) {
    final postings = <LedgerPosting>[];
    void add({
      required String code,
      required String name,
      double debit = 0,
      double credit = 0,
      String? memo,
    }) {
      final d = roundFcfa(debit);
      final c = roundFcfa(credit);
      if (d == 0 && c == 0) return;
      postings.add(
        LedgerPosting(
          accountCode: code,
          accountName: name,
          debit: d,
          credit: c,
          memo: memo,
        ),
      );
    }

    add(code: '701', name: 'Ventes HT', credit: totalHt);
    add(code: '443', name: 'TVA collectée', credit: taxTotal);

    for (final payment in payments) {
      if (payment.method == 'credit' || payment.amount <= 0) continue;
      final account = switch (payment.method) {
        'mtn_momo' || 'orange_money' => (
          '572',
          'Mobile Money',
        ),
        'transfer' || 'card' => ('512', 'Banque'),
        _ => ('570', 'Caisse'),
      };
      add(
        code: account.$1,
        name: account.$2,
        debit: payment.amount,
        memo: payment.method,
      );
    }
    add(code: '411', name: 'Clients', debit: amountDue);

    final debit = postings.fold<double>(0, (s, e) => s + e.debit);
    final credit = postings.fold<double>(0, (s, e) => s + e.credit);
    final gap = roundFcfa(credit - debit);
    if (gap.abs() >= 0.5) {
      add(
        code: '658',
        name: 'Écart d’arrondi',
        debit: gap > 0 ? gap : 0,
        credit: gap < 0 ? -gap : 0,
      );
    }
    return postings;
  }

  static List<LedgerPosting> reverse(List<LedgerPosting> original) {
    return [
      for (final e in original)
        LedgerPosting(
          accountCode: e.accountCode,
          accountName: e.accountName,
          debit: e.credit,
          credit: e.debit,
          memo: e.memo == null
              ? 'Contre-passation'
              : 'Contre-passation ${e.memo}',
        ),
    ];
  }

  /// Contre-passation d’un avoir partiel (facteur 0–1), avec rééquilibrage.
  static List<LedgerPosting> reverseProportion({
    required List<LedgerPosting> original,
    required double factor,
  }) {
    final clamped = factor.clamp(0, 1).toDouble();
    if (clamped <= 0) return const [];
    if (clamped >= 1) return reverse(original);
    final scaled = [
      for (final e in reverse(original))
        LedgerPosting(
          accountCode: e.accountCode,
          accountName: e.accountName,
          debit: roundFcfa(e.debit * clamped),
          credit: roundFcfa(e.credit * clamped),
          memo: e.memo,
        ),
    ];
    final debit = scaled.fold<double>(0, (s, e) => s + e.debit);
    final credit = scaled.fold<double>(0, (s, e) => s + e.credit);
    final gap = roundFcfa(debit - credit);
    if (gap.abs() < 0.5) return scaled;
    return [
      ...scaled,
      LedgerPosting(
        accountCode: '658',
        accountName: 'Écart d’arrondi',
        debit: gap < 0 ? -gap : 0,
        credit: gap > 0 ? gap : 0,
        memo: 'Équilibrage avoir partiel',
      ),
    ];
  }

  static List<LedgerPosting> buildDebtCollectionLedger({
    required double amount,
    required String method,
  }) {
    final rounded = roundFcfa(amount);
    if (rounded <= 0) return const [];
    final account = switch (method) {
      'mtn_momo' || 'orange_money' => ('572', 'Mobile Money'),
      'transfer' || 'card' => ('512', 'Banque'),
      _ => ('570', 'Caisse'),
    };
    return [
      LedgerPosting(
        accountCode: account.$1,
        accountName: account.$2,
        debit: rounded,
        credit: 0,
        memo: method,
      ),
      LedgerPosting(
        accountCode: '411',
        accountName: 'Clients',
        debit: 0,
        credit: rounded,
        memo: 'Encaissement créance',
      ),
    ];
  }

  /// Reconstruit une facture depuis le JSON persisté, ou depuis les lignes
  /// historiques si le JSON est absent (ventes antérieures au moteur).
  static InvoiceComputation hydrate({
    required Map<String, dynamic>? stored,
    required List<BillingLineInput> fallbackLines,
    double globalDiscount = 0,
    double amountPaid = 0,
  }) {
    if (stored != null &&
        stored['lines'] is List &&
        (stored['lines'] as List).isNotEmpty) {
      return InvoiceComputation.fromJson(stored);
    }
    return compute(
      lines: fallbackLines,
      globalDiscount: globalDiscount,
      payments: [
        if (amountPaid > 0)
          BillingPaymentInput(method: 'cash', amount: amountPaid),
      ],
    );
  }
}

class _MutableLine {
  _MutableLine({
    required this.input,
    required this.ttcAfterLineDiscount,
    required this.lineDiscount,
  });

  final BillingLineInput input;
  final double ttcAfterLineDiscount;
  final double lineDiscount;
  double globalShare = 0;
  double ttcNet = 0;
  double ht = 0;
  double tax = 0;
}

/// Mise en page lisible du reçu (source unique texte / UI / thermique).
class ReceiptLayout {
  ReceiptLayout._();

  static String plainText({
    required String businessName,
    required String reference,
    required DateTime soldAt,
    required InvoiceComputation invoice,
    String? customerName,
    String? cashierName,
    String? paymentSummary,
    String currency = 'FCFA',
    String? footer,
  }) {
    final buf = StringBuffer()
      ..writeln(businessName)
      ..writeln('Reçu $reference')
      ..writeln(_fmtDate(soldAt));
    if (cashierName != null && cashierName.trim().isNotEmpty) {
      buf.writeln('Caissier : ${cashierName.trim()}');
    }
    buf.writeln(
      'Client : ${customerName?.trim().isNotEmpty == true ? customerName!.trim() : 'Client de passage'}',
    );
    if (paymentSummary != null && paymentSummary.trim().isNotEmpty) {
      buf.writeln('Paiement : ${paymentSummary.trim()}');
    }
    buf.writeln('----------------------------');
    for (final line in invoice.lines) {
      for (final nameLine in wrapName(line.productName).split('\n')) {
        buf.writeln(nameLine);
      }
      buf.writeln(
        '  ${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)}'
        ' × ${_money(line.unitPriceTtc, currency)}'
        ' = ${_money(line.lineTtc, currency)}',
      );
      if (line.discount > 0) {
        buf.writeln('  Remise ligne : -${_money(line.discount, currency)}');
      }
    }
    buf.writeln('----------------------------');
    buf.writeln('Sous-total HT : ${_money(invoice.subtotalHt, currency)}');
    if (invoice.globalDiscount > 0) {
      buf.writeln('Remise       : -${_money(invoice.globalDiscount, currency)}');
    }
    if (invoice.taxTotal > 0) {
      for (final bucket in invoice.taxBuckets.where((b) => b.taxAmount > 0)) {
        final pct = (bucket.rate * 100).toStringAsFixed(
          bucket.rate * 100 % 1 == 0 ? 0 : 2,
        );
        buf.writeln('TVA $pct %    : ${_money(bucket.taxAmount, currency)}');
      }
    } else {
      buf.writeln('TVA          : ${_money(0, currency)} (exonéré)');
    }
    buf.writeln('Total TTC    : ${_money(invoice.totalTtc, currency)}');
    buf.writeln('Payé         : ${_money(invoice.amountPaid, currency)}');
    buf.writeln('Reste à payer: ${_money(invoice.amountDue, currency)}');
    if (invoice.changeGiven > 0) {
      buf.writeln('Monnaie      : ${_money(invoice.changeGiven, currency)}');
    }
    buf.writeln(
      footer?.trim().isNotEmpty == true
          ? footer!.trim()
          : 'Merci pour votre confiance.',
    );
    return buf.toString();
  }

  static String wrapName(String name, {int width = 32}) {
    if (name.length <= width) return name;
    final words = name.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if ('$current $word'.length <= width) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines.join('\n');
  }

  static String _money(double amount, String currency) {
    final n = amount.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      final fromEnd = n.length - i;
      if (i > 0 && fromEnd % 3 == 0) buf.write(' ');
      buf.write(n[i]);
    }
    return '$buf $currency';
  }

  static String _fmtDate(DateTime value) {
    final d = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}
