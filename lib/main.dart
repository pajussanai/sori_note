import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'app/services.dart';
import 'app/theme.dart';
import 'features/auth/auth_gate.dart';

void main() {
  runApp(const SoriNoteApp());
}

class SoriNoteApp extends StatelessWidget {
  const SoriNoteApp({super.key, this.services});

  /// 테스트에서 인증·저장소·AI·마이크를 가짜로 바꿔 끼운다.
  /// 없으면 Supabase와 기기 음성 인식을 쓴다.
  final AppServices? services;

  @override
  Widget build(BuildContext context) {
    final services = this.services;
    return MaterialApp(
      title: '소리노트',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: services != null
          ? AuthGate(services: services)
          : const SupabaseBootstrap(),
    );
  }
}
