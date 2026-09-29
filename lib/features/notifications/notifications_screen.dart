import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_ai_badge.dart';
import '../../design_system/components/kumba_states.dart';
import '../../l10n/app_strings.dart';

final _notificationsProvider =
    StreamProvider.autoDispose<List<AppNotification>>((ref) {
      final business = ref.watch(sessionProvider).business;
      if (business == null) return Stream.value(const []);
      return ref.watch(notificationServiceProvider).watch(business.id);
    });

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: S.tr('Notifications', 'Notifications'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.push('/notifications'),
          child: Ink(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.72),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.95),
              ),
            ),
            child: Badge(
              isLabelVisible: count > 0,
              label: Text(count > 99 ? '99+' : '$count'),
              child: const Icon(
                PhosphorIconsRegular.bell,
                color: AppColors.ocean,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_notificationsProvider);
    final business = ref.watch(sessionProvider).business;
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: Text(S.tr('Centre de notifications', 'Notification center')),
        actions: [
          IconButton(
            tooltip: S.tr('Tout marquer comme lu', 'Mark all as read'),
            onPressed: business == null
                ? null
                : () => ref
                      .read(notificationServiceProvider)
                      .markAllRead(business.id),
            icon: const Icon(Icons.done_all_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete_read' && business != null) {
                ref.read(notificationServiceProvider).deleteRead(business.id);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete_read',
                child: Text(
                  S.tr(
                    'Supprimer les notifications lues',
                    'Delete read notifications',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => const KumbaLoading(),
        error: (error, _) => KumbaErrorState(message: '$error'),
        data: (notifications) {
          final filtered = notifications.where((notification) {
            if (_filter == 'all') return true;
            if (_filter == 'unread') return !notification.isRead;
            if (_filter == 'ai') {
              return notification.type == 'ai' ||
                  notification.type == 'catalog';
            }
            return notification.type == _filter;
          }).toList();
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    _chip('all', S.tr('Toutes', 'All')),
                    _chip('unread', S.tr('Non lues', 'Unread')),
                    _chip('stock', S.tr('Stock', 'Stock')),
                    _chip('catalog', S.tr('Catalogue', 'Catalog')),
                    _chip('system', S.tr('Système', 'System')),
                    _chip('ai', S.tr('Lynk', 'Lynk')),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? KumbaEmptyState(
                        title: S.tr('Aucune notification', 'No notifications'),
                        subtitle: S.tr(
                          'Les alertes importantes apparaîtront ici.',
                          'Important alerts will appear here.',
                        ),
                        icon: Icons.notifications_none_rounded,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, index) =>
                            _notificationCard(filtered[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _notificationCard(AppNotification notification) {
    final args = _decode(notification.argsJson);
    final color = switch (notification.severity) {
      'critical' => AppColors.error,
      'warning' => AppColors.warning,
      _ => AppColors.primary,
    };
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: AppColors.errorSoft,
        child: const Icon(Icons.archive_outlined, color: AppColors.error),
      ),
      onDismissed: (_) =>
          ref.read(notificationServiceProvider).archive(notification.id),
      child: KumbaCard(
        onTap: () => _openNotification(notification),
        borderColor: notification.isRead ? null : color.withValues(alpha: 0.35),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              foregroundColor: color,
              child: Icon(_icon(notification.type)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notification.type == 'ai' ||
                      notification.type == 'catalog')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: KumbaAiBadge(compact: true),
                    ),
                  Text(
                    S.notificationTitle(notification.titleKey, args),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: notification.isRead
                          ? FontWeight.w600
                          : FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(S.notificationBody(notification.bodyKey, args)),
                  const SizedBox(height: 7),
                  Text(
                    DateFormat(
                      'dd/MM/yyyy HH:mm',
                    ).format(notification.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNotification(AppNotification notification) async {
    await ref.read(notificationServiceProvider).markRead(notification.id);
    if (!mounted) return;
    final payload = _decode(notification.actionPayloadJson);
    switch (notification.actionType) {
      case 'configure_ad_hoc_product':
        final uri = Uri(
          path: '/products/new',
          queryParameters: {
            'name': '${payload['name'] ?? ''}',
            'price': '${payload['price'] ?? 0}',
            'unit': '${payload['unit'] ?? 'pièce'}',
            'saleId': '${payload['saleId'] ?? ''}',
          },
        );
        await context.push(uri.toString());
      case 'configure_supplier':
        final productId = '${payload['productId'] ?? ''}';
        if (productId.isNotEmpty) {
          await context.push('/products/$productId?supplier=1');
        }
      case 'draft_supplier_message':
        await _showSupplierDraft(payload);
    }
  }

  Future<void> _showSupplierDraft(Map<String, dynamic> payload) async {
    final supplier = '${payload['supplierName'] ?? ''}';
    final product = '${payload['productName'] ?? ''}';
    final phone = '${payload['phone'] ?? ''}';
    final stock = (payload['stock'] as num?)?.toDouble() ?? 0;
    final threshold = (payload['threshold'] as num?)?.toDouble() ?? 0;
    final reorder = (payload['reorderQuantity'] as num?)?.toDouble() ?? 1;
    final fallback = S.tr(
      'Bonjour $supplier, notre stock de $product est arrivé à '
          '${_number(stock)}. Pouvez-vous confirmer la disponibilité et le '
          'prix pour ${_number(reorder)} unité(s) ?',
      'Hello $supplier, our stock of $product has reached ${_number(stock)}. '
          'Could you confirm availability and the price for '
          '${_number(reorder)} unit(s)?',
    );
    final controller = TextEditingController(text: fallback);
    var generating = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(S.tr('Message au fournisseur', 'Supplier message')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: S.tr('Message proposé', 'Suggested message'),
                  ),
                ),
                const SizedBox(height: 12),
                KumbaButton(
                  label: generating
                      ? S.tr('Rédaction…', 'Drafting…')
                      : S.tr(
                          'Améliorer avec l’IA locale',
                          'Improve with local AI',
                        ),
                  icon: Icons.auto_awesome_outlined,
                  variant: KumbaButtonVariant.outline,
                  onPressed: generating
                      ? null
                      : () async {
                          setDialogState(() => generating = true);
                          final draft = await ref
                              .read(lynkBrainProvider)
                              .draftSupplierMessage(
                                fallback: controller.text,
                                productName: product,
                                stock: stock,
                                threshold: threshold,
                                reorderQuantity: reorder,
                                supplierName: supplier,
                                language: S.currentLanguage,
                              );
                          controller.text = draft;
                          setDialogState(() => generating = false);
                        },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(S.cancel),
            ),
            TextButton.icon(
              onPressed: phone.isEmpty
                  ? null
                  : () => _launchSms(phone, controller.text),
              icon: const Icon(Icons.sms_outlined),
              label: const Text('SMS'),
            ),
            FilledButton.icon(
              onPressed: phone.isEmpty
                  ? null
                  : () => _launchWhatsApp(phone, controller.text),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('WhatsApp'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _launchSms(String phone, String message) async {
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchWhatsApp(String phone, String message) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.https('wa.me', '/$digits', {'text': message});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Map<String, dynamic> _decode(String? value) {
    if (value == null || value.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return {};
    }
  }

  IconData _icon(String type) => switch (type) {
    'stock' => Icons.inventory_2_outlined,
    'catalog' => Icons.add_box_outlined,
    'sync' => Icons.sync_problem_outlined,
    _ => Icons.notifications_outlined,
  };

  String _number(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
}
