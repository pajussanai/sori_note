import 'package:flutter/material.dart';

/// 소리노트 색상. 아이보리·흰 바탕에 피치·라벤더를 포인트로 쓴다.
///
/// 피치(#F2B18F)·라벤더(#A99BE0)는 흰 글자를 올리면 읽기 어려워서, 글자·선택 메뉴·
/// 주요 버튼에는 같은 계열의 진한 톤([primary], [peachDeep])을 쓴다.
abstract final class AppColors {
  // ----- 핵심 컬러
  static const peach = Color(0xFFF2B18F);
  static const lavender = Color(0xFFA99BE0);
  static const ivory = Color(0xFFF7F3EC);

  // ----- 보조 컬러
  static const pink = Color(0xFFEBC5D1);
  static const mint = Color(0xFFB8D5C9);

  /// 옅은 바탕(칩·안내 상자·표시)
  static const peachLight = Color(0xFFFCEDE4);
  static const lavenderLight = Color(0xFFEFECFA);
  static const pinkLight = Color(0xFFF9ECF0);
  static const mintLight = Color(0xFFEAF3EF);

  /// 글자용 진한 톤
  static const peachDeep = Color(0xFFB8673F);
  static const mintDeep = Color(0xFF3F7F67);
  static const pinkDeep = Color(0xFFA9566F);

  /// 핵심 액션·선택된 메뉴(진한 라벤더). 흰 글자를 올려도 잘 읽힌다.
  static const primary = Color(0xFF6B5CB8);

  /// 보조 강조: 아이콘, 링크성 글자(라벤더 중간 톤)
  static const accent = Color(0xFF7D6FC8);

  /// 선택된 칩·안내 상자 바탕(옅은 라벤더)
  static const primaryLight = lavenderLight;

  /// 화면 바탕(아이보리)
  static const background = ivory;

  /// 카드·입력 영역 바탕(흰색)
  static const surface = Color(0xFFFFFFFF);

  /// 테두리·구분선
  static const track = Color(0xFFEAE3E8);

  /// 본문(차콜)
  static const textMain = Color(0xFF38363D);
  static const textSub = Color(0xFF6E6A74);

  /// 흐린 글자(날짜, 비활성 아이콘)
  static const textMuted = Color(0xFFA6A1AB);

  /// 빈 화면 아이콘
  static const iconMuted = lavender;

  static const danger = Color(0xFFC9554A);

  /// 녹음 중(따뜻한 피치 레드) · 일시정지(라벤더) · 완료(진한 민트)
  static const recording = Color(0xFFE0795C);
  static const paused = Color(0xFF8C7DD6);
  static const done = mintDeep;
}

/// 피치 → 라벤더. 카드 테두리·얇은 강조선에만 쓴다(면을 채우지 않는다).
const brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.peach, AppColors.lavender],
);

/// 아주 옅은 그림자. 떠 있는 버튼과 시트에만 쓴다(카드는 테두리로 구분).
const softShadow = [
  BoxShadow(color: Color(0x1438363D), blurRadius: 14, offset: Offset(0, 4)),
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
    secondary: AppColors.accent,
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
      iconColor: AppColors.accent,
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
      actionTextColor: AppColors.peach,
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

/// 분류별 색(옅은 바탕, 글자). 피치·라벤더·민트·핑크 안에서 고른다.
({Color bg, Color fg}) categoryColors(String category) => switch (category) {
  '업무' => (bg: AppColors.lavenderLight, fg: AppColors.primary),
  '회의' => (bg: AppColors.mintLight, fg: AppColors.mintDeep),
  '아이디어' => (bg: AppColors.peachLight, fg: AppColors.peachDeep),
  '개인' => (bg: AppColors.pinkLight, fg: AppColors.pinkDeep),
  '일정' => (bg: AppColors.lavenderLight, fg: AppColors.accent),
  '쇼핑·할 일' => (bg: AppColors.peachLight, fg: AppColors.peachDeep),
  _ => (bg: const Color(0xFFF1ECE4), fg: AppColors.textSub),
};

/// 테두리에만 은은한 피치→라벤더 그라데이션을 두른 흰 카드.
/// 면은 흰색 그대로이며, 그라데이션은 얇은 외곽선으로만 보인다.
class GradientBorderCard extends StatelessWidget {
  const GradientBorderCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.gradient = brandGradient,
    this.width = 1.4,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Gradient gradient;
  final double width;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(width),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(cardRadius - width),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
