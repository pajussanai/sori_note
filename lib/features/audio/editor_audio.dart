import '../../services/app_settings.dart';
import '../../services/audio_player.dart';
import '../../services/audio_recorder.dart';
import '../../services/audio_repository.dart';
import '../../services/pending_audio_store.dart';

/// 편집 화면이 녹음 기능에 쓰는 것들
class EditorAudio {
  const EditorAudio({
    required this.repository,
    required this.pendingStore,
    required this.userId,
    required this.createRecorder,
    required this.createPlayer,
    required this.settings,
  });

  final AudioRepository repository;
  final PendingAudioStore pendingStore;
  final String userId;
  final AudioRecorderService Function() createRecorder;
  final AudioPlayback Function() createPlayer;

  /// 원본 음성 저장 설정(꺼져 있으면 녹음 버튼을 숨긴다)
  final AppSettings settings;
}
