import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/permissions/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_controller.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_pressable.dart';
import '../../design_system/components/kumba_subscription_banner.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../design_system/motion/lynk_avatar.dart';
import '../../features/ai_assistant/lynk_prefs.dart';
import '../../l10n/app_strings.dart';

/// Menu Plus / Paramètres — grille type Control Center + préférences.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.isMoreMenu = false});

  final bool isMoreMenu;

  static const _tilePalette = <Color>[
    AppColors.kpiCollectBg,
    AppColors.kpiSalesBg,
    AppColors.kpiDebtBg,
    AppColors.kpiDepositBg,
    AppColors.lynkVioletSoft,
    AppColors.kpiCollectBg,
    AppColors.kpiSalesBg,
    AppColors.kpiDebtBg,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final themeMode = ref.watch(themeControllerProvider);
    final themeCtrl = ref.read(themeControllerProvider.notifier);
    final bottom = isMoreMenu
        ? 28.0
        : MediaQuery.paddingOf(context).bottom + 16;
    final reduce =
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
        session.performanceMode;
    final dark = AppColors.isDark(context);
    final scheme = Theme.of(context).colorScheme;

    final modules =
        <_Item>[
              _Item(
                Icons.people_outline_rounded,
                'Clients',
                '/customers',
                'clients',
                AppPermission.customersManage,
              ),
              _Item(
                Icons.account_balance_wallet_outlined,
                'Dettes',
                '/debts',
                'dettes',
                AppPermission.debtsView,
              ),
              _Item(
                Icons.receipt_long_outlined,
                'Dépenses',
                '/expenses',
                'depenses',
                AppPermission.expensesView,
              ),
              _Item(
                Icons.local_shipping_outlined,
                'Fournisseurs',
                '/suppliers',
                'fournisseurs',
                AppPermission.suppliersManage,
              ),
              _Item(
                Icons.shopping_bag_outlined,
                'Achats',
                '/purchases',
                'achats',
                AppPermission.purchasesManage,
              ),
              _Item(
                Icons.request_quote_outlined,
                'Devis',
                '/quotes',
                'devis',
                AppPermission.quotesManage,
              ),
              _Item(
                Icons.description_outlined,
                'Factures',
                '/invoices',
                'factures',
                AppPermission.invoicesManage,
              ),
              _Item(
                Icons.category_outlined,
                'Produits',
                '/products',
                'stock',
                AppPermission.stockView,
              ),
              _Item(
                Icons.fact_check_outlined,
                'Inventaire',
                '/inventory',
                'inventaire',
                AppPermission.inventoryManage,
              ),
              _Item(
                Icons.delivery_dining_outlined,
                'Livraisons',
                '/deliveries',
                'livraisons',
                AppPermission.deliveriesManage,
              ),
              _Item(
                Icons.badge_outlined,
                'Employés',
                '/employees',
                'employes',
                AppPermission.employeesManage,
              ),
              _Item(
                Icons.fingerprint_rounded,
                'Pointage',
                '/attendance',
                'pointage',
                AppPermission.attendanceManage,
              ),
              _Item(
                Icons.bar_chart_rounded,
                'Rapports',
                '/reports',
                'rapports',
                AppPermission.reportsView,
              ),
              _Item(
                Icons.cloud_download_outlined,
                'Sauvegardes',
                '/backup',
                'sauvegardes',
                AppPermission.backupManage,
              ),
              _Item(
                Icons.chat_bubble_outline_rounded,
                'Assistant local',
                '/ai',
                'ia',
                AppPermission.aiUse,
              ),
            ]
            .where(
              (m) =>
                  session.moduleEnabled(m.module) && session.can(m.permission),
            )
            .toList();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isMoreMenu
                  ? S.tr('Explorer', 'Explore')
                  : S.tr('Compte', 'Account'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              isMoreMenu
                  ? S.more
                  : (S.currentLanguage == 'en' ? 'Settings' : 'Paramètres'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: KumbaPressable(
              onTap: () {
                HapticFeedback.selectionClick();
                themeCtrl.cycle();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.mutedFill(context).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : AppColors.primary.withValues(alpha: 0.12),
                  ),
                ),
                child: Icon(themeCtrl.icon, color: AppColors.primary, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.pageHorizontal,
          8,
          AppSpacing.pageHorizontal,
          bottom,
        ),
        children: [
          if (session.business != null) ...[
            _profileHeader(context, session, dark, reduce),
            const SizedBox(height: AppSpacing.md),
            const KumbaLicenseCard(),
            const SizedBox(height: AppSpacing.xl),
          ],
          Text(
            S.tr('Modules', 'Modules'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            S.tr(
              'Raccourcis comme un Control Center',
              'Shortcuts like Control Center',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (modules.isEmpty)
            Text(
              S.tr(
                'Aucun module accessible pour votre rôle.',
                'No module is available for your role.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            _controlCenterGrid(context, modules, reduce),
          if (session.can(AppPermission.employeesManage)) ...[
            const SizedBox(height: AppSpacing.md),
            _inviteTile(context, ref, session),
          ],
          const SizedBox(height: AppSpacing.xl),
          Text(
            S.tr('Période test', 'Test period'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          KumbaCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.insights_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              title: Text(S.tr('Données du test', 'Test data')),
              subtitle: Text(
                S.tr(
                  'Envoyer ou exporter l’usage de cette boutique',
                  'Send or export this shop’s usage',
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: scheme.outline,
              ),
              onTap: () => context.push('/settings/analytics'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            S.tr('Préférences', 'Preferences'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          KumbaCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Icon(
                      themeCtrl.icon,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(S.tr('Apparence', 'Appearance')),
                  subtitle: Text(
                    themeCtrl.label(en: S.currentLanguage == 'en'),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.outline,
                  ),
                  onTap: () {
                    showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (ctx) {
                        return SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  S.tr('Apparence', 'Appearance'),
                                  style: Theme.of(ctx).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                for (final mode in [
                                  ThemeMode.system,
                                  ThemeMode.light,
                                  ThemeMode.dark,
                                ])
                                  ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusMd,
                                      ),
                                    ),
                                    selected: themeMode == mode,
                                    selectedTileColor: AppColors.primary
                                        .withValues(alpha: 0.10),
                                    leading: Icon(switch (mode) {
                                      ThemeMode.light =>
                                        Icons.light_mode_rounded,
                                      ThemeMode.dark => Icons.dark_mode_rounded,
                                      ThemeMode.system =>
                                        Icons.brightness_auto_rounded,
                                    }, color: AppColors.primary),
                                    title: Text(switch (mode) {
                                      ThemeMode.light => S.tr('Clair', 'Light'),
                                      ThemeMode.dark => S.tr('Sombre', 'Dark'),
                                      ThemeMode.system => S.tr(
                                        'Système',
                                        'System',
                                      ),
                                    }),
                                    trailing: themeMode == mode
                                        ? const Icon(
                                            Icons.check_circle_rounded,
                                            color: AppColors.primary,
                                          )
                                        : null,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      themeCtrl.setMode(mode);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: LynkAvatar(
                    size: 40,
                    accent: ref.watch(lynkPrefsProvider).accentColor,
                  ),
                  title: Text(S.tr('Assistant Lynk', 'Lynk assistant')),
                  subtitle: Text(ref.watch(lynkPrefsProvider).name),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.outline,
                  ),
                  onTap: () => _showLynkPrefs(context, ref),
                ),
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  title: Text(S.tr('Mode performance', 'Performance mode')),
                  subtitle: Text(
                    S.tr(
                      'Moins de flou et d’animations',
                      'Less blur and fewer animations',
                    ),
                  ),
                  value: session.performanceMode,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) =>
                      ref.read(sessionProvider.notifier).setPerformanceMode(v),
                ),
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  title: Text(
                    S.tr('Déverrouillage biométrique', 'Biometric unlock'),
                  ),
                  subtitle: Text(
                    S.tr(
                      'En plus du PIN de session',
                      'In addition to the session PIN',
                    ),
                  ),
                  value: session.biometricEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) async {
                    if (v) {
                      final available = await ref
                          .read(biometricServiceProvider)
                          .isAvailable();
                      if (!available) {
                        if (context.mounted) {
                          showLkToast(
                            context,
                            S.tr(
                              'Biométrie indisponible sur cet appareil.',
                              'Biometrics are unavailable on this device.',
                            ),
                            tone: LkToastTone.warning,
                            icon: Icons.info_outline,
                          );
                        }
                        return;
                      }
                      final ok = await ref
                          .read(biometricServiceProvider)
                          .authenticate(
                            reason: 'Activer le déverrouillage biométrique',
                          );
                      if (!ok) return;
                    }
                    await ref
                        .read(sessionProvider.notifier)
                        .setBiometricEnabled(v);
                  },
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: Icon(
                    Icons.language_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    S.currentLanguage == 'en' ? 'Language' : 'Langue',
                  ),
                  subtitle: Text(
                    S.currentLanguage == 'en' ? 'English' : 'Français',
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.outline,
                  ),
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        title: const Text('Langue / Language'),
                        children: [
                          SimpleDialogOption(
                            onPressed: () async {
                              await ref
                                  .read(localeControllerProvider.notifier)
                                  .setLanguage('fr');
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            child: const Text('Français'),
                          ),
                          SimpleDialogOption(
                            onPressed: () async {
                              await ref
                                  .read(localeControllerProvider.notifier)
                                  .setLanguage('en');
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            child: const Text('English'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: Icon(
                    Icons.cloud_sync_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    S.tr(
                      'Activation et abonnement',
                      'Activation and subscription',
                    ),
                  ),
                  subtitle: Text(
                    S.tr(
                      'Forfait, expiration et état de la licence',
                      'Plan, expiration and license status',
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.outline,
                  ),
                  onTap: () => context.push('/subscription'),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(S.lock),
                  subtitle: Text(
                    S.tr('Verrouiller avec le PIN', 'Lock with PIN'),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.outline,
                  ),
                  onTap: () async {
                    await ref.read(sessionProvider.notifier).logout();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) {
              final v = snap.data?.version ?? AppConfig.version;
              final b = snap.data?.buildNumber ?? '${AppConfig.buildNumber}';
              return Text(
                '${AppConfig.appName}\nv$v ($b) · Offline-first · RBAC',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _profileHeader(
    BuildContext context,
    SessionState session,
    bool dark,
    bool reduce,
  ) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : AppColors.fab,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(
          color: Colors.white.withValues(alpha: dark ? 0.08 : 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryContainer.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1.5,
              ),
              image: const DecorationImage(
                image: AssetImage('assets/images/ic_launcher.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.business!.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${session.user?.fullName ?? 'Utilisateur'} · ${RolePermissions.label(RolePermissions.parseRole(session.role))}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
            ),
            child: Text(
              S.tr('Actif', 'Active'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (reduce) return card;
    return card.animate().fadeIn(duration: 300.ms).slideY(begin: 0.03, end: 0);
  }

  Widget _controlCenterGrid(
    BuildContext context,
    List<_Item> modules,
    bool reduce,
  ) {
    final grid = LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final w = constraints.maxWidth;
        final cell = (w - gap) / 2;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < modules.length; i++)
              SizedBox(
                width: cell,
                height: 108,
                child: _moduleTile(
                  context,
                  modules[i],
                  _tilePalette[i % _tilePalette.length],
                  i,
                  reduce,
                ),
              ),
          ],
        );
      },
    );

    if (reduce) return grid;
    return grid
        .animate()
        .fadeIn(delay: 80.ms, duration: 320.ms)
        .slideY(begin: 0.02, end: 0);
  }

  Widget _moduleTile(
    BuildContext context,
    _Item item,
    Color accent,
    int index,
    bool reduce,
  ) {
    final dark = AppColors.isDark(context);
    final tile = KumbaPressable(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(item.route);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkCard : accent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          boxShadow: [
            BoxShadow(
              color: (dark ? Colors.black : accent).withValues(
                alpha: dark ? 0.28 : 0.10,
              ),
              blurRadius: 16,
              offset: const Offset(0, 8),
              spreadRadius: -6,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: dark ? 0.12 : 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                item.icon,
                color: dark ? Colors.white : AppColors.secondary,
                size: 20,
              ),
            ),
            const Spacer(),
            Text(
              S.auto(item.label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: dark ? Colors.white : AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );

    if (reduce) return tile;
    return tile
        .animate()
        .fadeIn(delay: (24 * (index % 8)).ms, duration: 280.ms)
        .scale(
          begin: const Offset(0.96, 0.96),
          end: const Offset(1, 1),
          delay: (24 * (index % 8)).ms,
          duration: 300.ms,
          curve: Curves.easeOutCubic,
        );
  }

  Widget _inviteTile(
    BuildContext context,
    WidgetRef ref,
    SessionState session,
  ) {
    return KumbaCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.turquoise.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: const Icon(
            Icons.vpn_key_outlined,
            color: AppColors.turquoiseDeep,
            size: 20,
          ),
        ),
        title: Text(S.tr('Invitation employé', 'Employee invitation')),
        subtitle: Text(
          S.tr(
            'Code à usage unique (7 jours), multi-postes cloud',
            'Single-use code (7 days), cloud multi-device',
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: Theme.of(context).colorScheme.outline,
        ),
        onTap: () async {
          String code;
          try {
            code = await ref
                .read(invitationServiceProvider)
                .createInvitation(
                  businessId: session.business!.id,
                  role: 'seller',
                  createdBy: session.user?.id,
                );
          } on AppException catch (e) {
            if (!context.mounted) return;
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(S.tr('Invitation impossible', 'Invite failed')),
                content: Text(e.message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
            return;
          }
          if (!context.mounted) return;
          await Clipboard.setData(ClipboardData(text: code));
          if (!context.mounted) return;
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(S.tr('Code d’invitation', 'Invitation code')),
              content: Text(
                S.tr(
                  'Code : $code\n\nCopié dans le presse-papiers.\n'
                      'L’employé saisit ce code sur « Rejoindre un commerce ».',
                  'Code: $code\n\nCopied to the clipboard.\n'
                      'The employee enters this code on “Join a business”.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showLynkPrefs(BuildContext context, WidgetRef ref) {
    final prefs = ref.read(lynkPrefsProvider);
    final nameCtrl = TextEditingController(text: prefs.name);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.tr('Personnaliser Lynk', 'Customize Lynk'),
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: S.tr('Nom', 'Name')),
                  onSubmitted: (v) =>
                      ref.read(lynkPrefsProvider.notifier).setName(v),
                ),
                const SizedBox(height: 16),
                Text(
                  S.tr('Couleur d’accent', 'Accent color'),
                  style: Theme.of(ctx).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final entry in const [
                      ('coral', AppColors.coral),
                      ('sky', AppColors.sky),
                      ('ocean', AppColors.ocean),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: KumbaPressable(
                          onTap: () => ref
                              .read(lynkPrefsProvider.notifier)
                              .setAccent(entry.$1),
                          child: LynkAvatar(size: 52, accent: entry.$2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    ref.read(lynkPrefsProvider.notifier).setName(nameCtrl.text);
                    Navigator.pop(ctx);
                  },
                  child: Text(S.save),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(nameCtrl.dispose);
  }
}

class _Item {
  _Item(this.icon, this.label, this.route, this.module, this.permission);
  final IconData icon;
  final String label;
  final String route;
  final String module;
  final AppPermission permission;
}
