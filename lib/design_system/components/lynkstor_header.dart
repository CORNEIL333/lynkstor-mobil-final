import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// Native adaptation of Figma Make's LynkstorHeader.
class LynkstorHeader extends StatelessWidget {
  const LynkstorHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.shopName,
    this.actions = const [],
    this.onBack,
    this.status,
  });

  final String title;
  final String subtitle;
  final String shopName;
  final List<Widget> actions;
  final VoidCallback? onBack;

  /// Indicateur de synchronisation (SyncIndicator) affiché sous le sous-titre,
  /// comme dans le header de la maquette.
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final initials = shopName.trim().split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty).take(2)
        .map((s) => s.characters.first).join().toUpperCase();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ClipRect(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF08192D), Color(0xFF06101F), Color(0xFF071526)],
            ),
          ),
          child: Stack(children: [
            Positioned(
              top: -90, left: -102,
              child: Container(
                width: 204, height: 204,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Color(0xFFFFB321), AppColors.primary, Color(0xFFE77D00)]),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 12, 18),
                child: LayoutBuilder(builder: (context, constraints) {
                  final compact = constraints.maxWidth < 460;
                  final copy = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.12)),
                      const SizedBox(height: 6),
                      Text(subtitle, style: const TextStyle(color: Color(0xFFC5D0E1), fontSize: 12)),
                      if (status != null) ...[
                        const SizedBox(height: 8),
                        status!,
                      ],
                    ],
                  );
                  final profile = onBack != null
                      ? LynkstorHeaderAction(icon: Icons.arrow_back, label: 'Retour', onTap: onBack!)
                      : Container(
                          width: 58, height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0xFFEDF3FF), shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 3)),
                          child: Text(initials.isEmpty ? 'LS' : initials, style: const TextStyle(color: AppColors.info, fontWeight: FontWeight.w800, fontSize: 20)),
                        );
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [profile, const SizedBox(width: 14), Expanded(child: copy), if (!compact) ...actions]),
                    if (compact && actions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
                    ],
                  ]);
                }),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class LynkstorHeaderAction extends StatelessWidget {
  const LynkstorHeaderAction({super.key, required this.icon, required this.label, required this.onTap, this.count = 0});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Badge(
      isLabelVisible: count > 0,
      backgroundColor: AppColors.primary,
      label: Text(count > 99 ? '99+' : '$count'),
      child: IconButton.filled(
        tooltip: label,
        style: IconButton.styleFrom(backgroundColor: const Color(0xFF16253A), foregroundColor: Colors.white, minimumSize: const Size(44, 44)),
        onPressed: onTap,
        icon: Icon(icon, size: 22),
      ),
    ),
  );
}
