import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/memo_audio.dart';
import '../../services/audio_recorder.dart';

enum RecordingState { idle, starting, recording, paused, stopping }

/// 녹음 한 번의 상태: 시작, 일시정지, 재개, 끝내기(저장), 버리기와 녹음 시간.
class AudioRecording extends ChangeNotifier {
  AudioRecording(
    this._recorder, {
    this.maxDuration = AudioLimits.maxDuration,
    this.onLimitReached,
  });

  final AudioRecorderService _recorder;
  final Duration maxDuration;

  /// 최대 시간에 닿아 자동으로 끝났을 때 결과를 넘긴다.
  final void Function(RecordedAudio audio, Duration duration)? onLimitReached;

  RecordingState _state = RecordingState.idle;
  final _clock = Stopwatch();
  Timer? _ticker;
  String? _problem;
  bool _disposed = false;

  RecordingState get state => _state;
  bool get active => _state != RecordingState.idle;
  bool get paused => _state == RecordingState.paused;

  /// 실제로 녹음한 시간(일시정지한 동안은 빼고)
  Duration get elapsed => _clock.elapsed;

  /// 녹음을 시작하지 못했을 때 안내
  String? get problem => _problem;

  void _set(RecordingState state) {
    _state = state;
    if (!_disposed) notifyListeners();
  }

  void clearProblem() {
    if (_problem == null) return;
    _problem = null;
    if (!_disposed) notifyListeners();
  }

  Future<bool> start() async {
    if (active) return false;
    _problem = null;
    _set(RecordingState.starting);
    final problem = await _recorder.start();
    if (_disposed) return false;
    if (problem != null) {
      _problem = messageFor(problem);
      _set(RecordingState.idle);
      return false;
    }
    _clock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _set(RecordingState.recording);
    return true;
  }

  void _tick() {
    if (_disposed) return;
    if (_clock.elapsed >= maxDuration && _state == RecordingState.recording) {
      unawaited(_finishAtLimit());
      return;
    }
    notifyListeners();
  }

  Future<void> _finishAtLimit() async {
    final duration = _clock.elapsed;
    final audio = await finish();
    if (audio != null) onLimitReached?.call(audio, duration);
  }

  Future<void> pause() async {
    if (_state != RecordingState.recording) return;
    await _recorder.pause();
    _clock.stop();
    _set(RecordingState.paused);
  }

  Future<void> resume() async {
    if (_state != RecordingState.paused) return;
    await _recorder.resume();
    _clock.start();
    _set(RecordingState.recording);
  }

  /// 녹음을 끝내고 파일을 돌려준다(저장은 부르는 쪽이 한다).
  Future<RecordedAudio?> finish() async {
    if (_state != RecordingState.recording && _state != RecordingState.paused) {
      return null;
    }
    _ticker?.cancel();
    _clock.stop();
    _set(RecordingState.stopping);
    RecordedAudio? audio;
    try {
      audio = await _recorder.stop();
      if (audio == null) _problem = '녹음된 소리가 없어요. 다시 녹음해 주세요.';
    } catch (e) {
      debugPrint('녹음 끝내기 실패: ${e.runtimeType}');
      _problem = '녹음을 끝내지 못했어요. 다시 녹음해 주세요.';
    }
    _set(RecordingState.idle);
    return audio;
  }

  /// 녹음을 버린다.
  Future<void> discard() async {
    if (!active) return;
    _ticker?.cancel();
    _clock
      ..stop()
      ..reset();
    await _recorder.cancel();
    _set(RecordingState.idle);
  }

  static String messageFor(RecorderProblem problem) => switch (problem) {
    RecorderProblem.permissionDenied =>
      '마이크 권한이 없어요. 브라우저나 기기 설정에서 마이크를 허용한 뒤 다시 눌러 주세요.',
    RecorderProblem.unsupported => '이 브라우저에서는 녹음할 수 없어요. 받아쓰기나 글자 입력을 이용해 주세요.',
    RecorderProblem.failed => '녹음을 시작하지 못했어요. 잠시 후 다시 시도해 주세요.',
  };

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    if (_state != RecordingState.idle) unawaited(_recorder.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }
}

/// 00:00 형식(1시간 이상이면 0:00:00)
String formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}
