import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../l10n/app_strings.dart';
import '../utils/money_format.dart';

enum ReceiptPaperSize { roll58, roll80, standardA4 }

class ThermalReceiptService {
  ThermalReceiptService._();

  /// Génère un document PDF pour un reçu de vente au format ticket ou A4.
  static Future<Uint8List> generateReceiptPdf({
    required String businessName,
    required String saleId,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String paymentMethod,
    DateTime? date,
    ReceiptPaperSize paperSize = ReceiptPaperSize.roll80,
  }) async {
    final pdf = pw.Document();
    final saleDate = date ?? DateTime.now();

    PdfPageFormat format;
    switch (paperSize) {
      case ReceiptPaperSize.roll58:
        format = const PdfPageFormat(
          58 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 4 * PdfPageFormat.mm,
        );
        break;
      case ReceiptPaperSize.roll80:
        format = const PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 5 * PdfPageFormat.mm,
        );
        break;
      case ReceiptPaperSize.standardA4:
        format = PdfPageFormat.a4;
        break;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Center(
                child: pw.Text(
                  businessName.toUpperCase(),
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: paperSize == ReceiptPaperSize.standardA4
                        ? 18
                        : 12,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  S.tr('TICKET DE CAISSE', 'SALES RECEIPT'),
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),
              pw.Text(
                '${S.tr('Réf', 'Ref')}: $saleId',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Date: ${saleDate.toLocal().toString().split('.')[0]}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                '${S.tr('Paiement', 'Payment')}: $paymentMethod',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    S.tr('Article', 'Item'),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 8,
                    ),
                  ),
                  pw.Text(
                    S.tr('Qté x Prix', 'Qty x Price'),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 8,
                    ),
                  ),
                  pw.Text(
                    'Total',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
              pw.Divider(thickness: 0.5),
              ...items.map((item) {
                final name = (item['name'] ?? 'Article').toString();
                final qty = (item['qty'] ?? 1) as num;
                final price = (item['price'] ?? 0.0) as num;
                final lineTotal = qty * price;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          name,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Text(
                        '$qty x ${MoneyFormat.format(price.toDouble())}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        MoneyFormat.format(lineTotal.toDouble()),
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL Net:',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  pw.Text(
                    MoneyFormat.format(totalAmount),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'Merci pour votre confiance !',
                  style: pw.TextStyle(
                    fontStyle: pw.FontStyle.italic,
                    fontSize: 8,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Imprime directement vers une imprimante thermique / Bluetooth via le sous-système Printing.
  static Future<void> printReceipt({
    required String businessName,
    required String saleId,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String paymentMethod,
    DateTime? date,
    ReceiptPaperSize paperSize = ReceiptPaperSize.roll80,
  }) async {
    final pdfBytes = await generateReceiptPdf(
      businessName: businessName,
      saleId: saleId,
      items: items,
      totalAmount: totalAmount,
      paymentMethod: paymentMethod,
      date: date,
      paperSize: paperSize,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'Ticket_$saleId',
    );
  }
}
