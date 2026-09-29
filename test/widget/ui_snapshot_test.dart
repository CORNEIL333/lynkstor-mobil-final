import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/ui_fixture.dart';

void main() {
  const stage = String.fromEnvironment('UI_CAPTURE', defaultValue: 'after');
  for (final dark in [false, true]) {
    testWidgets('dashboard capture ${dark ? "dark" : "light"}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fixture = UiFixture();
      final router = fixture.router();
      addTearDown(router.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(fixture.app(router, dark: dark, captureKey: key));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await tester.runAsync(() async {
        final directory = Directory('build/ui-review')..createSync(recursive: true);
        await File('${directory.path}/dashboard-$stage-${dark ? "dark" : "light"}.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
      image.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
