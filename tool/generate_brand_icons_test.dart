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

/// 64px보다 작은 아이콘은 단순형(파형 2개·글줄 2개)으로 그린다.
SoriLogoPainter _rounded(int size) => SoriLogoPainter(simple: size < 64);

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

  // 브랜드 에셋(PNG): 심볼, 앱 아이콘(스토어용 꽉 찬 사각형), 작은 favicon
  const brand = 'brand/png';
  for (final px in [32, 64, 128, 256, 512, 1024]) {
    icons.add(_Icon('$brand/sori_symbol_$px.png', px, _rounded(px)));
  }
  for (final px in [16, 32, 48]) {
    icons.add(_Icon('$brand/favicon_$px.png', px, _rounded(px)));
  }
  icons
    ..add(const _Icon('$brand/sori_app_icon_512.png', 512, _ios))
    ..add(const _Icon('$brand/sori_app_icon_1024.png', 1024, _ios));
  return icons;
}

// ------------------------------------------------------------- SVG 원본

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// 심볼 SVG. [size] 크기의 viewBox에 [LogoGeometry] 좌표를 그대로 옮긴다.
String symbolSvg({
  LogoBackground background = LogoBackground.rounded,
  bool simple = false,
  double scale = 1,
  int size = 1024,
}) {
  String n(double v) => (v * size).toStringAsFixed(1);
  final g = StringBuffer();
  if (background == LogoBackground.rounded) {
    g.writeln(
      '  <rect width="$size" height="$size" rx="${n(LogoGeometry.cornerRatio)}" '
      'fill="${_hex(LogoGeometry.background)}"/>',
    );
  } else if (background == LogoBackground.square) {
    g.writeln(
      '  <rect width="$size" height="$size" fill="${_hex(LogoGeometry.background)}"/>',
    );
  }
  // 그림 크기·위치(SoriLogoPainter.paint와 같은 변환)
  final t = size * (0.5 - 0.5 * scale + LogoGeometry.shiftX * scale);
  final ty = size * (0.5 - 0.5 * scale);
  g.writeln(
    '  <g transform="translate(${t.toStringAsFixed(1)} ${ty.toStringAsFixed(1)}) '
    'scale($scale)">',
  );
  const l = LogoGeometry.pageLeft, top = LogoGeometry.pageTop;
  const r = LogoGeometry.pageRight, b = LogoGeometry.pageBottom;
  const k = LogoGeometry.pageRadius, f = LogoGeometry.pageFold;
  final page =
      'M${n(l + k)} ${n(top)} L${n(r - f)} ${n(top)} L${n(r)} ${n(top + f)} '
      'L${n(r)} ${n(b - k)} A${n(k)} ${n(k)} 0 0 1 ${n(r - k)} ${n(b)} '
      'L${n(l + k)} ${n(b)} A${n(k)} ${n(k)} 0 0 1 ${n(l)} ${n(b - k)} '
      'L${n(l)} ${n(top + k)} A${n(k)} ${n(k)} 0 0 1 ${n(l + k)} ${n(top)} Z';
  g
    ..writeln(
      '    <defs><clipPath id="page"><path d="$page"/></clipPath></defs>',
    )
    ..writeln('    <path d="$page" fill="${_hex(LogoGeometry.paper)}"/>')
    ..writeln(
      '    <path d="M${n(r - f)} ${n(top)} L${n(r - f)} ${n(top + f)} '
      'L${n(r)} ${n(top + f)} Z" fill="${_hex(LogoGeometry.fold)}"/>',
    );
  final barWidth = simple ? LogoGeometry.barWidthSimple : LogoGeometry.barWidth;
  final bars = simple ? LogoGeometry.barsSimple : LogoGeometry.bars;
  g.writeln(
    '    <g stroke="${_hex(LogoGeometry.wave)}" stroke-width="${n(barWidth)}" '
    'stroke-linecap="round">',
  );
  for (final (x, length) in bars) {
    final half = length / 2 - barWidth / 2;
    g.writeln(
      '      <line x1="${n(x)}" y1="${n(LogoGeometry.midY - half)}" '
      'x2="${n(x)}" y2="${n(LogoGeometry.midY + half)}"/>',
    );
  }
  g.writeln('    </g>');
  final lineWidth = simple
      ? LogoGeometry.lineWidthSimple
      : LogoGeometry.lineWidth;
  final start = simple ? bars.last.$1 : LogoGeometry.flowStart;
  final flow =
      'x1="${n(start)}" y1="${n(LogoGeometry.midY)}" '
      'x2="${n(LogoGeometry.flowEnd)}" y2="${n(LogoGeometry.midY)}"';
  g
    ..writeln(
      '    <line $flow stroke="${_hex(LogoGeometry.wave)}" '
      'stroke-width="${n(lineWidth)}" stroke-linecap="round"/>',
    )
    ..writeln(
      '    <line $flow stroke="${_hex(LogoGeometry.ink)}" '
      'stroke-width="${n(lineWidth)}" stroke-linecap="round" clip-path="url(#page)"/>',
    )
    ..writeln(
      '    <g stroke="${_hex(LogoGeometry.ink)}" stroke-width="${n(lineWidth)}" '
      'stroke-linecap="round">',
    );
  for (final (y, x1, x2)
      in simple ? LogoGeometry.linesSimple : LogoGeometry.lines) {
    g.writeln(
      '      <line x1="${n(x1)}" y1="${n(y)}" x2="${n(x2)}" y2="${n(y)}"/>',
    );
  }
  g
    ..writeln('    </g>')
    ..writeln('  </g>');
  return '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" '
      'viewBox="0 0 $size $size">\n<title>소리노트 Sori Note</title>\n$g</svg>\n';
}

