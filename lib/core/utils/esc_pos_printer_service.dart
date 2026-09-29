import 'package:flutter/services.dart';
import '../../l10n/app_strings.dart';
import 'money_format.dart';

enum EscPosPaperWidth { mm58, mm80 }

class BluetoothPrinterDevice {
  const BluetoothPrinterDevice({required this.name, required this.address});

  final String name;
  final String address;
}

/// Pilote et générateur de commandes RAW ESC/POS pour imprimantes thermiques Bluetooth / USB.
class EscPosPrinterService {
  EscPosPrinterService._();

  static const _channel = MethodChannel(
    'com.kumba.kumba_business/bluetooth_printer',
  );

  static Future<List<BluetoothPrinterDevice>> pairedDevices() async {
    final granted =
        await _channel.invokeMethod<bool>('requestPermission') ?? false;
    if (!granted) {
      throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: 'Permission Bluetooth refusée.',
      );
    }
    final raw = await _channel.invokeListMethod<dynamic>('pairedDevices');
    return (raw ?? const [])
        .whereType<Map>()
        .map(
          (value) => BluetoothPrinterDevice(
            name: value['name']?.toString() ?? 'Imprimante Bluetooth',
            address: value['address']?.toString() ?? '',
          ),
        )
        .where((device) => device.address.isNotEmpty)
        .toList(growable: false);
  }

  static Future<void> printToDevice({
    required BluetoothPrinterDevice device,
    required Uint8List bytes,
  }) async {
    await _channel.invokeMethod<void>('printBytes', {
      'address': device.address,
      'bytes': bytes,
    });
  }

  // Commandes de contrôle ESC/POS
  static const List<int> escInit = [0x1B, 0x40]; // Initialize printer
  static const List<int> escAlignLeft = [0x1B, 0x61, 0x00];
  static const List<int> escAlignCenter = [0x1B, 0x61, 0x01];
  static const List<int> escAlignRight = [0x1B, 0x61, 0x02];
  static const List<int> escBoldOn = [0x1B, 0x45, 0x01];
  static const List<int> escBoldOff = [0x1B, 0x45, 0x00];
  static const List<int> escLineFeed = [0x0A];
  static const List<int> escCutPaper = [0x1D, 0x56, 0x41, 0x03]; // Partial cut

  /// Génère un flux d'octets RAW ESC/POS prêt à être envoyé directement par Bluetooth SPP.
  static Uint8List buildRawReceipt({
    required String businessName,
    required String saleId,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String paymentMethod,
    DateTime? date,
    EscPosPaperWidth width = EscPosPaperWidth.mm80,
  }) {
    final bytes = <int>[];
    final cols = width == EscPosPaperWidth.mm58 ? 32 : 48;
    final lineDate = date ?? DateTime.now();

    void addText(String text, {List<int>? align, bool bold = false}) {
      if (align != null) bytes.addAll(align);
      if (bold) bytes.addAll(escBoldOn);
      bytes.addAll(text.codeUnits);
      if (bold) bytes.addAll(escBoldOff);
      bytes.addAll(escLineFeed);
    }

    void addDivider() {
      addText('-' * cols, align: escAlignLeft);
    }

    // Header
    bytes.addAll(escInit);
    addText(businessName.toUpperCase(), align: escAlignCenter, bold: true);
    addText(S.tr('TICKET DE CAISSE', 'SALES RECEIPT'), align: escAlignCenter);
    addDivider();

    // Infos vente
    addText('${S.tr('Réf', 'Ref')} : $saleId', align: escAlignLeft);
    addText(
      'Date: ${lineDate.toLocal().toString().split('.')[0]}',
      align: escAlignLeft,
    );
    addText(
      '${S.tr('Paiement', 'Payment')}: $paymentMethod',
      align: escAlignLeft,
    );
    addDivider();

    // En-tête tableau articles
    addText(
      S.tr(
        'Article                 Qté   Total',
        'Item                    Qty   Total',
      ),
      align: escAlignLeft,
      bold: true,
    );
    addDivider();

    // Lignes articles
    for (final item in items) {
      final name = (item['name'] ?? 'Article').toString();
      final qty = (item['qty'] ?? 1) as num;
      final price = (item['price'] ?? 0.0) as num;
      final lineTotal = qty * price;

      final formattedName = name.length > 20
          ? name.substring(0, 20)
          : name.padRight(20);
      final formattedQty = 'x${qty.toStringAsFixed(0)}'.padLeft(4);
      final formattedTotal = MoneyFormat.format(
        lineTotal.toDouble(),
      ).padLeft(10);

      addText(
        '$formattedName $formattedQty $formattedTotal',
        align: escAlignLeft,
      );
    }

    addDivider();
    addText(
      'TOTAL: ${MoneyFormat.format(totalAmount)}',
      align: escAlignRight,
      bold: true,
    );
    addText(' ', align: escAlignCenter);
    addText(
      S.tr('Merci de votre visite !', 'Thank you for your visit!'),
      align: escAlignCenter,
    );

    // Ejection & Coupe
    bytes.addAll(escLineFeed);
    bytes.addAll(escLineFeed);
    bytes.addAll(escCutPaper);

    return Uint8List.fromList(bytes);
  }
}
