import 'package:flutter/foundation.dart';

import '../../services/speech_input.dart';

/// 받아쓰기 상태: 마이크로 듣고, 들은 글을 넘겨주고, 상황을 안내한다.
class Dictation extends ChangeNotifier {
  Dictation(this._input);

  final SpeechInput _input;

  bool _listening = false;
  bool _starting = false;
  String? _status;
  bool _statusIsError = false;
  bool _disposed = false;

  bool get listening => _listening;
  bool get starting => _starting;
  bool get active => _listening || _starting;
  String? get status => _status;
  bool get statusIsError => _statusIsError;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setStatus(String? text, {bool error = false}) {
    _status = text;
    _statusIsError = error;
  }

  /// 듣기를 시작하거나, 듣는 중이면 멈춘다.
  Future<void> toggle(SpeechTextCallback onText) =>
      active ? stop() : start(onText);

  Future<void> start(SpeechTextCallback onText) async {
    if (active) return;
    _starting = true;
    _setStatus('마이크를 준비하고 있어요…');
    _notify();

    final problem = await _input.initialize();
    if (problem != null) {
      _starting = false;
      _setStatus(messageFor(problem), error: true);
      _notify();
      return;
    }

    var heardSomething = false;
    _starting = false;
    _listening = true;
    _setStatus('듣고 있어요… 말을 마치면 마이크 버튼을 눌러 주세요.');
    _notify();
    await _input.start(
      onText: (text, {required isFinal}) {
        if (text.trim().isNotEmpty) heardSomething = true;
        onText(text, isFinal: isFinal);
      },
      onStopped: (reason) {
        if (!_listening) return;
        _listening = false;
        if (reason == SpeechStopReason.done && !heardSomething) {
          reason = SpeechStopReason.noMatch;
        }
        _setStatus(
          reason == SpeechStopReason.done ? null : messageFor(reason),
          error: reason != SpeechStopReason.done,
        );
        _notify();
      },
    );
  }

  Future<void> stop() async {
    if (!active) return;
    await _input.stop();
    // 기기가 'done'을 늦게 보내도 화면은 바로 멈춘 상태로 바꾼다.
    if (_listening) {
      _listening = false;
      _setStatus(null);
      _notify();
    }
  }

  void clearStatus() {
    if (_status == null || _listening) return;
    _setStatus(null);
    _notify();
  }

  static String messageFor(SpeechStopReason reason) => switch (reason) {
    SpeechStopReason.permissionDenied =>
      '마이크 권한이 없어요. 브라우저나 기기 설정에서 마이크를 허용한 뒤 다시 눌러 주세요.',
    SpeechStopReason.serviceBlocked =>
      '이 기기에서 음성 인식 서비스를 쓸 수 없어요. iPhone은 설정 > 일반 > 키보드에서 '
          '받아쓰기를 켠 뒤 다시 눌러 주세요. 지금은 글자로 입력해 주세요.',
    SpeechStopReason.noMatch => '잘 듣지 못했어요. 마이크 버튼을 누르고 다시 말해 주세요.',
    SpeechStopReason.unsupported =>
      kIsWeb
          ? '이 브라우저에서는 음성 인식을 쓸 수 없어요. 글자로 입력하거나, '
                'Android는 Chrome, iPhone은 Safari에서 열어 주세요.'
          : '이 기기에서는 음성 인식을 쓸 수 없어요. 글자로 입력해 주세요.',
    SpeechStopReason.error => '음성 인식 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.',
    SpeechStopReason.done => '',
  };

  @override
  void dispose() {
    _disposed = true;
    _input.stop().catchError((_) {});
    super.dispose();
  }
}
