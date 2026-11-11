// 화면 미리 보기(점검용): 서버 없이 테스트용 가짜 서비스로 앱을 띄운다. 배포에는 포함되지 않는다.
//   flutter build web -t tool/web_probe/ui_preview.dart -o build/preview --no-web-resources-cdn
//   주소 뒤 ?screen=list | editor | recording | settings
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sori_note/app/theme.dart';
import 'package:sori_note/features/audio/editor_audio.dart';
import 'package:sori_note/features/memos/memo_editor_page.dart';
import 'package:sori_note/features/settings/settings_page.dart';
import 'package:sori_note/main.dart';
import 'package:sori_note/models/memo.dart';
import 'package:sori_note/models/memo_audio.dart';

import '../../test/helpers/fakes.dart';

Memo _memo(String id, String content, int minute) => Memo(
  id: id,
  content: content,
  createdAt: DateTime(2026, 11, 11, 9, minute),
  updatedAt: DateTime(2026, 11, 11, 9, minute),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fakes = FakeServices(
    user: testUser,
    saveOriginalAudio: true,
    memos: [
      _memo('a', '주간 회의\n다음 주 출시 일정과 담당자 정리', 1),
      _memo('b', '', 2),
      _memo('c', '장보기\n우유, 달걀, 사과', 3),
    ],
  );
  await fakes.settings.load();
  fakes.audio.rows
    ..add(_clip('c1', 'a', 65))
    ..add(_clip('c2', 'b', 312));
  await fakes.pendingAudio.put(
    PendingAudio(
      id: 'p1',
      userId: testUser.id,
      memoId: 'a',
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 42),
      bytes: Uint8List(10),
      createdAt: DateTime.now().toUtc(),
    ),
  );
  fakes.audio.uploadError = Exception('offline');

  final services = fakes.services;
  final screen = Uri.base.queryParameters['screen'] ?? 'list';
  final editorAudio = EditorAudio(
    repository: services.audio,
    pendingStore: services.pendingAudio,
    userId: testUser.id,
    createRecorder: services.createRecorder,
    createPlayer: services.createPlayer,
    settings: services.settings,
  );
  Widget editor({bool record = false}) => MemoEditorPage(
    memo: fakes.memos.rows.first,
    repository: services.memos,
    polishService: services.polish,
    speechInput: services.createSpeechInput(),
    onSaved: (_) {},
    onDelete: (_) async {},
    audio: editorAudio,
    startAudioRecording: record,
  );
  runApp(switch (screen) {
    'editor' => _Wrap(child: editor()),
    'recording' => _Wrap(child: editor(record: true)),
    'settings' => _Wrap(
      child: SettingsPage(settings: services.settings, audio: services.audio),
    ),
    _ => SoriNoteApp(services: services),
  });
}

MemoAudio _clip(String id, String memoId, int seconds) => MemoAudio(
  id: id,
  memoId: memoId,
  storagePath: '${testUser.id}/$memoId/$id.m4a',
  mimeType: 'audio/mp4',
  duration: Duration(seconds: seconds),
  sizeBytes: seconds * 13000,
  createdAt: DateTime(2026, 11, 11),
);

class _Wrap extends StatelessWidget {
  const _Wrap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: child,
  );
}
