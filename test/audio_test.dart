import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sori_note/core/errors.dart';
import 'package:sori_note/features/audio/audio_recording.dart';
import 'package:sori_note/models/memo_audio.dart';
import 'package:sori_note/services/audio_recorder.dart';
import 'package:sori_note/services/audio_repository.dart';
import 'package:sori_note/services/pending_audio_store.dart';

import 'helpers/fakes.dart';
import 'helpers/pump.dart';

final recordButton = find.byKey(const Key('recordButton'));
final recordSave = find.byKey(const Key('recordSave'));
final newAudioMemo = find.byKey(const Key('newAudioMemo'));

MemoAudio clip(String id, String memoId, {int seconds = 65}) => MemoAudio(
  id: id,
  memoId: memoId,
  storagePath: '${testUser.id}/$memoId/$id.m4a',
  mimeType: 'audio/mp4',
  duration: Duration(seconds: seconds),
  sizeBytes: 5000,
  createdAt: DateTime.utc(2026, 11, 1),
);

PendingAudio pending(String id, String memoId) => PendingAudio(
  id: id,
  userId: testUser.id,
  memoId: memoId,
  mimeType: 'audio/mp4',
  duration: const Duration(seconds: 12),
  bytes: Uint8List.fromList([1, 2, 3]),
  createdAt: DateTime.utc(2026, 11, 1),
);

