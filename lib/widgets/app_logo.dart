import 'package:flutter/material.dart';

import '../app/theme.dart';

/// 소리노트 로고: 노트 한 장에서 빛나는 음파가 번져 나오는 모습('살아있는 노트').
///
/// 앱 아이콘(Android·iOS·PWA·favicon)과 로딩 화면 이미지는 모두
/// [SoriLogoPainter]로 만든다(tool/generate_brand_icons_test.dart).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * SoriLogoPainter.cornerRatio),
        boxShadow: softShadow,
      ),
      child: CustomPaint(
        size: Size.square(size),
        painter: SoriLogoPainter(simple: size < SoriLogoPainter.simpleBelow),
      ),
    );
  }
}

/// 로고 바탕 모양
enum LogoBackground {
  /// 둥근 사각형(앱 안 로고, PWA, favicon, Android 기본 아이콘)
  rounded,

  /// 꽉 찬 사각형(iOS 아이콘, maskable 아이콘처럼 OS가 모양을 잘라 내는 곳)
  square,

  /// 바탕 없음(Android 적응형 아이콘 전경, 로딩 화면 그림)
  none,
}

/// 로고 그리기. 모든 좌표는 한 변을 1로 본 비율이다.
class SoriLogoPainter extends CustomPainter {
  const SoriLogoPainter({
    this.background = LogoBackground.rounded,
    this.scale = 1,
    this.simple = false,
    this.paintBackground = true,
    this.paintForeground = true,
  });

  final LogoBackground background;

  /// 그림(노트·음파)의 크기. 안전 영역 안에 넣을 때 줄인다.
  final double scale;

  /// 작은 크기(favicon 등)에서는 음파 수를 줄이고 선을 굵게 한다.
  final bool simple;

  /// Android 적응형 아이콘처럼 바탕과 그림을 따로 그릴 때 쓴다.
  final bool paintBackground;
  final bool paintForeground;

  /// 이 크기(논리 픽셀)보다 작으면 [simple]로 그린다.
  static const simpleBelow = 64.0;

  /// 둥근 사각형 바탕의 모서리 비율
  static const cornerRatio = 0.23;

  static const _tealLight = Color(0xFF3A8A8F);
  static const _tealDark = Color(0xFF245B5F);
  static const _paper = Color(0xFFFBF9F4);
  static const _paperFold = Color(0xFFDCD6C8);
  static const _glow = Color(0xFFCFEDE9);

  // 노트 한 장(세로로 긴 종이, 오른쪽 위 모서리를 접음)
  static const _pageLeft = 0.17, _pageTop = 0.19, _pageRight = 0.57;
  static const _pageBottom = 0.81, _pageRadius = 0.055, _fold = 0.1;

  /// 노트 가운데. 안의 소리 막대와 밖으로 번지는 음파가 여기를 중심으로 한다.
  static const _center = Offset(0.37, 0.5);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.scale(s);
    if (paintBackground && background != LogoBackground.none) {
      _paintBackground(canvas);
    }
    if (paintForeground) {
      canvas.translate(0.5, 0.5);
      canvas.scale(scale);
      // 노트와 오른쪽 음파를 합친 그림이 가운데에 오도록 옮긴다.
      canvas.translate(-0.5 + 0.025, -0.5);
      _paintNote(canvas);
    }
    canvas.restore();
  }

  void _paintBackground(Canvas canvas) {
    const rect = Rect.fromLTWH(0, 0, 1, 1);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_tealLight, AppColors.primary, _tealDark],
        stops: [0, 0.55, 1],
      ).createShader(rect);
    if (background == LogoBackground.rounded) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(cornerRatio)),
        paint,
      );
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  Path _pagePath() {
    const l = _pageLeft, t = _pageTop, r = _pageRight, b = _pageBottom;
    const k = _pageRadius, f = _fold;
    return Path()
      ..moveTo(l + k, t)
      ..lineTo(r - f, t)
      ..lineTo(r, t + f)
      ..lineTo(r, b - k)
      ..arcToPoint(const Offset(r - k, b), radius: const Radius.circular(k))
      ..lineTo(l + k, b)
      ..arcToPoint(const Offset(l, b - k), radius: const Radius.circular(k))
      ..lineTo(l, t + k)
      ..arcToPoint(const Offset(l + k, t), radius: const Radius.circular(k))
      ..close();
  }

  void _paintNote(Canvas canvas) {
    final page = _pagePath();

    // 종이 그림자
    canvas.drawPath(
      page.shift(const Offset(0, 0.018)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.02),
    );
    canvas.drawPath(page, Paint()..color = _paper);

    // 접힌 모서리
    const r = _pageRight, t = _pageTop, f = _fold;
    canvas.drawPath(
      Path()
        ..moveTo(r - f, t)
        ..lineTo(r - f, t + f * 0.82)
        ..quadraticBezierTo(r - f, t + f, r - f * 0.82, t + f)
        ..lineTo(r, t + f)
        ..close(),
      Paint()..color = _paperFold,
    );

    Paint line(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    // 노트 안: 소리 막대(예전 소리노트 표시 graphic_eq와 같은 비율)
    final barWidth = simple ? 0.05 : 0.034;
    final bars = simple
        ? const [(-0.07, 0.16), (0.0, 0.32), (0.07, 0.16)]
        : const [
            (-0.1, 0.07),
            (-0.05, 0.19),
            (0.0, 0.31),
            (0.05, 0.19),
            (0.1, 0.07),
          ];
    final barPaint = line(AppColors.primary, barWidth);
    for (final (dx, height) in bars) {
      final x = _center.dx + dx;
      final half = height / 2 - barWidth / 2;
      canvas.drawLine(
        Offset(x, _center.dy - half),
        Offset(x, _center.dy + half),
        barPaint,
      );
    }

    // 노트 밖: 오른쪽으로 번지는 음파. 번짐을 먼저 깔아 은은하게 빛나 보이게 한다.
    final waveWidth = simple ? 0.05 : 0.034;
    final waves = simple
        ? const [(0.3, 0.66)]
        : const [(0.29, 0.68), (0.39, 0.6)];
    for (final (radius, sweep) in waves) {
      final rect = Rect.fromCircle(center: _center, radius: radius);
      canvas.drawArc(
        rect,
        -sweep,
        sweep * 2,
        false,
        line(_glow.withValues(alpha: 0.38), waveWidth * 2.2)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, waveWidth * 0.8),
      );
      canvas.drawArc(rect, -sweep, sweep * 2, false, line(_glow, waveWidth));
    }
  }

  @override
  bool shouldRepaint(SoriLogoPainter old) =>
      old.background != background ||
      old.scale != scale ||
      old.simple != simple ||
      old.paintBackground != paintBackground ||
      old.paintForeground != paintForeground;
}
