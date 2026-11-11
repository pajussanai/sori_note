// 브라우저에서 실제 녹음(MediaRecorder)과 기기 보관소(IndexedDB)를 확인하는 점검 페이지.
// 앱 화면 없이 서비스 코드만 실행하고 결과를 페이지 글자로 남긴다(배포에는 포함되지 않는다).
//
//   flutter build web -t tool/web_probe/audio_probe.dart -o build/probe --base-href /sori_note/
//   Chrome --use-fake-ui-for-media-stream --use-fake-device-for-media-stream 로 열기
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:sori_note/models/memo_audio.dart';
import 'package:sori_note/services/audio_recorder.dart';
import 'package:sori_note/services/pending_audio_store.dart';
import 'package:web/web.dart' as web;

void report(String line) {
  final p = web.document.createElement('p')..textContent = line;
  web.document.body!.append(p);
  web.document.title = '${web.document.title} | $line';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  web.document.title = 'PROBE';
  try {
    final store = createPendingAudioStore();
    await store.put(
      PendingAudio(
        id: 'probe-1',
        userId: 'probe-user',
        memoId: 'memo',
        mimeType: 'audio/webm',
        duration: const Duration(seconds: 1),
        bytes: Uint8List.fromList(List.generate(3000, (i) => i % 256)),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    final again = await createPendingAudioStore().list('probe-user');
    final ok =
        again.length == 1 &&
        again.single.bytes.length == 3000 &&
        again.single.bytes[2999] == 2999 % 256;
    await store.remove('probe-1');
    final gone = (await createPendingAudioStore().list('probe-user')).isEmpty;
    report(
      'INDEXEDDB ${ok && gone ? 'PASS' : 'FAIL'} (stored=${again.length}, removed=$gone)',
    );
  } catch (e) {
    report('INDEXEDDB FAIL $e');
  }

  try {
    final recorder = DeviceAudioRecorder();
    final problem = await recorder.start();
    if (problem != null) {
      report('RECORD FAIL start=$problem');
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await recorder.pause();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await recorder.resume();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final audio = await recorder.stop();
      await recorder.dispose();
      final ok =
          audio != null &&
          audio.bytes.length > 1000 &&
          audioExtensions.containsKey(audio.mimeType);
      report(
        'RECORD ${ok ? 'PASS' : 'FAIL'} type=${audio?.mimeType} bytes=${audio?.bytes.length}',
      );
    }
  } catch (e) {
    report('RECORD FAIL $e');
  }
  report('DONE');
}
