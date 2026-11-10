import 'package:flutter/material.dart';

/// 앱에서 쓰는 색상. 종이 같은 바탕에 차분한 청록 잉크색을 포인트로 쓴다.
abstract final class AppColors {
  /// 버튼·강조색(청록). 흰 글자를 올려도 잘 읽힌다.
  static const primary = Color(0xFF2E6E73);

  /// 화면 바탕(종이색)
  static const background = Color(0xFFF7F5F0);

  /// 카드·입력 영역 바탕
  static const surface = Color(0xFFFFFEFB);

  static const textMain = Color(0xFF2B2D2F);
  static const textSub = Color(0xFF6E7378);
  static const danger = Color(0xFFC0463F);

  /// 흐린 글자(날짜, 비활성 아이콘)
  static const textMuted = Color(0xFFA3A8AD);

  /// 빈 화면 아이콘
  static const iconMuted = Color(0xFFBFD6D7);

  /// 구분선
  static const track = Color(0xFFE7E3DA);

  /// 선택·강조 배경(연한 청록)
  static const primaryLight = Color(0xFFDDECEB);

  /// 녹음 중 표시(따뜻한 빨강)
  static const recording = Color(0xFFD9534F);
}

/// 부드러운 그림자. 카드와 입력 영역에 함께 쓴다.
const softShadow = [
  BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 3)),
];

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
    error: AppColors.danger,
  );
  const stadium = StadiumBorder();

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textMain,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: stadium,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: stadium),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: stadium),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textMain,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.track, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
    ),
  );
}

/// 입력창 공통 모양: 둥근 모서리, 평소에는 테두리 없음, 입력 중에는 청록 테두리.
InputDecoration appFieldDecoration({
  required Color fillColor,
  String? hintText,
  TextStyle? hintStyle,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  bool? isDense,
  EdgeInsetsGeometry? contentPadding,
  double radius = 14,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide.none,
  );

  return InputDecoration(
    hintText: hintText,
    hintStyle: hintStyle,
    labelText: labelText,
    filled: true,
    fillColor: fillColor,
    isDense: isDense,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: contentPadding,
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  );
}
