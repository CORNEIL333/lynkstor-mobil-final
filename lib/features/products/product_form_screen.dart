import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../shared/services/product_service.dart';
import '../../l10n/app_strings.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({
    super.key,
    this.productId,
    this.initialName,
    this.initialPrice,
    this.initialUnit,
    this.sourceSaleId,
    this.focusSupplier = false,
  });

  final String? productId;
  final String? initialName;
  final double? initialPrice;
  final String? initialUnit;
  final String? sourceSaleId;
  final bool focusSupplier;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _stock = TextEditingController(text: '0');
  final _barcode = TextEditingController();
  final _unit = TextEditingController(text: 'pièce');
  final _threshold = TextEditingController(text: '5');
  final _reorderQuantity = TextEditingController(text: '1');
  bool _isService = false;
  bool _loading = false;
  bool _initLoading = false;
  String? _error;
  String? _photoPath;
  String? _originalPhotoPath;
  bool _saved = false;
  List<Supplier> _suppliers = const [];
  String? _supplierId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _initLoading = true);
    final business = ref.read(sessionProvider).business;
    if (business == null) return;
    _suppliers = await ref.read(databaseProvider).getSuppliers(business.id);
    final p = widget.productId == null
        ? null
        : await ref.read(productServiceProvider).byId(widget.productId!);
    if (p != null) {
      _name.text = p.name;
      _price.text = p.salePrice.toStringAsFixed(0);
      _cost.text = p.costPrice.toStringAsFixed(0);
      _stock.text = p.stockQty.toStringAsFixed(0);
      _barcode.text = p.barcode ?? '';
      _unit.text = p.unit;
      _threshold.text = p.lowStockThreshold.toStringAsFixed(0);
      _isService = p.isService;
      _photoPath = p.photoPath;
      _originalPhotoPath = p.photoPath;
      final relation = await ref
          .read(automationServiceProvider)
          .preferredSupplier(p.id);
      _supplierId = relation?.supplierId;
      if (relation != null) {
        _reorderQuantity.text = relation.reorderQuantity.toStringAsFixed(0);
      }
    } else {
      _name.text = widget.initialName ?? '';
      if (widget.initialPrice != null) {
        _price.text = widget.initialPrice!.toStringAsFixed(0);
      }
      _unit.text = widget.initialUnit ?? S.tr('pièce', 'piece');
    }
    if (mounted) setState(() => _initLoading = false);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final business = ref.read(sessionProvider).business;
    if (business == null) return;
    try {
      final path = await ref
          .read(productImageServiceProvider)
          .pickAndPersist(businessId: business.id, source: source);
      if (path == null || !mounted) return;
      final replaced = _photoPath;
      setState(() => _photoPath = path);
      if (replaced != null && replaced != _originalPhotoPath) {
        await ref.read(productImageServiceProvider).deleteIfManaged(replaced);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Impossible d’ajouter la photo : $e');
      }
    }
  }

  Future<void> _choosePhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(S.tr('Prendre une photo', 'Take a photo')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                S.tr('Choisir dans la galerie', 'Choose from gallery'),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  @override
  void dispose() {
    final unsavedPhoto = _photoPath;
    if (!_saved && unsavedPhoto != null && unsavedPhoto != _originalPhotoPath) {
      unawaited(
        ref.read(productImageServiceProvider).deleteIfManaged(unsavedPhoto),
      );
    }
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    _barcode.dispose();
    _unit.dispose();
    _threshold.dispose();
    _reorderQuantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    final business = session.business;
    if (business == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final input = ProductInput(
        name: _name.text,
        salePrice: MoneyFormat.parse(_price.text) ?? 0,
        costPrice: MoneyFormat.parse(_cost.text) ?? 0,
        stockQty: MoneyFormat.parse(_stock.text) ?? 0,
        barcode: _barcode.text.isEmpty ? null : _barcode.text,
        unit: _unit.text.isEmpty ? 'pièce' : _unit.text,
        lowStockThreshold: MoneyFormat.parse(_threshold.text) ?? 5,
        isService: _isService,
        trackStock: !_isService,
        photoPath: _photoPath,
      );

      Product? savedProduct;
      if (widget.productId == null) {
        savedProduct = await ref
            .read(productServiceProvider)
            .create(
              business.id,
              input,
              userId: session.user?.id,
              userRole: session.role,
            );
      } else {
        final existing = await ref
            .read(productServiceProvider)
            .byId(widget.productId!);
        if (existing != null) {
          savedProduct = await ref
              .read(productServiceProvider)
              .update(existing, input, userId: session.user?.id);
          if (_originalPhotoPath != null && _originalPhotoPath != _photoPath) {
            await ref
                .read(productImageServiceProvider)
                .deleteIfManaged(_originalPhotoPath);
          }
          final newQty = input.stockQty;
          if (!_isService && newQty != existing.stockQty) {
            await ref
                .read(productServiceProvider)
                .adjustStock(
                  businessId: business.id,
                  productId: existing.id,
                  newQty: newQty,
                  reason: 'Ajustement depuis fiche produit',
                  userId: session.user?.id,
                  userRole: session.role,
                );
          }
        }
      }
      if (savedProduct != null && _supplierId != null) {
        final parsedReorder = MoneyFormat.parse(_reorderQuantity.text) ?? 1;
        await ref
            .read(automationServiceProvider)
            .setPreferredSupplier(
              businessId: business.id,
              productId: savedProduct.id,
              supplierId: _supplierId!,
              reorderQuantity: parsedReorder < 1 ? 1 : parsedReorder,
            );
      }
      if (savedProduct != null &&
          widget.sourceSaleId != null &&
          widget.sourceSaleId!.isNotEmpty) {
        await ref
            .read(saleServiceProvider)
            .linkAdHocItems(
              saleId: widget.sourceSaleId!,
              productId: savedProduct.id,
              productName: widget.initialName ?? savedProduct.name,
            );
      }
      _saved = true;
      if (mounted) {
        if (widget.sourceSaleId != null && widget.sourceSaleId!.isNotEmpty) {
          context.go('/sale/receipt/${widget.sourceSaleId}');
        } else {
          context.pop();
        }
      }
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initLoading) {
      return const Scaffold(
        backgroundColor: AppColors.pageBg,
        body: KumbaLoading(),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: Text(
          widget.productId == null
              ? S.tr('Nouveau produit', 'New product')
              : S.tr('Modifier le produit', 'Edit product'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Material(
                  color: AppColors.kpiCollectBg,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _choosePhotoSource,
                    child: SizedBox(
                      width: 144,
                      height: 144,
                      child:
                          _photoPath != null && File(_photoPath!).existsSync()
                          ? Image.file(
                              File(_photoPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.add_a_photo_outlined,
                                size: 42,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.add_a_photo_outlined,
                                  size: 42,
                                ),
                                const SizedBox(height: 8),
                                Text(S.tr('Photo du produit', 'Product photo')),
                              ],
                            ),
                    ),
                  ),
                ),
                if (_photoPath != null)
                  Positioned(
                    right: -10,
                    top: -10,
                    child: IconButton.filledTonal(
                      tooltip: S.tr('Retirer la photo', 'Remove photo'),
                      onPressed: () async {
                        final removed = _photoPath;
                        setState(() => _photoPath = null);
                        if (removed != _originalPhotoPath) {
                          await ref
                              .read(productImageServiceProvider)
                              .deleteIfManaged(removed);
                        }
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (widget.productId == null) ...[
            OutlinedButton.icon(
              onPressed: () => context.push('/products/catalog'),
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(
                S.tr(
                  'Choisir un produit déjà enregistré',
                  'Pick a registered product',
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SwitchListTile(
            title: Text(
              S.tr(
                'C’est un service (pas de stock)',
                'This is a service (no stock)',
              ),
            ),
            value: _isService,
            onChanged: (v) => setState(() => _isService = v),
          ),
          const SizedBox(height: 8),
          KumbaTextField(
            controller: _name,
            label: 'Nom',
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          KumbaAmountField(controller: _price, label: 'Prix de vente'),
          const SizedBox(height: 12),
          KumbaAmountField(controller: _cost, label: 'Prix d’achat'),
          if (!_isService) ...[
            const SizedBox(height: 12),
            KumbaTextField(
              controller: _stock,
              label: 'Quantité en stock',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            KumbaTextField(
              controller: _threshold,
              label: 'Seuil stock faible',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            KumbaTextField(controller: _unit, label: 'Unité'),
            const SizedBox(height: 12),
            KumbaTextField(
              controller: _barcode,
              label: 'Code-barres',
              keyboardType: TextInputType.number,
            ),
          ],
          const SizedBox(height: 18),
          DropdownButtonFormField<String?>(
            initialValue: _supplierId,
            decoration: InputDecoration(
              labelText: S.tr('Fournisseur principal', 'Preferred supplier'),
              helperText: _suppliers.isEmpty
                  ? S.tr(
                      'Créez d’abord un fournisseur dans le menu Plus.',
                      'Create a supplier first from the More menu.',
                    )
                  : null,
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(S.tr('Aucun fournisseur', 'No supplier')),
              ),
              ..._suppliers.map(
                (supplier) => DropdownMenuItem<String?>(
                  value: supplier.id,
                  child: Text(supplier.name),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _supplierId = value),
          ),
          if (_supplierId != null) ...[
            const SizedBox(height: 12),
            KumbaTextField(
              controller: _reorderQuantity,
              label: S.tr(
                'Quantité de réapprovisionnement proposée',
                'Suggested reorder quantity',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          KumbaButton(
            label: 'Enregistrer',
            isLoading: _loading,
            onPressed: _loading ? null : _save,
          ),
        ],
      ),
    );
  }
}
