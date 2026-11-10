import 'package:flutter/material.dart';

import '../app/theme.dart';

/// 소리노트 로고: 청록 원 안의 소리 물결.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
        boxShadow: softShadow,
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        size: size * 0.55,
        color: Colors.white,
      ),
    );
  }
}
