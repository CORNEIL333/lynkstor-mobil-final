import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'sync_indicator.dart' show LkSyncTransport;

/// RECRÉER depuis `.lk-sync-indicator` (index.css L79–80) +
/// `ui/SyncIndicator.tsx` : padding 4×7, gap 5, bord 1 px
/// borderDecorative, radius 999, 10 px w650 (→ w600), ls 0,01 em,
/// lh 1,2 ; point ::before 5 px currentColor 90 % PUIS icône 12 PUIS
/// libellé. États : cloud (successBg/successFg), wifi (infoBg/infoFg),
/// local (surfaceMuted/textSecondary).
class DavexSyncIndicator extends StatelessWidget {
  const DavexSyncIndicator({super.key, required this.transport});

  final LkSyncTransport transport;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final (Color bg, Color fg, IconData icon, String label) =
        switch (transport) {
          LkSyncTransport.cloud => (
            p.successBg,
            p.successFg,
            Icons.cloud_outlined,
            'Cloud',
          ),
          LkSyncTransport.wifi => (
            p.infoBg,
            p.infoFg,
            Icons.wifi_outlined,
            'Wi-Fi',
          ),
          LkSyncTransport.local => (
            p.surfaceMuted,
            p.textSecondary,
            Icons.smartphone_outlined,
            'Local',
          ),
        };
    return Semantics(
      label: 'Synchronisation : $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: p.borderDecorative),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `.lk-sync-indicator::before` — point d'état.
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fg.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 5),
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg,
                letterSpacing: 0.1,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