/// 녹음 중에는 시간 표시가 계속 바뀌므로 pumpAndSettle 대신 몇 번만 그린다.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('원본 음성 저장 설정', () {
    testWidgets('기본은 꺼져 있어 녹음 버튼이 보이지 않는다', (tester) async {
      await pumpApp(tester, memos: [memo('a', '장보기', 1)]);
      expect(newAudioMemo, findsNothing);
      await tester.tap(find.text('장보기'));
      await tester.pumpAndSettle();
      expect(recordButton, findsNothing);
      // 받아쓰기와 AI 다듬기는 그대로 있다.
      expect(find.byKey(const Key('micButton')), findsOneWidget);
      expect(find.byKey(const Key('polishButton')), findsOneWidget);
    });

    testWidgets('설정에서 켜면 녹음 버튼이 생기고 사용량이 보인다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '장보기', 1)],
        setUp: (f) => f.audio.rows.add(clip('c1', 'a')),
      );
      await tester.tap(find.byTooltip('계정'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('openSettings')));
      await tester.pumpAndSettle();
      expect(find.textContaining('녹음 1개'), findsOneWidget);

      await tester.tap(find.byKey(const Key('saveAudioSwitch')));
      await tester.pumpAndSettle();
      expect(fakes.settings.saveOriginalAudio, isTrue);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(newAudioMemo, findsOneWidget);
    });
  });

  group('녹음', () {
    testWidgets('녹음하고 저장하면 메모에 연결되고 목록에 음성 기록으로 보인다', (tester) async {
      final fakes = await pumpApp(tester, saveOriginalAudio: true);
      await tester.tap(newAudioMemo);
      await pumpFrames(tester);

      // 녹음을 붙일 메모가 먼저 만들어진다(빈 메모).
      expect(fakes.memos.calls, contains('create:'));
      expect(fakes.recorder.calls, contains('start'));
      expect(find.byKey(const Key('recordingTime')), findsOneWidget);

      await tester.tap(find.byKey(const Key('recordPause')));
      await pumpFrames(tester);
      expect(fakes.recorder.calls, contains('pause'));
      expect(find.textContaining('일시정지'), findsOneWidget);
      await tester.tap(find.byKey(const Key('recordPause')));
      await pumpFrames(tester);
      expect(fakes.recorder.calls, contains('resume'));

      await tester.tap(recordSave);
      await tester.pumpAndSettle();
      expect(fakes.recorder.calls, contains('stop'));
      expect(fakes.audio.rows, hasLength(1));
      expect(fakes.audio.rows.single.memoId, 'm1');
      expect(find.byKey(const Key('clipPlay')), findsOneWidget);
      // 올리고 나면 기기 보관소에서 지운다.
      expect(await fakes.pendingAudio.list(testUser.id), isEmpty);

      await tester.tap(find.byKey(const Key('backButton')));
      await tester.pumpAndSettle();
      expect(find.text('음성 메모'), findsOneWidget);
      expect(find.byKey(const Key('memoHasAudio')), findsOneWidget);
      expect(find.byKey(const Key('filterAudio')), findsOneWidget);
    });

    testWidgets('올리기에 실패하면 기기에 보관하고 다시 시도할 수 있다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1)],
        saveOriginalAudio: true,
      );
      fakes.audio.uploadError = const AudioException(AudioErrorCode.failed);
      await tester.tap(find.text('회의 메모'));
      await tester.pumpAndSettle();
      await tester.tap(recordButton);
      await pumpFrames(tester);
      await tester.tap(recordSave);
      await tester.pumpAndSettle();

      expect(find.textContaining('저장하지 못했어요'), findsOneWidget);
      expect(await fakes.pendingAudio.list(testUser.id), hasLength(1));
      expect(fakes.audio.rows, isEmpty);

      fakes.audio.uploadError = null;
      await tester.tap(find.byKey(const Key('pendingRetry')));
      await tester.pumpAndSettle();
      expect(fakes.audio.rows, hasLength(1));
      expect(await fakes.pendingAudio.list(testUser.id), isEmpty);
      expect(find.byKey(const Key('clipPlay')), findsOneWidget);
    });

    testWidgets('앱을 다시 열면 남아 있는 녹음을 목록에서 다시 저장할 수 있다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1)],
        setUp: (f) => f.pendingAudio.put(pending('p1', 'a')),
      );
      expect(find.byKey(const Key('pendingBanner')), findsOneWidget);
      expect(find.textContaining('저장하지 못한 녹음 1개'), findsOneWidget);

      await tester.tap(find.byKey(const Key('retryPendingAll')));
      await tester.pumpAndSettle();
      expect(fakes.audio.rows.single.id, 'p1');
      expect(find.byKey(const Key('pendingBanner')), findsNothing);
      expect(find.text('녹음을 모두 저장했어요.'), findsOneWidget);
    });

    testWidgets('마이크 권한이 없으면 안내하고 녹음하지 않는다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1)],
        saveOriginalAudio: true,
      );
      fakes.recorder.startProblem = RecorderProblem.permissionDenied;
      await tester.tap(find.text('회의 메모'));
      await tester.pumpAndSettle();
      await tester.tap(recordButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('마이크 권한이 없어요'), findsOneWidget);
      expect(find.byKey(const Key('recordingTime')), findsNothing);
    });

    testWidgets('녹음을 취소하면 저장하지 않고, 녹음용으로 만든 빈 메모도 남기지 않는다', (tester) async {
      final fakes = await pumpApp(tester, saveOriginalAudio: true);
      await tester.tap(newAudioMemo);
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('recordCancel')));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('confirmDiscardRecording')));
      await tester.pumpAndSettle();
      expect(fakes.recorder.calls, contains('cancel'));
      expect(fakes.audio.calls, isEmpty);

      await tester.tap(find.byKey(const Key('backButton')));
      await tester.pumpAndSettle();
      expect(fakes.memos.rows, isEmpty);
      expect(find.byKey(const Key('emptyMemos')), findsOneWidget);
    });

    testWidgets('녹음 중에 나가면 저장할지 묻고 저장한 뒤 나간다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1)],
        saveOriginalAudio: true,
      );
      await tester.tap(find.text('회의 메모'));
      await tester.pumpAndSettle();
      await tester.tap(recordButton);
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('backButton')));
      await pumpFrames(tester);
      expect(find.text('녹음 중이에요'), findsOneWidget);
      await tester.tap(find.byKey(const Key('saveRecordingAndLeave')));
      await tester.pumpAndSettle();
      expect(fakes.audio.rows, hasLength(1));
      expect(find.byKey(const Key('memoHasAudio')), findsOneWidget);
    });
  });

  group('재생과 삭제', () {
    testWidgets('녹음을 재생하고 위치를 옮길 수 있다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1)],
        setUp: (f) => f.audio.rows.add(clip('c1', 'a')),
      );
      await tester.tap(find.text('회의 메모'));
      await tester.pumpAndSettle();
      expect(find.text('00:00 / 01:05'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clipPlay')));
      await tester.pumpAndSettle();
      expect(fakes.player.calls, ['load:https://audio/c1', 'play']);

      await tester.drag(find.byKey(const Key('clipSeek')), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(fakes.player.calls.last, startsWith('seek:'));
    });

    testWidgets('녹음을 삭제하면 파일이 지워지고 메모 글은 남는다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1)],
        setUp: (f) => f.audio.rows.add(clip('c1', 'a')),
      );
      await tester.tap(find.text('회의 메모'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clipDelete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      expect(fakes.audio.calls, contains('delete:c1'));
      expect(find.byKey(const Key('clipPlay')), findsNothing);
      expect(fakes.memos.rows.single.content, '회의 메모');
    });

    testWidgets('녹음 삭제에 실패하면 알려 주고 녹음은 그대로 둔다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1)],
        setUp: (f) => f.audio.rows.add(clip('c1', 'a')),
      );
      fakes.audio.deleteError = const AudioException(AudioErrorCode.failed);
      await tester.tap(find.text('회의 메모'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clipDelete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      expect(find.textContaining('녹음을 삭제하지 못했어요'), findsOneWidget);
      expect(find.byKey(const Key('clipPlay')), findsOneWidget);
    });

    testWidgets('메모를 삭제하면 녹음 파일을 먼저 지운다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1)],
        setUp: (f) => f.audio.rows.add(clip('c1', 'a')),
      );
      await tester.tap(find.text('회의 메모'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteMemoButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      expect(fakes.audio.calls, contains('deleteAll:a'));
      expect(fakes.audio.files, isEmpty);
      expect(fakes.memos.rows, isEmpty);
    });

    testWidgets('녹음 파일을 지우지 못하면 메모도 지우지 않는다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1)],
        setUp: (f) => f.audio.rows.add(clip('c1', 'a')),
      );
      fakes.audio.deleteError = const AudioException(AudioErrorCode.failed);
      await tester.tap(find.text('회의 메모'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteMemoButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      expect(fakes.memos.rows, hasLength(1));
      expect(find.textContaining('메모를 삭제하지 못했습니다'), findsOneWidget);
    });

    testWidgets("'음성 기록'만 걸러 볼 수 있다", (tester) async {
      await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1), memo('b', '장보기', 2)],
        setUp: (f) => f.audio.rows.add(clip('c1', 'a')),
      );
      expect(find.text('장보기'), findsOneWidget);
      await tester.tap(find.byKey(const Key('filterAudio')));
      await tester.pumpAndSettle();
      expect(find.text('장보기'), findsNothing);
      expect(find.text('회의 메모'), findsOneWidget);
    });

    testWidgets('서버에 녹음 기능이 아직 없어도 메모는 평소처럼 쓴다', (tester) async {
      final fakes = await pumpApp(
        tester,
        memos: [memo('a', '회의 메모', 1)],
        setUp: (f) =>
            f.audio.fetchError = const AudioException(AudioErrorCode.notReady),
      );
      expect(find.text('회의 메모'), findsOneWidget);
      await tester.tap(find.text('회의 메모'));
      await tester.pumpAndSettle();
      expect(find.textContaining('녹음을 불러오지 못했어요'), findsNothing);
      await tester.tap(find.byKey(const Key('deleteMemoButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      expect(fakes.memos.rows, isEmpty);
    });
  });

  group('녹음 도우미', () {
    test('녹음 형식을 서버가 받는 형식으로 맞춘다', () {
      expect(normalizeAudioType('audio/webm;codecs=opus'), 'audio/webm');
      expect(normalizeAudioType('audio/mp4; codecs=mp4a.40.2'), 'audio/mp4');
      expect(normalizeAudioType('audio/x-m4a'), 'audio/mp4');
      expect(normalizeAudioType('audio/wav'), isNull);
      expect(normalizeAudioType(null), isNull);
    });

    test('저장 위치는 본인 폴더/메모 폴더 아래', () {
      expect(pending('p1', 'a').storagePath, '${testUser.id}/a/p1.m4a');
    });

    test('녹음 시간 표시', () {
      expect(formatDuration(const Duration(seconds: 5)), '00:05');
      expect(formatDuration(const Duration(minutes: 29, seconds: 59)), '29:59');
      expect(formatDuration(const Duration(hours: 1, seconds: 1)), '1:00:01');
    });

    test('기기 보관소가 실패해도 녹음을 잃지 않는다', () async {
      final store = FallbackPendingAudioStore(_BrokenStore());
      await store.put(pending('p1', 'a'));
      expect((await store.list(testUser.id)).single.id, 'p1');
      await store.remove('p1');
      expect(await store.list(testUser.id), isEmpty);
    });

    test('녹음 오류 문구', () {
      expect(
        describeError(const AudioException(AudioErrorCode.quotaExceeded)),
        contains('100MB'),
      );
      expect(
        describeError(const AudioException(AudioErrorCode.notReady)),
        contains('이 기기에 보관'),
      );
    });

    test('최대 녹음 시간이 되면 자동으로 끝내고 결과를 넘긴다', () async {
      final recorder = FakeRecorder();
      RecordedAudio? saved;
      final recording = AudioRecording(
        recorder,
        maxDuration: const Duration(milliseconds: 300),
        onLimitReached: (audio, _) => saved = audio,
      );
      expect(await recording.start(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(saved, isNotNull);
      expect(recording.active, isFalse);
      expect(recorder.calls, containsAllInOrder(['start', 'stop']));
      recording.dispose();
    });
  });
}

class _BrokenStore implements PendingAudioStore {
  @override
  Future<void> put(PendingAudio audio) async => throw StateError('broken');

  @override
  Future<List<PendingAudio>> list(String userId) async =>
      throw StateError('broken');

  @override
  Future<void> remove(String id) async => throw StateError('broken');
}
