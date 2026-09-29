import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'davex_button.dart';

/// RECRÉER depuis `.lk-state` / `.lk-loading-state` (components.css
/// L473–507) : conteneur pointillé borderControl, radius 16, padding
/// 28×16, centré, gap 8 ; titre + corps 14 px textSecondary.
class DavexStateView extends StatelessWidget {
  const DavexStateView({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return CustomPaint(
      painter: _DashedRRectBorder(
        color: p.borderControl,
        radius: LkColors.radiusLarge,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null) Icon(icon, size: 28, color: p.textSecondary),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, fontSize: 14),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 8),
              Align(
                child: DavexButton(
                  label: actionLabel!,
                  variant: DavexButtonVariant.secondary,
                  onPressed: onAction,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// RECRÉER depuis `.lk-loading-state>span` : anneau 22 px, bord 3 px
/// infoBg, sommet info, rotation 700 ms linéaire.
class DavexLoading extends StatefulWidget {
  const DavexLoading({super.key});

  @override
  State<DavexLoading> createState() => _DavexLoadingState();
}

class _DavexLoadingState extends State<DavexLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  // HIG (reduce motion) : la boucle de rotation ne joue que si l'utilisateur
  // n'a pas demandé la réduction d'animations ; sinon, arc statique lisible.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      if (_c.isAnimating) _c.stop();
      _c.value = 0.3;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Transform.rotate(
            angle: _c.value * 6.283185307179586,
            child: CustomPaint(
              painter: _SpinnerPainter(track: p.infoBg, head: p.info),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.track, required this.head});
  final Color track;
  final Color head;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    canvas.drawArc(
      rect,
      0,
      6.283185307179586,
      false,
      Paint()
        ..color = track
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    // `border-top-color` CSS = quart supérieur peint (12 h → 18 h).
    canvas.drawArc(
      rect,
      -1.5707963267948966,
      1.5707963267948966,
      false,
      Paint()
        ..color = head
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.track != track || old.head != head;
}

/// Bordure pointillée (CSS `border: 1px dashed` — non natif Flutter).
class _DashedRRectBorder extends CustomPainter {
  const _DashedRRectBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    const dash = 5.0, gap = 4.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectBorder old) =>
      old.color != color || old.radius != radius;
}
