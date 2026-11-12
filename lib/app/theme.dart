import 'package:flutter/material.dart';

/// 소리노트 색상. 아이보리·흰 바탕에 딥 틸을 핵심 액션에, 민트를 보조 정보에 쓴다.
abstract final class AppColors {
  /// 핵심 액션·선택된 메뉴(딥 틸). 흰 글자를 올려도 잘 읽힌다.
  static const primary = Color(0xFF356B65);

  /// 보조 강조(틸): 아이콘, 링크성 글자
  static const teal = Color(0xFF548C83);

  /// 보조 정보·태그·상태(소프트 민트)
  static const mint = Color(0xFFB8D5C9);

  /// 민트보다 옅은 바탕(선택된 칩, 안내 상자)
  static const primaryLight = Color(0xFFE6F0EB);

  /// 화면 바탕(아이보리)
  static const background = Color(0xFFF7F8F3);

  /// 카드·입력 영역 바탕(흰색)
  static const surface = Color(0xFFFFFFFF);

  /// 테두리·구분선
  static const track = Color(0xFFE8ECE7);

  /// 본문(차콜)
  static const textMain = Color(0xFF303A38);
  static const textSub = Color(0xFF66716E);

  /// 흐린 글자(날짜, 비활성 아이콘)
  static const textMuted = Color(0xFF9AA4A0);

  /// 빈 화면 아이콘
  static const iconMuted = Color(0xFFB8D5C9);

  static const danger = Color(0xFFC0504A);

  /// 녹음 중 표시(차분한 빨강). 녹음 상태에만 쓴다.
  static const recording = Color(0xFFD0605A);

  /// 일시정지 표시(차분한 호박색)
  static const paused = Color(0xFFC48A2C);
}

/// 아주 옅은 그림자. 떠 있는 버튼과 시트에만 쓴다(카드는 테두리로 구분).
const softShadow = [
  BoxShadow(color: Color(0x0F1E2B28), blurRadius: 12, offset: Offset(0, 2)),
];

/// 카드 모양: 흰 바탕, 옅은 테두리, 둥근 모서리
const cardRadius = 16.0;
final cardShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(cardRadius),
  side: const BorderSide(color: AppColors.track),
);

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.teal,
    secondaryContainer: AppColors.primaryLight,
    onSecondaryContainer: AppColors.primary,
    surface: AppColors.surface,
    onSurface: AppColors.textMain,
    outline: AppColors.track,
    outlineVariant: AppColors.track,
    error: AppColors.danger,
  );
  const stadium = StadiumBorder();

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.track,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textMain,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textMain,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: stadium,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.track),
        backgroundColor: AppColors.surface,
        shape: stadium,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        shape: stadium,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 3,
      shape: CircleBorder(),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primaryLight,
      side: const BorderSide(color: AppColors.track),
      labelStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMain),
      secondaryLabelStyle: const TextStyle(
        fontSize: 13.5,
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
      checkmarkColor: AppColors.primary,
      shape: const StadiumBorder(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primaryLight,
      elevation: 0,
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primaryLight,
      selectedIconTheme: IconThemeData(color: AppColors.primary),
      unselectedIconTheme: IconThemeData(color: AppColors.textMuted),
      selectedLabelTextStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontSize: 12,
        color: AppColors.textMuted,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primaryLight
              : AppColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textSub,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.track)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: const BorderSide(color: AppColors.textMuted, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.primary : null,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.primary : null,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.teal,
      textColor: AppColors.textMain,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.track,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textMain,
      actionTextColor: AppColors.mint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.track, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.track,
    ),
  );
}

/// 입력창 공통 모양: 둥근 모서리, 옅은 테두리, 입력 중에는 딥 틸 테두리.
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
    borderSide: const BorderSide(color: AppColors.track),
  );

  return InputDecoration(
    hintText: hintText,
    hintStyle: hintStyle ?? const TextStyle(color: AppColors.textMuted),
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
