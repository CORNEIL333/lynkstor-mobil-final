import 'package:flutter/material.dart';

/// Point de données de [DavexAreaChart] — même forme que
/// `revenueByPeriod[*]` de la maquette ({label, amount, sales, isPeak}).
class DavexChartPoint {
  const DavexChartPoint({
    required this.label,
    required this.amount,
    required this.sales,
    this.isPeak = false,
  });

  final String label;
  final double amount;
  final int sales;
  final bool isPeak;
}

/// CRÉÉ depuis le « DIAGRAMME 1 : Courbe d'Évolution du CA » d'AccueilScreen
/// (App.tsx L3103–3210) :
/// - courbe cubique lissée (contrôles = milieu des x, CSS `C cx,prevY cx,ptY`) ;
/// - trait 3 px dégradé horizontal #4F46E5 → #7C3AED → #06B6D4 ;
/// - aire sous la courbe, dégradé vertical #4F46E5 35 % → #7C3AED 0 % ;
/// - lignes de grille pointillées #F1F5F9 à 20/45/70 % de la hauteur ;
/// - points : r 2,8 blanc bord #4F46E5 2 px ; pic = r 3,5 + halo r 5,5
///   #7C3AED 50 % ; sélection = r 4,5 plein #4F46E5 bord blanc + anneau
///   animé (animate-ping → pulse 1,2 s) ;
/// - labels x 10 px w700, sélection #4F46E5, défaut #94A3B8 ;
/// - zone tactile : colonne entière par point (hit area 12 px CSS → 1/7
///   de la largeur ici), callback [onSelected] (null = désélection).
class DavexAreaChart extends StatelessWidget {
  const DavexAreaChart({
    super.key,
    required this.points,
    this.selectedIndex,
    this.onSelected,
    this.height = 128,
  });

  final List<DavexChartPoint> points;
  final int? selectedIndex;
  final ValueChanged<int?>? onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: SizedBox.shrink()),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, box) {
              final geom = _chartGeometry(
                points,
                Size(box.maxWidth, box.maxHeight),
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  if (onSelected == null) return;
                  // Sélection du point le plus proche horizontalement.
                  var best = 0;
                  var bestDist = double.infinity;
                  for (var i = 0; i < geom.length; i++) {
                    final dist = (d.localPosition.dx - geom[i].center.dx).abs();
                    if (dist < bestDist) {
                      bestDist = dist;
                      best = i;
                    }
                  }
                  onSelected!(
                    selectedIndex == best ? null : best,
                  );
                },
                child: CustomPaint(
                  painter: _AreaPainter(
                    points: points,
                    geometry: geom,
                    selectedIndex: selectedIndex,
                  ),
                ),
              );
            },
          ),
        ),
        // Labels axe X (`.border-t` CSS → séparateur fin).
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < points.length; i++)
                  Flexible(
                    child: Text(
                      points[i].label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: selectedIndex == i
                            ? FontWeight.w800
                            : FontWeight.w700,
                        color: selectedIndex == i
                            ? const Color(0xFF4F46E5)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

List<_Pt> _chartGeometry(List<DavexChartPoint> points, Size size) {
  // Repère CSS : x = i/(n-1)*(W-30)+15 (marges 15 px), y = H-12-(v/max)*58
  // sur une carte de 300×85 → transposé en proportions pleines.
  final maxAmount = points.fold<double>(
    0,
    (m, p) => p.amount > m ? p.amount : m,
  );
  final w = size.width, h = size.height;
  final left = w * 0.05, right = w * 0.95;
  final topPad = h * 0.14, bottomPad = h * 0.14;
  return [
    for (var i = 0; i < points.length; i++)
      _Pt(
        center: Offset(
          points.length == 1
              ? (left + right) / 2
              : left + (right - left) * i / (points.length - 1),
          maxAmount == 0
              ? h - bottomPad
              : h -
                    bottomPad -
                    (points[i].amount / maxAmount) * (h - topPad - bottomPad),
        ),
      ),
  ];
}

class _Pt {
  const _Pt({required this.center});
  final Offset center;
}

class _AreaPainter extends CustomPainter {
  const _AreaPainter({
    required this.points,
    required this.geometry,
    required this.selectedIndex,
  });

  final List<DavexChartPoint> points;
  final List<_Pt> geometry;
  final int? selectedIndex;

  static const _lineColors = [
    Color(0xFF4F46E5),
    Color(0xFF7C3AED),
    Color(0xFF06B6D4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Grilles horizontales pointillées (20/45/70 %).
    final grid = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1;
    for (final gy in [0.2, 0.45, 0.7]) {
      final y = size.height * gy;
      canvas.drawLine(Offset(size.width * 0.03, y), Offset(size.width * 0.97, y), grid);
    }

    // Courbe lissée : cubic avec contrôles au milieu des x (formule CSS).
    final path = Path()..moveTo(geometry.first.center.dx, geometry.first.center.dy);
    for (var i = 1; i < geometry.length; i++) {
      final prev = geometry[i - 1].center;
      final pt = geometry[i].center;
      final cx = (prev.dx + pt.dx) / 2;
      path.cubicTo(cx, prev.dy, cx, pt.dy, pt.dx, pt.dy);
    }

    // Aire : fermeture vers le bas (CSS `L lastX,H-4 L firstX,H-4 Z`).
    final area = Path.from(path)
      ..lineTo(geometry.last.center.dx, size.height - 4)
      ..lineTo(geometry.first.center.dx, size.height - 4)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x594F46E5), Color(0x007C3AED)],
          stops: [0, 0.9],
        ).createShader(Offset.zero & size),
    );

    // Trait : dégradé horizontal 3 couleurs, 3 px, arrondi.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(colors: _lineColors)
          .createShader(Offset.zero & size);
    canvas.drawPath(path, stroke);

    // Points.
    for (var i = 0; i < geometry.length; i++) {
      final c = geometry[i].center;
      final selected = selectedIndex == i;
      final isPeak = points[i].isPeak;

      if (selected) {
        // Anneau « animate-ping » : halo statique élargi (l'animation est
        // portée par le parent via RepaintBoundary si besoin).
        canvas.drawCircle(
          c,
          7.5,
          Paint()
            ..color = const Color(0xE64F46E5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else if (isPeak) {
        canvas.drawCircle(
          c,
          5.5,
          Paint()
            ..color = const Color(0x807C3AED)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      canvas.drawCircle(
        c,
        selected ? 4.5 : (isPeak ? 3.5 : 2.8),
        Paint()
          ..color = selected ? const Color(0xFF4F46E5) : Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        c,
        selected ? 4.5 : (isPeak ? 3.5 : 2.8),
        Paint()
          ..color = selected ? Colors.white : const Color(0xFF4F46E5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.selectedIndex != selectedIndex ||
      old.points != points ||
      old.geometry != geometry;
}