/// 워드마크 SVG: 심볼 + 글자. 글꼴은 Pretendard → Noto Sans KR → 시스템 글꼴 순서로 쓴다.
String wordmarkSvg({
  required String text,
  required double fontSize,
  required int width,
}) {
  const height = 160;
  final symbol = symbolSvg(size: height)
      .replaceFirst(RegExp(r'<svg[^>]*>\n<title>[^<]*</title>\n'), '')
      .replaceFirst('</svg>\n', '');
  return '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" '
      'viewBox="0 0 $width $height">\n<title>$text</title>\n'
      '<g>\n$symbol</g>\n'
      '<text x="${height + 36}" y="${height / 2}" dominant-baseline="central" '
      'font-family="Pretendard, \'Noto Sans KR\', \'Apple SD Gothic Neo\', \'Malgun Gothic\', sans-serif" '
      'font-size="$fontSize" font-weight="800" letter-spacing="-1" '
      'fill="${_hex(const Color(0xFF303A38))}">$text</text>\n</svg>\n';
}

Map<String, String> _svgs() => {
  'brand/svg/sori_symbol.svg': symbolSvg(),
  'brand/svg/sori_symbol_small.svg': symbolSvg(simple: true, size: 64),
  'brand/svg/sori_app_icon.svg': symbolSvg(
    background: LogoBackground.square,
    scale: 0.92,
  ),
  'brand/svg/sori_symbol_mark_only.svg': symbolSvg(
    background: LogoBackground.none,
  ),
  'brand/svg/sori_wordmark_ko.svg': wordmarkSvg(
    text: '소리노트',
    fontSize: 96,
    width: 640,
  ),
  'brand/svg/sori_wordmark_en.svg': wordmarkSvg(
    text: 'Sori Note',
    fontSize: 92,
    width: 700,
  ),
  'web/favicon.svg': symbolSvg(simple: true, size: 64),
};

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
    final svgs = _svgs();
    svgs.forEach((path, svg) {
      final out = _preview.isEmpty
          ? File(path)
          : File('$_preview/${path.replaceAll('/', '__')}');
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(svg);
    });
    // ignore: avoid_print
    print('아이콘 ${icons.length}개, SVG ${svgs.length}개를 만들었습니다.');
  });
}
