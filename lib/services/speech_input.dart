import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 음성 인식 결과(듣는 중 바뀌는 중간 결과 포함)
typedef SpeechTextCallback = void Function(
  String text, {
  required bool isFinal,
});

/// 음성 인식이 끝나거나 실패한 이유
///
/// [serviceBlocked]: 마이크와 별개로 기기의 음성 인식 서비스를 쓸 수 없음
/// (iPhone Safari에서 '받아쓰기'가 꺼져 있을 때 등, Web Speech `service-not-allowed`)
enum SpeechStopReason {
  done,
  noMatch,
  permissionDenied,
  serviceBlocked,
  unsupported,
  error,
}

/// 마이크로 말한 내용을 글자로 바꾼다(STT).
abstract class SpeechInput {
  /// 처음 한 번 준비한다. 사용할 수 없거나 권한이 거부되면 이유를 돌려준다.
  Future<SpeechStopReason?> initialize();

  /// 듣기 시작한다. 결과는 [onText], 끝나면 [onStopped]로 알린다.
  Future<void> start({
    required SpeechTextCallback onText,
    required void Function(SpeechStopReason reason) onStopped,
  });

  Future<void> stop();
}

/// 기기(브라우저·휴대폰)의 음성 인식. 한국어로 듣는다.
class DeviceSpeechInput implements SpeechInput {
  final _speech = SpeechToText();
  bool _ready = false;
  String _localeId = kIsWeb ? 'ko-KR' : 'ko_KR';
  SpeechTextCallback? _onText;
  void Function(SpeechStopReason reason)? _onStopped;
  SpeechStopReason? _pendingReason;

  /// 플랫폼 오류 코드를 앱의 이유로 바꾼다(Android, iOS, 웹 Web Speech API).
  static SpeechStopReason reasonFor(String code) {
    if (code == 'service-not-allowed') return SpeechStopReason.serviceBlocked;
    if (code.contains('permission') || code == 'not-allowed') {
      return SpeechStopReason.permissionDenied;
    }
    if (code == 'error_no_match' ||
        code == 'error_speech_timeout' ||
        code == 'no-speech') {
      return SpeechStopReason.noMatch;
    }
    if (code.contains('not supported') ||
        code.contains('not_supported') ||
        code.contains('language_not_supported') ||
        code.contains('recognizer_disabled')) {
      return SpeechStopReason.unsupported;
    }
    return SpeechStopReason.error;
  }

  void _finish(SpeechStopReason reason) {
    final onStopped = _onStopped;
    _onStopped = null;
    _onText = null;
    onStopped?.call(reason);
  }

  @override
  Future<SpeechStopReason?> initialize() async {
    if (_ready) return null;
    try {
      _ready = await _speech.initialize(
        onError: (SpeechRecognitionError e) {
          // 오류 뒤에 'done' 상태가 따로 오므로 이유만 기억해 둔다.
          _pendingReason = reasonFor(e.errorMsg);
          if (e.permanent || !_speech.isListening) _finish(_pendingReason!);
        },
        onStatus: (status) {
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            _finish(_pendingReason ?? SpeechStopReason.done);
          }
        },
      );
    } catch (e) {
      debugPrint('음성 인식 준비 실패: ${e.runtimeType}');
      return SpeechStopReason.unsupported;
    }
    if (!_ready) {
      // 웹은 브라우저에 Web Speech API가 없을 때만 false다(마이크 권한은 듣기
      // 시작할 때 묻는다). 웹 플러그인의 hasPermission은 지원 여부를 돌려주므로 쓰지 않는다.
      if (kIsWeb) return SpeechStopReason.unsupported;
      // 앱에서는 권한이 거부됐거나 기기가 지원하지 않는다.
      final allowed = await _speech.hasPermission.catchError((_) => false);
      return allowed
          ? SpeechStopReason.unsupported
          : SpeechStopReason.permissionDenied;
    }
    // 기기에 설치된 한국어 인식기를 고른다(없으면 기본 ko-KR).
    try {
      final locales = await _speech.locales();
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith('ko')) {
          _localeId = l.localeId;
          break;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> start({
    required SpeechTextCallback onText,
    required void Function(SpeechStopReason reason) onStopped,
  }) async {
    _onText = onText;
    _onStopped = onStopped;
    _pendingReason = null;
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) =>
            _onText?.call(r.recognizedWords, isFinal: r.finalResult),
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      debugPrint('음성 인식 시작 실패: ${e.runtimeType}');
      _finish(SpeechStopReason.error);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }
}
