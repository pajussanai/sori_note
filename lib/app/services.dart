import '../services/app_settings.dart';
import '../services/audio_player.dart';
import '../services/audio_recorder.dart';
import '../services/audio_repository.dart';
import '../services/auth_service.dart';
import '../services/memo_repository.dart';
import '../services/pending_audio_store.dart';
import '../services/polish_service.dart';
import '../services/speech_input.dart';

/// 앱이 쓰는 외부 기능 묶음. 테스트에서는 가짜로 바꿔 끼운다.
class AppServices {
  const AppServices({
    required this.auth,
    required this.memos,
    required this.polish,
    required this.createSpeechInput,
    required this.audio,
    required this.pendingAudio,
    required this.createRecorder,
    required this.createPlayer,
    required this.settings,
  });

  final AuthService auth;
  final MemoRepository memos;
  final PolishService polish;

  /// 편집 화면마다 새 음성 인식을 만든다.
  final SpeechInput Function() createSpeechInput;

  /// 원본 음성(녹음 파일) 저장소
  final AudioRepository audio;

  /// 올리지 못한 녹음을 기기에 보관하는 곳
  final PendingAudioStore pendingAudio;

  /// 녹음할 때마다 새 녹음기를 만든다.
  final AudioRecorderService Function() createRecorder;

  /// 녹음 하나를 재생할 때마다 새 재생기를 만든다.
  final AudioPlayback Function() createPlayer;

  final AppSettings settings;
}
