import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Segment de [DavexDonutChart].
class DavexDonutSegment {
  const DavexDonutSegment({required this.value, required this.color});

  final double value;
  final Color color;
}

/// CRÉÉ depuis le « DIAGRAMME 2 : Ring Donut Modes de Paiement » d'AccueilScreen
/// (App.tsx L3224–3268) : SVG viewBox 36, anneau de départ à 12 h
/// (`-rotate-90`), fond #F1F5F9 (strokeWidth 4), segments strokeWidth 4,5,
/// `strokeLinecap="round"`, proportions = dasharray.
/// Rendu Flutter : arcs CustomPaint, ratio trait 4,5/36 = 12,5 % du diamètre.
/// L'appelant superpose son libellé central ([center] = slot).
class DavexDonutChart extends StatelessWidget {
  const DavexDonutChart({
    super.key,
    required this.segments,
    this.size = 112,
    this.center,
  });

  final List<DavexDonutSegment> segments;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(segments: segments),
          ),
          if (center != null) center!,
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.segments});

  final List<DavexDonutSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * (4.5 / 36);
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    // Anneau de fond (.text-slate-100, strokeWidth 4).
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = const Color(0xFFF1F5F9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * (4 / 36),
    );

    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;

    var start = -math.pi / 2; // 12 h, comme `-rotate-90`.
    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweep = (seg.value / total) * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        // Arc complet : le rounded cap ferait déborder ; on peint un cercle.
        sweep >= math.pi * 2 - 0.01 ? math.pi * 2 : sweep,
        false,
        Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = sweep >= math.pi * 2 - 0.01
              ? StrokeCap.butt
              : StrokeCap.round,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.segments != segments;
}
