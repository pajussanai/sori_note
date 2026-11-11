// 실제 브라우저에서만 도는 테스트: 녹음(MediaRecorder)과 기기 보관소(IndexedDB).
//
//   flutter test --platform chrome test/web/audio_web_test.dart
//
// 녹음 테스트는 가짜 마이크가 필요하다. Chrome을 다음 옵션으로 띄우는 실행 파일을
// CHROME_EXECUTABLE로 지정한다(tool/chrome_fake_mic.bat 참고).
//   --use-fake-ui-for-media-stream --use-fake-device-for-media-stream
// 가짜 마이크가 없으면 녹음 테스트는 건너뛴다.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sori_note/models/memo_audio.dart';
import 'package:sori_note/services/audio_recorder.dart';
import 'package:sori_note/services/pending_audio_store.dart';

PendingAudio _pending(String id, String user, int size) => PendingAudio(
  id: id,
  userId: user,
  memoId: 'memo-1',
  mimeType: 'audio/webm',
  duration: const Duration(seconds: 3),
  bytes: Uint8List.fromList(List.generate(size, (i) => i % 256)),
  createdAt: DateTime.utc(2026, 11, 11, 0, 0, size % 60),
);

void main() {
  test('IndexedDB 보관소: 넣고, 사용자별로 꺼내고, 지운다', () async {
    final store = createPendingAudioStore();
    await store.put(_pending('w1', 'user-a', 2000));
    await store.put(_pending('w2', 'user-b', 10));

    // 새 보관소(앱을 다시 연 것과 같음)에서도 남아 있어야 한다.
    final reopened = createPendingAudioStore();
    final mine = await reopened.list('user-a');
    expect(mine.map((a) => a.id), ['w1']);
    expect(mine.single.bytes.length, 2000);
    expect(mine.single.bytes[1999], 1999 % 256);
    expect(mine.single.duration, const Duration(seconds: 3));

    await reopened.remove('w1');
    await reopened.remove('w2');
    expect(await createPendingAudioStore().list('user-a'), isEmpty);
    expect(await createPendingAudioStore().list('user-b'), isEmpty);
  });

  test('녹음: 시작·일시정지·재개·끝내기 후 소리 파일을 받는다', () async {
    final recorder = DeviceAudioRecorder();
    final problem = await recorder.start();
    if (problem != null) {
      markTestSkipped('가짜 마이크 없이 실행됨($problem)');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await recorder.pause();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await recorder.resume();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final audio = await recorder.stop();
    await recorder.dispose();

    expect(audio, isNotNull);
    expect(audio!.bytes.length, greaterThan(1000));
    expect(audioExtensions.keys, contains(audio.mimeType));
    // ignore: avoid_print
    print('녹음 형식 ${audio.mimeType}, ${audio.bytes.length}바이트');
  });
}
