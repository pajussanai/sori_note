import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/ids.dart';
import '../models/memo_audio.dart';
import 'platform/recording_file_stub.dart'
    if (dart.library.js_interop) 'platform/recording_file_web.dart'
    if (dart.library.io) 'platform/recording_file_io.dart';

/// 녹음을 시작하지 못한 이유
enum RecorderProblem { permissionDenied, unsupported, failed }

/// 녹음을 마친 결과(원본 오디오 파일)
class RecordedAudio {
  const RecordedAudio({required this.bytes, required this.mimeType});

  final Uint8List bytes;

  /// 서버가 받는 형식(audio/mp4, audio/webm 등)
  final String mimeType;
}

/// 마이크 소리를 그대로 파일로 녹음한다.
///
/// 음성 인식(받아쓰기, [SpeechInput])과는 다른 기능이다. 받아쓰기는 글자만 만들고
/// 소리를 남기지 않으며, 녹음은 글자로 바꾸지 않고 소리를 파일로 남긴다.
abstract class AudioRecorderService {
  Future<RecorderProblem?> start();

  Future<void> pause();

  Future<void> resume();

  /// 녹음을 끝내고 파일을 돌려준다. 녹음된 것이 없으면 null.
  Future<RecordedAudio?> stop();

  /// 녹음을 버린다.
  Future<void> cancel();

  Future<void> dispose();
}

/// 기기(브라우저 MediaRecorder, Android·iOS 녹음기)로 녹음한다.
///
/// 형식은 AAC(mp4)를 먼저 고른다. iPhone Safari는 mp4만 녹음하고, 다른 기기에서
/// 녹음한 파일도 iPhone에서 재생되게 하려는 것이다. 지원하지 않으면 Opus(webm).
class DeviceAudioRecorder implements AudioRecorderService {
  final _recorder = AudioRecorder();
  String _fallbackType = 'audio/mp4';

  /// 말소리용 비트레이트(요청 값). 브라우저에 따라 따르지 않을 수 있다:
  /// Chrome AAC는 실측 약 103kbps로 녹음했다. 그래서 최대 녹음 시간으로 파일 크기를 막는다
  /// ([AudioLimits.maxDuration]).
  static const _bitRate = 48000;

  @override
  Future<RecorderProblem?> start() async {
    try {
      if (!await _recorder.hasPermission()) {
        return RecorderProblem.permissionDenied;
      }
      final AudioEncoder encoder;
      if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
        encoder = AudioEncoder.aacLc;
        _fallbackType = 'audio/mp4';
      } else if (kIsWeb &&
          await _recorder.isEncoderSupported(AudioEncoder.opus)) {
        encoder = AudioEncoder.opus;
        _fallbackType = 'audio/webm';
      } else {
        return RecorderProblem.unsupported;
      }
      final path = kIsWeb
          ? ''
          : '${(await getTemporaryDirectory()).path}/rec_${newUuid()}.m4a';
      await _recorder.start(
        RecordConfig(encoder: encoder, bitRate: _bitRate, numChannels: 1),
        path: path,
      );
      return null;
    } catch (e) {
      debugPrint('녹음 시작 실패: ${e.runtimeType}');
      // 브라우저에 녹음 기능(getUserMedia, MediaRecorder)이 없으면 여기로 온다.
      return kIsWeb ? RecorderProblem.unsupported : RecorderProblem.failed;
    }
  }

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<RecordedAudio?> stop() async {
    final location = await _recorder.stop();
    if (location == null || location.isEmpty) return null;
    final file = await readRecording(location);
    if (file.bytes.isEmpty) return null;
    return RecordedAudio(
      bytes: file.bytes,
      mimeType: normalizeAudioType(file.type) ?? _fallbackType,
    );
  }

  @override
  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
