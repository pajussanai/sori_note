// 소리노트 앱 아이콘·로딩 화면 이미지를 앱 로고(SoriLogoPainter)로 다시 만든다.
//
//   flutter test tool/generate_brand_icons_test.dart
//
// 미리 보기만 하려면 --dart-define=BRAND_PREVIEW=<폴더>를 붙인다(프로젝트 파일은 그대로).
// iOS 아이콘은 투명도(알파 채널)가 없어야 하므로, 만든 뒤
// tool/flatten_ios_icons.ps1로 알파를 없앤다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sori_note/widgets/app_logo.dart';

const _preview = String.fromEnvironment('BRAND_PREVIEW');

class _Icon {
  const _Icon(this.path, this.size, this.painter);

  final String path;
  final int size;
  final SoriLogoPainter painter;
}

SoriLogoPainter _rounded(int size) =>
    SoriLogoPainter(simple: size < SoriLogoPainter.simpleBelow);

/// OS가 모양을 잘라 내는 아이콘: 꽉 찬 바탕, 그림은 안전 영역 안으로
const _maskable = SoriLogoPainter(
  background: LogoBackground.square,
  scale: 0.8,
);
const _ios = SoriLogoPainter(background: LogoBackground.square, scale: 0.92);

/// Android 적응형 아이콘(108dp 중 지름 66dp 원이 안전 영역)
const _adaptiveBackground = SoriLogoPainter(
  background: LogoBackground.square,
  paintForeground: false,
);
const _adaptiveForeground = SoriLogoPainter(
  background: LogoBackground.none,
  scale: 0.62,
);

/// 로딩 화면 가운데 그림
const _splash = SoriLogoPainter();

List<_Icon> _icons() {
  final icons = <_Icon>[
    // 웹(PWA·favicon)
    _Icon('web/favicon.png', 48, _rounded(48)),
    _Icon('web/icons/Icon-192.png', 192, _rounded(192)),
    _Icon('web/icons/Icon-512.png', 512, _rounded(512)),
    const _Icon('web/icons/Icon-maskable-192.png', 192, _maskable),
    const _Icon('web/icons/Icon-maskable-512.png', 512, _maskable),
    const _Icon('web/icons/apple-touch-icon.png', 180, _ios),
  ];

  // Android
  const densities = {
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
  };
  const res = 'android/app/src/main/res';
  densities.forEach((name, d) {
    final legacy = (48 * d).round();
    final layer = (108 * d).round();
    icons
      ..add(
        _Icon('$res/mipmap-$name/ic_launcher.png', legacy, _rounded(legacy)),
      )
      ..add(
        _Icon(
          '$res/mipmap-$name/ic_launcher_background.png',
          layer,
          _adaptiveBackground,
        ),
      )
      ..add(
        _Icon(
          '$res/mipmap-$name/ic_launcher_foreground.png',
          layer,
          _adaptiveForeground,
        ),
      )
      ..add(
        _Icon('$res/drawable-$name/splash_logo.png', (96 * d).round(), _splash),
      );
  });

  // iOS 홈 화면 아이콘(파일 이름의 크기·배율로 픽셀 크기를 정한다)
  const iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final pattern = RegExp(r'^Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$');
  for (final file in Directory(iosIcons).listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    final m = pattern.firstMatch(name);
    if (m == null) continue;
    final px = (double.parse(m[1]!) * int.parse(m[2]!)).round();
    icons.add(_Icon('$iosIcons/$name', px, _ios));
  }

  // iOS 로딩 화면(LaunchScreen.storyboard에서 96pt로 쓴다)
  const launch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
  icons
    ..add(const _Icon('$launch/LaunchImage.png', 96, _splash))
    ..add(const _Icon('$launch/LaunchImage@2x.png', 192, _splash))
    ..add(const _Icon('$launch/LaunchImage@3x.png', 288, _splash));
  return icons;
}

Future<List<int>> _render(_Icon icon) async {
  final recorder = ui.PictureRecorder();
  final size = icon.size.toDouble();
  icon.painter.paint(Canvas(recorder), Size.square(size));
  final image = await recorder.endRecording().toImage(icon.size, icon.size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  test('브랜드 아이콘 만들기', () async {
    final icons = _icons();
    for (final icon in icons) {
      final out = _preview.isEmpty
          ? File(icon.path)
          : File('$_preview/${icon.path.replaceAll('/', '__')}');
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(await _render(icon));
    }
    // ignore: avoid_print
    print('아이콘 ${icons.length}개를 만들었습니다.');
  });
}
