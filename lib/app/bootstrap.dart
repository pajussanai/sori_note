import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/errors.dart';
import '../features/auth/auth_gate.dart';
import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/memo_repository.dart';
import '../services/local_store.dart';
import '../services/notifier.dart';
import '../services/polish_service.dart';
import '../services/speech_input.dart';
import '../widgets/status_view.dart';
import 'services.dart';

/// Supabase를 준비한 뒤 로그인/메모 화면을 보여 준다.
class SupabaseBootstrap extends StatefulWidget {
  const SupabaseBootstrap({super.key});

  @override
  State<SupabaseBootstrap> createState() => _SupabaseBootstrapState();
}

class _SupabaseBootstrapState extends State<SupabaseBootstrap> {
  late Future<AppServices> _ready = _initialize();

  Future<AppServices> _initialize() async {
    checkSupabaseConfig(url: supabaseUrl, key: supabasePublishableKey);
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
      // 디버그 로그에는 세션(토큰)과 요청 헤더가 출력되므로 끈다.
      debug: false,
    );
    final client = Supabase.instance.client;
    return AppServices(
      auth: SupabaseAuthService(client.auth),
      memos: SupabaseMemoRepository(client),
      polish: SupabasePolishService(client),
      createSpeechInput: DeviceSpeechInput.new,
      account: SupabaseAccountService(client),
      local: PrefsKeyValueStore(),
      notifier: createNotifier(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isSupabaseConfigured) return const SetupNeededPage();
    return FutureBuilder(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasData) return AuthGate(services: snapshot.data!);
        if (snapshot.hasError) {
          logError('Supabase 초기화 실패', snapshot.error!);
          final error = snapshot.error;
          return Scaffold(
            body: SafeArea(
              child: StatusView(
                icon: Icons.cloud_off_rounded,
                message: error is StateError
                    ? '앱 설정 오류: ${error.message}'
                    : '서버에 연결할 준비를 하지 못했습니다.\n잠시 후 다시 시도해 주세요.',
                actionLabel: '다시 시도',
                onAction: () => setState(() => _ready = _initialize()),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

/// 연결 정보 없이 빌드했을 때 보여 주는 안내(개발자용)
class SetupNeededPage extends StatelessWidget {
  const SetupNeededPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Supabase 연결 정보가 없습니다.\n'
              'SUPABASE_URL과 SUPABASE_PUBLISHABLE_KEY를\n'
              '--dart-define으로 넣어 실행해 주세요.',
              key: Key('setupNeeded'),
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6),
            ),
          ),
        ),
      ),
    );
  }
}
