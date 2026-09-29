import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_motion.dart';

/// Scale press Apple-like pour cartes / chips flottants.
class KumbaPressable extends StatefulWidget {
  const KumbaPressable({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.haptic = true,
    this.scale = AppMotion.pressScale,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final bool haptic;
  final double scale;

  @override
  State<KumbaPressable> createState() => _KumbaPressableState();
}

class _KumbaPressableState extends State<KumbaPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled && widget.onTap != null
          ? (_) => setState(() => _down = true)
          : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.enabled
          ? () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap?.call();
            }
          : null,
      child: AnimatedScale(
        scale: _down && !reduce ? widget.scale : 1,
        duration: AppMotion.instant,
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}
