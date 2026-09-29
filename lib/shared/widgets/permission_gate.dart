import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/permissions/permission_guard.dart';
import '../../core/permissions/permissions.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_states.dart';
import '../../l10n/app_strings.dart';

/// Enveloppe un écran avec contrôle de permission.
class PermissionGate extends ConsumerWidget {
  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.module,
  });

  final AppPermission permission;
  final Widget child;
  final String? module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final role = session.user?.role ?? 'seller';
    final guard = PermissionGuard.of(role);

    if (module != null && !session.moduleEnabled(module!)) {
      return Scaffold(
        appBar: AppBar(),
        body: KumbaEmptyState(
          title: S.moduleDisabled,
          subtitle:
              'Ce module n’est pas activé pour le secteur de votre commerce.',
          icon: Icons.block,
          actionLabel: 'Retour',
          onAction: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      );
    }

    if (!guard.allows(permission)) {
      return Scaffold(
        appBar: AppBar(title: Text(S.permissionDenied)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 16),
              Text(
                S.permissionDenied,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(S.accessDeniedDetail, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              KumbaButton(
                label: 'Retour à l’accueil',
                onPressed: () => context.go('/home'),
              ),
            ],
          ),
        ),
      );
    }

    return child;
  }
}
