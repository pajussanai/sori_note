import '../services/auth_service.dart';
import '../services/memo_repository.dart';
import '../services/polish_service.dart';
import '../services/speech_input.dart';

/// 앱이 쓰는 외부 기능 묶음. 테스트에서는 가짜로 바꿔 끼운다.
class AppServices {
  const AppServices({
    required this.auth,
    required this.memos,
    required this.polish,
    required this.createSpeechInput,
  });

  final AuthService auth;
  final MemoRepository memos;
  final PolishService polish;

  /// 편집 화면마다 새 음성 인식을 만든다.
  final SpeechInput Function() createSpeechInput;
}
