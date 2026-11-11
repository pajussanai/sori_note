import 'dart:async';
import 'dart:typed_data';

import 'package:sori_note/app/services.dart';
import 'package:sori_note/models/memo_audio.dart';
import 'package:sori_note/services/app_settings.dart';
import 'package:sori_note/services/audio_player.dart';
import 'package:sori_note/services/audio_recorder.dart';
import 'package:sori_note/services/audio_repository.dart';
import 'package:sori_note/services/pending_audio_store.dart';
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

/// 기기 녹음기 대신 쓴다. 테스트가 결과와 문제를 정한다.
class FakeRecorder implements AudioRecorderService {
  RecorderProblem? startProblem;
  RecordedAudio? result = RecordedAudio(
    bytes: Uint8List.fromList(List.filled(1000, 7)),
    mimeType: 'audio/mp4',
  );
  final calls = <String>[];

  @override
  Future<RecorderProblem?> start() async {
    calls.add('start');
    return startProblem;
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<RecordedAudio?> stop() async {
    calls.add('stop');
    return result;
  }

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// 서버(Storage·memo_audio) 대신 녹음을 메모리에 저장한다.
class FakeAudioRepository implements AudioRepository {
  final rows = <MemoAudio>[];
  final files = <String>{};
  final calls = <String>[];
  Object? uploadError;
  Object? deleteError;
  Object? fetchError;

  @override
  Future<List<MemoAudio>> fetchForMemo(String memoId) async {
    if (fetchError != null) throw fetchError!;
    return rows.where((r) => r.memoId == memoId).toList();
  }

  @override
  Future<Set<String>> memoIdsWithAudio() async {
    if (fetchError != null) throw fetchError!;
    return {for (final r in rows) r.memoId};
  }

  @override
  Future<MemoAudio> upload(PendingAudio audio) async {
    calls.add('upload:${audio.memoId}');
    if (uploadError != null) throw uploadError!;
    files.add(audio.storagePath);
    final row = MemoAudio(
      id: audio.id,
      memoId: audio.memoId,
      storagePath: audio.storagePath,
      mimeType: audio.mimeType,
      duration: audio.duration,
      sizeBytes: audio.bytes.length,
      createdAt: audio.createdAt,
    );
    rows.removeWhere((r) => r.id == audio.id);
    rows.add(row);
    return row;
  }

  @override
  Future<String> playbackUrl(MemoAudio audio) async =>
      'https://audio/${audio.id}';

  @override
  Future<void> delete(MemoAudio audio) async {
    calls.add('delete:${audio.id}');
    if (deleteError != null) throw deleteError!;
    files.remove(audio.storagePath);
    rows.removeWhere((r) => r.id == audio.id);
  }

  @override
  Future<void> deleteAllForMemo(String memoId) async {
    calls.add('deleteAll:$memoId');
    if (deleteError != null) throw deleteError!;
    for (final r in rows.where((r) => r.memoId == memoId)) {
      files.remove(r.storagePath);
    }
    rows.removeWhere((r) => r.memoId == memoId);
  }

  @override
  Future<AudioUsage> usage() async => AudioUsage(
    usedBytes: rows.fold(0, (sum, r) => sum + r.sizeBytes),
    limitBytes: AudioLimits.quotaBytes,
    fileCount: rows.length,
  );
}

/// 재생기 대신 쓴다. 재생·위치 이동을 기록한다.
class FakePlayback implements AudioPlayback {
  final calls = <String>[];
  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();

  @override
  Future<Duration?> load(String url) async {
    calls.add('load:$url');
    return null;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    _position.add(position);
  }

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// 테스트용 서비스 묶음
class FakeServices {
  FakeServices({
    AppUser? user,
    List<Memo> memos = const [],
    bool saveOriginalAudio = false,
  }) : auth = FakeAuthService(user: user),
       memos = FakeMemoRepository(memos),
       settings = AppSettings(
         MemorySettingsStore()
           ..values['save_original_audio'] = saveOriginalAudio,
       );

  final FakeAuthService auth;
  final FakeMemoRepository memos;
  final polish = FakePolishService();
  final speech = FakeSpeechInput();
  final audio = FakeAudioRepository();
  final pendingAudio = MemoryPendingAudioStore();
  final recorder = FakeRecorder();
  final player = FakePlayback();
  final AppSettings settings;

  AppServices get services => AppServices(
    auth: auth,
    memos: memos,
    polish: polish,
    createSpeechInput: () => speech,
    audio: audio,
    pendingAudio: pendingAudio,
    createRecorder: () => recorder,
    createPlayer: () => player,
    settings: settings,
  );
}
