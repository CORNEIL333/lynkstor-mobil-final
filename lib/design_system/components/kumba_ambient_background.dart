import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Fond plat — pas de dégradé ni de blobs.
class KumbaAmbientBackground extends StatelessWidget {
  const KumbaAmbientBackground({
    super.key,
    required this.child,
    this.performanceMode = false,
    this.imageAsset,
    this.imageOpacity = 0.2,
    this.imageAlignment = Alignment.center,
  });

  final Widget child;
  final bool performanceMode;
  final String? imageAsset;
  final double imageOpacity;
  final Alignment imageAlignment;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppColors.darkBg : AppColors.pageBg;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: base),
        if (imageAsset != null)
          Positioned.fill(
            child: Opacity(
              opacity: imageOpacity,
              child: Image.asset(
                imageAsset!,
                fit: BoxFit.cover,
                alignment: imageAlignment,
              ),
            ),
          ),
        if (imageAsset != null)
          Positioned.fill(
            child: ColoredBox(color: base.withValues(alpha: 0.72)),
          ),
        child,
      ],
    );
  }
}
