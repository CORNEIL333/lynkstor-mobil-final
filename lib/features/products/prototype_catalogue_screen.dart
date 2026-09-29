import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/catalog/prototype_catalogue.dart';
import '../../core/utils/money_format.dart';
import '../../l10n/app_strings.dart';

class PrototypeCatalogueScreen extends StatefulWidget {
  const PrototypeCatalogueScreen({
    super.key,
    this.loadCatalogue = PrototypeCatalogue.load,
  });

  final Future<List<PrototypeCatalogueItem>> Function(String) loadCatalogue;

  @override
  State<PrototypeCatalogueScreen> createState() =>
      _PrototypeCatalogueScreenState();
}

class _PrototypeCatalogueScreenState extends State<PrototypeCatalogueScreen> {
  String _source = PrototypeCatalogue.sources.keys.first;
  String _query = '';
  String? _category;
  late Future<List<PrototypeCatalogueItem>> _items = widget.loadCatalogue(
    _source,
  );

  void _load(String source) => setState(() {
    _source = source;
    _category = null;
    _items = widget.loadCatalogue(source);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(S.tr('Catalogues fournisseurs', 'Supplier catalogues')),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.tr(
                      'Disponibles hors ligne. Les prix sont des observations fournisseurs. Définissez votre prix et votre stock avant d’enregistrer.',
                      'Available offline. Prices are supplier observations. Set your price and stock before saving.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _source,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: S.tr('Secteur', 'Sector'),
                    ),
                    items: [
                      for (final source in PrototypeCatalogue.sources.entries)
                        DropdownMenuItem(
                          value: source.key,
                          child: Text(source.value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _load(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: S.tr(
                        'Produit, marque, fournisseur…',
                        'Product, brand, supplier…',
                      ),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<PrototypeCatalogueItem>>(
                future: _items,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () => _load(_source),
                        child: Text(
                          S.tr(
                            'Catalogue indisponible — réessayer',
                            'Catalogue unavailable — retry',
                          ),
                        ),
                      ),
                    );
                  }
                  final all = snapshot.data ?? [];
                  final categories =
                      all.map((item) => item.category).toSet().toList()..sort();
                  final filtered = all
                      .where((item) => item.matches(_query, _category))
                      .toList();
                  return Column(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            for (final category in <String?>[
                              null,
                              ...categories,
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    category ?? S.tr('Toutes', 'All'),
                                  ),
                                  selected: _category == category,
                                  onSelected: (_) =>
                                      setState(() => _category = category),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          S.tr(
                            '${filtered.length} références',
                            '${filtered.length} items',
                          ),
                        ),
                      ),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  S.tr(
                                    'Aucun produit trouvé',
                                    'No products found',
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  return Card(
                                    margin: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      10,
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(16),
                                      title: Text(item.name),
                                      subtitle: Text(
                                        [
                                          item.category,
                                          '${item.seller} · ${item.observedAt.split('T').first}',
                                          item.suggestedPrice != null
                                              ? S.tr(
                                                  'Prix observé : ${MoneyFormat.format(item.suggestedPrice!)}',
                                                  'Observed price: ${MoneyFormat.format(item.suggestedPrice!)}',
                                                )
                                              : S.tr(
                                                  'Prix à vérifier',
                                                  'Price needs review',
                                                ),
                                        ].join('\n'),
                                      ),
                                      trailing: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                      onTap: () => context.push(
                                        Uri(
                                          path: '/products/new',
                                          queryParameters: {
                                            'name': item.name,
                                            if (item.suggestedPrice != null)
                                              'price': item.suggestedPrice
                                                  .toString(),
                                          },
                                        ).toString(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
