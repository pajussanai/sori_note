import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/speech_input.dart';
import '../memos/dictation.dart';

enum VoiceState {
  /// 시작 전
  ready,

  /// 마이크 준비 중
  starting,

  /// 듣고 글자로 바꾸는 중
  listening,
  paused,

  /// 끝남(결과를 고칠 수 있음)
  finished,

  /// 음성 인식을 쓸 수 없거나 실패함(직접 입력 가능)
  failed,
}

/// 음성 기록 한 번: 시작·일시정지·재개·종료, 들은 글 모으기, 녹음 시간.
///
/// 소리는 기기(브라우저) 음성 인식이 바로 글자로 바꾸며, 소리 파일은 만들지도 보관하지도 않는다.
/// 말을 멈춰 인식이 끝나면(무음) 자동으로 다시 듣는다. 3번 연속 아무 말도 듣지 못하면 일시정지한다.
class VoiceSession extends ChangeNotifier {
  VoiceSession(this._input);

  final SpeechInput _input;

  VoiceState _state = VoiceState.ready;
  String _committed = '';
  String _partial = '';
  String? _message;
  bool _messageIsError = false;
  final _clock = Stopwatch();
  Timer? _ticker;
  int _silentRestarts = 0;
  bool _disposed = false;

  VoiceState get state => _state;
  bool get active =>
      _state == VoiceState.starting ||
      _state == VoiceState.listening ||
      _state == VoiceState.paused;

  /// 지금까지 들은 글(듣는 중인 문장 포함)
  String get transcript => _join(_committed, _partial);

  /// 확정된 글과 듣는 중인 글(화면에서 다르게 보여 준다)
  String get committed => _committed;
  String get partial => _partial;

  /// 녹음한 시간(일시정지한 동안은 빼고)
  Duration get elapsed => _clock.elapsed;

  String? get message => _message;
  bool get messageIsError => _messageIsError;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setMessage(String? text, {bool error = false}) {
    _message = text;
    _messageIsError = error;
  }

  static String _join(String a, String b) {
    final x = a.trim();
    final y = b.trim();
    if (x.isEmpty) return y;
    if (y.isEmpty) return x;
    return '$x $y';
  }

  void _commit() {
    _committed = _join(_committed, _partial);
    _partial = '';
  }

  Future<void> start() async {
    if (active) return;
    _state = VoiceState.starting;
    _setMessage('마이크를 준비하고 있어요…');
    _notify();
    final problem = await _input.initialize();
    if (_disposed) return;
    if (problem != null) {
      _state = VoiceState.failed;
      _setMessage(Dictation.messageFor(problem), error: true);
      _notify();
      return;
    }
    _ticker ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_state == VoiceState.listening) _notify();
    });
    await _listen();
  }

  Future<void> _listen() async {
    _state = VoiceState.listening;
    _clock.start();
    _setMessage(null);
    _notify();
    await _input.start(
      onText: (text, {required isFinal}) {
        if (_state != VoiceState.listening) return;
        if (text.trim().isNotEmpty) _silentRestarts = 0;
        _partial = text;
        if (isFinal) _commit();
        _notify();
      },
      onStopped: _onStopped,
    );
  }

  void _onStopped(SpeechStopReason reason) {
    _commit();
    if (_state != VoiceState.listening) {
      _notify();
      return;
    }
    // 말을 멈춰 인식이 끝난 경우: 이어서 듣는다.
    if (reason == SpeechStopReason.done || reason == SpeechStopReason.noMatch) {
      if (reason == SpeechStopReason.noMatch) _silentRestarts++;
      if (_silentRestarts >= 3) {
        _silentRestarts = 0;
        _clock.stop();
        _state = VoiceState.paused;
        _setMessage('소리가 들리지 않아 일시정지했어요. 이어서 말하려면 재개를 눌러 주세요.');
        _notify();
        return;
      }
      _notify();
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (_state == VoiceState.listening && !_disposed) _listen();
        }),
      );
      return;
    }
    _clock.stop();
    _state = VoiceState.failed;
    _setMessage(Dictation.messageFor(reason), error: true);
    _notify();
  }

  Future<void> pause() async {
    if (_state != VoiceState.listening) return;
    _state = VoiceState.paused;
    _clock.stop();
    _setMessage(null);
    _notify();
    await _input.stop();
    _commit();
    _notify();
  }

  Future<void> resume() async {
    if (_state != VoiceState.paused) return;
    _silentRestarts = 0;
    await _listen();
  }

  /// 녹음을 끝낸다. 들은 글을 고칠 수 있는 상태가 된다.
  Future<void> finish() async {
    if (!active) return;
    final wasListening = _state == VoiceState.listening;
    _state = VoiceState.finished;
    _clock.stop();
    _ticker?.cancel();
    _ticker = null;
    if (wasListening) await _input.stop();
    _commit();
    _setMessage(
      _committed.isEmpty
          ? '들은 내용이 없어요. 아래에 직접 입력하거나 다시 녹음해 주세요.'
          : '글자로 바꿨어요. 내용을 확인하고 고쳐 주세요.',
      error: _committed.isEmpty,
    );
    _notify();
  }

  /// 실패한 뒤 다시 시도한다(이미 들은 글은 유지).
  Future<void> retry() async {
    if (active) return;
    _state = VoiceState.ready;
    await start();
  }

  /// 결과 편집 화면에서 고친 글을 반영한다.
  void setText(String text) {
    _committed = text;
    _partial = '';
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _input.stop().catchError((_) {});
    super.dispose();
  }
}
