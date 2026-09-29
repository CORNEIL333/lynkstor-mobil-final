import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'davex_pressable.dart';
import 'davex_tone.dart';

/// RECRÉER depuis `LynkstorMetricCard` (design-system/components.tsx) +
/// components.css `.lk-card, .lk-metric-card`, `.lk-metric-icon`,
/// override `.lk-home .lk-metric-card` (compact = true).
///
/// Spécifications maquette :
/// - bord 1 px borderDecorative, radius 16 px (var --lk-radius-large),
///   fond surface, ombre shadowCard ;
/// - padding 16 (12 en compact lk-home), empilement gap 7 px ;
/// - tuile icône 38×38, radius 12, fond/encre par ton ;
/// - label et trend 12 px textSecondary, value 24 px (20 px en compact).
class DavexMetricCard extends StatelessWidget {
  const DavexMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.trend,
    this.tone = DavexTone.info,
    this.compact = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? trend;
  final DavexTone tone;

  /// `lk-home` : `.lk-home .lk-metric-card { padding: 12px }`,
  /// `.lk-home .lk-metric-card strong { font-size: 20px }`.
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final c = davexToneColors(p, tone);
    final pad = compact ? 12.0 : 16.0;

    return DavexPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(LkColors.radiusLarge),
          border: Border.all(color: p.borderDecorative),
          boxShadow: [p.shadowCard],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: c.fg),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.text,
                fontSize: compact ? 20 : 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (trend != null) ...[
              const SizedBox(height: 7),
              Text(
                trend!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
