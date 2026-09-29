import 'package:flutter/material.dart';

/// Primitif Davex — wrapper tactile « active:scale(.97) » de la maquette
/// (components.css `.lk-ds-button:active { transform: scale(.97) }`,
/// transition 160 ms ease).
///
/// HIG (Apple, *Touch Targets*) : garantit une zone tactile ≥ 44×44 pt
/// même si l'enfant est plus petit.
class DavexPressable extends StatefulWidget {
  const DavexPressable({
    super.key,
    required this.onTap,
    required this.child,
    this.scale = 0.97,
    this.minTouchTarget = 44,
    this.semanticLabel,
  });

  final VoidCallback? onTap;
  final Widget child;
  final double scale;
  final double minTouchTarget;
  final String? semanticLabel;

  @override
  State<DavexPressable> createState() => _DavexPressableState();
}

class _DavexPressableState extends State<DavexPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? widget.scale : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: widget.minTouchTarget,
              minWidth: widget.minTouchTarget,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
