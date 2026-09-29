import 'package:flutter/material.dart';

import 'davex_pressable.dart';

/// RECRÉER depuis `.lk-qr-banner` (components.css L220–278) — bannière
/// navy fixe des deux thèmes (comme la barre de navigation) :
/// margin 12×16, padding 10/10/10/12, bord 1 px rgba(255,152,0,.68),
/// radius 16, dégradé 100deg rgba(255,152,0,.16)→.04, ombre
/// 0 10/22 rgba(0,0,0,.12), entrée 220 ms ease-out translateY(-8).
/// Tuile icône 38×38 radius 12 #FF9800 ; copie blanc 13 px + #C9D5E6
/// 11 px ; ouvrir #FFAD24 w700 ; fermer #AAB7CC.
///
/// ÉCART VOLONTAIRE (charte) : glyphe sur tuile orange = encre #3A2500
/// au lieu du blanc CSS (WCAG).
class DavexQrBanner extends StatefulWidget {
  const DavexQrBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onDismiss,
    this.icon = Icons.qr_code_2,
    this.openLabel = 'Ouvrir',
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final IconData icon;
  final String openLabel;

  @override
  State<DavexQrBanner> createState() => _DavexQrBannerState();
}

class _DavexQrBannerState extends State<DavexQrBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -8 / 64),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment(-0.98, -0.17),
                end: Alignment(0.98, 0.17),
                colors: [Color(0x29FF9800), Color(0x0AFF9800)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xADFF9800)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 20,
                    color: const Color(0xFF3A2500),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFC9D5E6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                DavexPressable(
                  onTap: widget.onTap,
                  semanticLabel: widget.openLabel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 9,
                    ),
                    child: Text(
                      widget.openLabel,
                      style: const TextStyle(
                        color: Color(0xFFFFAD24),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (widget.onDismiss != null)
                  DavexPressable(
                    onTap: widget.onDismiss,
                    semanticLabel: 'Fermer',
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: Color(0xFFAAB7CC),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
