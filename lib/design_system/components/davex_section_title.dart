import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// RECRÉER depuis `.lk-section-title` (components.css L387–399) :
/// flex space-between, h2 18 px, letter-spacing −0,02 em, encre text.
class DavexSectionTitle extends StatelessWidget {
  const DavexSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: p.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -18 * 0.02,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
