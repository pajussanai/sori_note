import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// 녹음 파일 재생. 화면은 이 인터페이스만 쓴다(테스트에서 가짜로 바꾼다).
abstract class AudioPlayback {
  /// 주소의 소리를 불러온다. 길이를 알면 돌려준다.
  Future<Duration?> load(String url);

  /// 재생을 시작한다(끝날 때까지 기다리지 않는다).
  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Stream<Duration> get positionStream;

  Stream<bool> get playingStream;

  /// 끝까지 재생했을 때
  Stream<void> get completedStream;

  Future<void> dispose();
}

/// just_audio로 재생한다(웹은 브라우저 audio, Android·iOS는 기기 재생기).
class JustAudioPlayback implements AudioPlayback {
  final _player = AudioPlayer();

  @override
  Future<Duration?> load(String url) => _player.setUrl(url);

  @override
  Future<void> play() async {
    // just_audio의 play()는 재생이 멈출 때 끝나므로 기다리지 않는다.
    unawaited(_player.play().catchError((_) {}));
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<void> get completedStream => _player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) {});

  @override
  Future<void> dispose() => _player.dispose();
}
