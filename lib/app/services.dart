import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/local_store.dart';
import '../services/memo_repository.dart';
import '../services/notifier.dart';
import '../services/organizer.dart';
import '../services/polish_service.dart';
import '../services/speech_input.dart';

/// 앱이 쓰는 외부 기능 묶음. 테스트에서는 가짜로 바꿔 끼운다.
class AppServices {
  const AppServices({
    required this.auth,
    required this.memos,
    required this.polish,
    required this.createSpeechInput,
    required this.account,
    required this.local,
    required this.notifier,
    this.organizer = const RuleBasedOrganizer(),
    this.clock,
  });

  final AuthService auth;
  final MemoRepository memos;
  final PolishService polish;

  /// 화면마다 새 음성 인식을 만든다.
  final SpeechInput Function() createSpeechInput;

  /// 계정 삭제, AI 사용량
  final AccountService account;

  /// 분류·일정·요약을 저장하는 이 기기의 저장소
  final KeyValueStore local;

  /// 일정 알림
  final Notifier notifier;

  /// 분류·태그·요약·일정 추출
  final MemoOrganizer organizer;

  /// 지금 시각(테스트에서 고정한다). null이면 기기 시계.
  final DateTime Function()? clock;
}
