import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../services/auth_service.dart';
import '../shell/app_shell.dart';
import 'auth_page.dart';

/// 로그인 상태에 따라 로그인 화면 또는 메모 목록을 보여 준다.
///
/// 로그인하지 않은 사용자는 메모에 접근할 수 없다(서버에서는 RLS가 한 번 더 막는다).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final auth = services.auth;
    return StreamBuilder<AppUser?>(
      stream: auth.userChanges,
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return AuthPage(auth: auth);
        // 계정이 바뀌면 이전 사용자의 화면 상태를 남기지 않는다.
        return AppShell(key: ValueKey(user.id), user: user, services: services);
      },
    );
  }
}
