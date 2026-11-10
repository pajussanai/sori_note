import 'dart:async';

import 'package:sori_note/app/services.dart';
import 'package:sori_note/models/memo.dart';
import 'package:sori_note/services/auth_service.dart';
import 'package:sori_note/services/memo_repository.dart';
import 'package:sori_note/services/polish_service.dart';
import 'package:sori_note/services/speech_input.dart';

const testUser = AppUser(id: 'user-1', email: 'me@example.com');

/// 서버 대신 쓰는 인증 서비스.
class FakeAuthService implements AuthService {
  // 비공개 필드는 named 매개변수로 직접 받을 수 없어 초기화 목록을 쓴다.
  // ignore: prefer_initializing_formals
  FakeAuthService({AppUser? user}) : _user = user;

  AppUser? _user;
  final _changes = StreamController<AppUser?>.broadcast();
  final calls = <String>[];

  Object? signInError;
  Object? signUpError;
  SignUpOutcome signUpOutcome = SignUpOutcome.needsEmailConfirmation;

  void _setUser(AppUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> get userChanges => _changes.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    if (signInError != null) throw signInError!;
    _setUser(AppUser(id: 'user-1', email: email));
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    calls.add('signUp:$email');
    if (signUpError != null) throw signUpError!;
    if (signUpOutcome == SignUpOutcome.signedIn) {
      _setUser(AppUser(id: 'user-1', email: email));
    }
    return signUpOutcome;
  }

  @override
  Future<void> resendConfirmation(String email) async {
    calls.add('resend:$email');
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _setUser(null);
  }
}

/// 기기 마이크 대신 쓰는 음성 인식. 테스트가 인식 결과와 종료를 직접 보낸다.
class FakeSpeechInput implements SpeechInput {
  /// initialize가 돌려줄 문제(null이면 사용 가능)
  SpeechStopReason? initProblem;
  int initializeCalls = 0;
  int stopCalls = 0;
  SpeechTextCallback? _onText;
  void Function(SpeechStopReason reason)? _onStopped;

  bool get isListening => _onStopped != null;

  @override
  Future<SpeechStopReason?> initialize() async {
    initializeCalls++;
    return initProblem;
  }

  @override
  Future<void> start({
    required SpeechTextCallback onText,
    required void Function(SpeechStopReason reason) onStopped,
  }) async {
    _onText = onText;
    _onStopped = onStopped;
  }

  /// 인식 중간·최종 결과를 보낸다.
  void hear(String text, {bool isFinal = false}) =>
      _onText?.call(text, isFinal: isFinal);

  /// 기기가 듣기를 끝낸 것처럼 알린다.
  void finish([SpeechStopReason reason = SpeechStopReason.done]) {
    final onStopped = _onStopped;
    _onStopped = null;
    _onText = null;
    onStopped?.call(reason);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    finish();
  }
}

/// 서버 대신 메모를 메모리에 저장한다.
class FakeMemoRepository implements MemoRepository {
  FakeMemoRepository([List<Memo> initial = const []]) : rows = [...initial];

  final List<Memo> rows;
  final calls = <String>[];
  Object? fetchError;
  Object? saveError;
  Object? deleteError;
  int _next = 1;
  DateTime _clock = DateTime.utc(2026, 11, 10, 1);

  DateTime _tick() => _clock = _clock.add(const Duration(minutes: 1));

  @override
  Future<List<Memo>> fetchMemos() async {
    calls.add('fetch');
    if (fetchError != null) throw fetchError!;
    final sorted = [...rows]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  @override
  Future<Memo> createMemo(String content) async {
    calls.add('create:$content');
    if (saveError != null) throw saveError!;
    final now = _tick();
    final memo = Memo(
      id: 'm${_next++}',
      content: content,
      createdAt: now,
      updatedAt: now,
    );
    rows.add(memo);
    return memo;
  }

  @override
  Future<Memo> updateMemo(String id, String content) async {
    calls.add('update:$id:$content');
    if (saveError != null) throw saveError!;
    final index = rows.indexWhere((m) => m.id == id);
    final updated = rows[index].copyWith(content: content, updatedAt: _tick());
    rows[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteMemo(String id) async {
    calls.add('delete:$id');
    if (deleteError != null) throw deleteError!;
    rows.removeWhere((m) => m.id == id);
  }
}

/// 서버 대신 쓰는 AI 다듬기. [result]를 돌려주거나 [error]를 던진다.
class FakePolishService implements PolishService {
  String Function(String text) result = (text) => '다듬은: $text';
  Object? error;
  final requests = <String>[];

  /// 값이 있으면 완료될 때까지 응답을 미룬다(로딩 화면 확인용).
  Completer<void>? gate;

  @override
  Future<String> polish(String text) async {
    requests.add(text);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return result(text);
  }
}

/// 테스트용 서비스 묶음
class FakeServices {
  FakeServices({AppUser? user, List<Memo> memos = const []})
    : auth = FakeAuthService(user: user),
      memos = FakeMemoRepository(memos);

  final FakeAuthService auth;
  final FakeMemoRepository memos;
  final polish = FakePolishService();
  final speech = FakeSpeechInput();

  AppServices get services => AppServices(
    auth: auth,
    memos: memos,
    polish: polish,
    createSpeechInput: () => speech,
  );
}
