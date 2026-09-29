import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final srcPath =
      'C:/Users/migco/.gemini/antigravity-ide/brain/210b7fa9-5f4a-4de9-807e-9a7f36eedd16/media__1785108977604.jpg';
  final bytes = File(srcPath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    stderr.writeln('Failed to decode image');
    return;
  }

  final pngBytes = img.encodePng(decoded);

  final targets = [
    'assets/images/ic_launcher.png',
    'assets/images/lynkstor_logo_dark.png',
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png',
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png',
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png',
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
  ];

  for (final t in targets) {
    File(t).writeAsBytesSync(pngBytes);
    stdout.writeln('Wrote PNG: $t');
  }

  stdout.writeln('Conversion to PNG complete!');
}
