import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// SyncIndicator — port fidèle de `src/ui/SyncIndicator.tsx`.
///
/// Trois transports seulement, jamais de jargon technique (§5.3) :
/// - cloud : synchronisé avec le cloud (ton success) ;
/// - wifi  : synchronisé sur le réseau local (ton info) ;
/// - local : hors ligne, files locales (neutre).
/// La perte de connectivité retombe TOUJOURS sur local ; cloud/wifi exigent
/// un événement de synchronisation positif.
enum LkSyncTransport { cloud, wifi, local }

class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, required this.transport});

  final LkSyncTransport transport;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final (Color bg, Color fg, IconData icon, String label) = switch (transport)
    {
      LkSyncTransport.cloud => (
        p.successBg,
        p.successFg,
        Icons.cloud_done_outlined,
        'Cloud',
      ),
      LkSyncTransport.wifi => (
        p.infoBg,
        p.infoFg,
        Icons.wifi,
        'Wi-Fi',
      ),
      LkSyncTransport.local => (
        p.surfaceMuted,
        p.textSecondary,
        Icons.phone_android_outlined,
        'Local',
      ),
    };
    return Semantics(
      label: 'Synchronisation : $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
          border: Border.all(color: p.borderDecorative),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: fg,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
