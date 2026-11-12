import 'package:flutter/material.dart';

import '../app/theme.dart';

/// 소리노트 심볼: 왼쪽의 음성 파형이 오른쪽 메모 문서로 이어지는 모양(평면 벡터).
///
/// 앱 안 로고, 앱 아이콘(Android·iOS·PWA·favicon), 로딩 화면 이미지, SVG 원본은 모두
/// [LogoGeometry]의 같은 좌표로 그린다(tool/generate_brand_icons_test.dart).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: SoriLogoPainter(simple: size < SoriLogoPainter.simpleBelow),
    );
  }
}

/// 심볼 + 한글 워드마크(필요하면 영문 함께)
class AppWordmark extends StatelessWidget {
  const AppWordmark({
    super.key,
    this.logoSize = 32,
    this.fontSize = 20,
    this.english = false,
  });

  final double logoSize;
  final double fontSize;

  /// 'Sori Note'를 함께 보여 준다.
  final bool english;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        SizedBox(width: logoSize * 0.3),
        Text(
          '소리노트',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.textMain,
          ),
        ),
        if (english) ...[
          const SizedBox(width: 6),
          Text(
            'Sori Note',
            style: TextStyle(
              fontSize: fontSize * 0.62,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ],
      ],
    );
  }
}

/// 로고 바탕 모양
enum LogoBackground {
  /// 둥근 사각형(앱 안 로고, PWA, favicon, Android 기본 아이콘)
  rounded,

  /// 꽉 찬 사각형(iOS 아이콘, maskable 아이콘처럼 OS가 모양을 잘라 내는 곳)
  square,

  /// 바탕 없음(Android 적응형 아이콘 전경)
  none,
}

/// 심볼 좌표. 한 변을 1로 본 비율이며 그림과 SVG가 함께 쓴다.
abstract final class LogoGeometry {
  /// 둥근 사각형 바탕의 모서리 비율
  static const cornerRatio = 0.23;

  static const background = AppColors.primary; // 진한 라벤더
  static const wave = AppColors.peach; // 피치 파형
  static const paper = Color(0xFFFFFFFF);
  static const fold = AppColors.pink;
  static const ink = AppColors.lavender; // 문서 안 글줄

  /// 문서(세로로 긴 메모지, 오른쪽 위를 접음)
  static const pageLeft = 0.46, pageTop = 0.22, pageRight = 0.80;
  static const pageBottom = 0.78, pageRadius = 0.06, pageFold = 0.11;

  /// 파형의 가운데 높이(문서 안 첫 글줄과 같은 높이로 이어진다)
  static const midY = 0.50;

  /// 파형 막대 (x, 길이). 작은 크기에서는 2개만 쓴다.
  static const bars = [(0.205, 0.17), (0.29, 0.36), (0.375, 0.24)];
  static const barsSimple = [(0.25, 0.22), (0.355, 0.40)];
  static const barWidth = 0.056;
  static const barWidthSimple = 0.075;

  /// 파형에서 문서로 이어지는 선(가운데 글줄): 문서 밖은 민트, 안은 틸
  static const flowStart = 0.375, flowEnd = 0.70;

  /// 문서 안 나머지 글줄 (y, 시작 x, 끝 x)
  static const lines = [(0.385, 0.53, 0.66), (0.615, 0.53, 0.72)];
  static const linesSimple = [(0.635, 0.53, 0.70)];
  static const lineWidth = 0.044;
  static const lineWidthSimple = 0.06;

  /// 그림 전체가 가운데에 오도록 옮기는 양
  static const shiftX = 0.02;
}

/// 로고 그리기.
class SoriLogoPainter extends CustomPainter {
  const SoriLogoPainter({
    this.background = LogoBackground.rounded,
    this.scale = 1,
    this.simple = false,
    this.paintBackground = true,
    this.paintForeground = true,
  });

  final LogoBackground background;

  /// 그림(파형·문서)의 크기. 안전 영역 안에 넣을 때 줄인다.
  final double scale;

  /// 작은 크기(favicon 등)에서는 파형·글줄을 줄이고 선을 굵게 한다.
  final bool simple;

  /// Android 적응형 아이콘처럼 바탕과 그림을 따로 그릴 때 쓴다.
  final bool paintBackground;
  final bool paintForeground;

  /// 이 크기(논리 픽셀)보다 작으면 [simple]로 그린다.
  static const simpleBelow = 40.0;

  static const cornerRatio = LogoGeometry.cornerRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.scale(s);
    if (paintBackground && background != LogoBackground.none) {
      final paint = Paint()..color = LogoGeometry.background;
      const rect = Rect.fromLTWH(0, 0, 1, 1);
      if (background == LogoBackground.rounded) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(cornerRatio)),
          paint,
        );
      } else {
        canvas.drawRect(rect, paint);
      }
    }
    if (paintForeground) {
      canvas.translate(0.5, 0.5);
      canvas.scale(scale);
      canvas.translate(-0.5 + LogoGeometry.shiftX, -0.5);
      _paintSymbol(canvas);
    }
    canvas.restore();
  }

  static Path pagePath() {
    const l = LogoGeometry.pageLeft, t = LogoGeometry.pageTop;
    const r = LogoGeometry.pageRight, b = LogoGeometry.pageBottom;
    const k = LogoGeometry.pageRadius, f = LogoGeometry.pageFold;
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

  static Path foldPath() {
    const r = LogoGeometry.pageRight, t = LogoGeometry.pageTop;
    const f = LogoGeometry.pageFold;
    return Path()
      ..moveTo(r - f, t)
      ..lineTo(r - f, t + f)
      ..lineTo(r, t + f)
      ..close();
  }

  void _paintSymbol(Canvas canvas) {
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    final page = pagePath();
    canvas.drawPath(page, Paint()..color = LogoGeometry.paper);
    canvas.drawPath(foldPath(), Paint()..color = LogoGeometry.fold);

    // 파형
    final barWidth = simple
        ? LogoGeometry.barWidthSimple
        : LogoGeometry.barWidth;
    final wave = stroke(LogoGeometry.wave, barWidth);
    for (final (x, length)
        in simple ? LogoGeometry.barsSimple : LogoGeometry.bars) {
      final half = length / 2 - barWidth / 2;
      canvas.drawLine(
        Offset(x, LogoGeometry.midY - half),
        Offset(x, LogoGeometry.midY + half),
        wave,
      );
    }

    // 파형에서 문서로 이어지는 가운데 선: 문서 밖은 민트, 안은 틸
    final lineWidth = simple
        ? LogoGeometry.lineWidthSimple
        : LogoGeometry.lineWidth;
    final start = simple
        ? LogoGeometry.barsSimple.last.$1
        : LogoGeometry.flowStart;
    const a = Offset(0, LogoGeometry.midY);
    canvas.drawLine(
      a.translate(start, 0),
      a.translate(LogoGeometry.flowEnd, 0),
      stroke(LogoGeometry.wave, lineWidth),
    );
    canvas.save();
    canvas.clipPath(page);
    canvas.drawLine(
      a.translate(start, 0),
      a.translate(LogoGeometry.flowEnd, 0),
      stroke(LogoGeometry.ink, lineWidth),
    );
    canvas.restore();

    // 나머지 글줄
    final ink = stroke(LogoGeometry.ink, lineWidth);
    for (final (y, x1, x2)
        in simple ? LogoGeometry.linesSimple : LogoGeometry.lines) {
      canvas.drawLine(Offset(x1, y), Offset(x2, y), ink);
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
