import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sori_note/core/errors.dart';
import 'package:sori_note/features/memos/memo_editor_page.dart';
import 'package:sori_note/main.dart';
import 'package:sori_note/services/polish_service.dart';
import 'package:sori_note/services/speech_input.dart';

import 'helpers/fakes.dart';
import 'helpers/pump.dart';

final memoInput = find.byKey(const Key('memoInput'));
final micButton = find.byKey(const Key('micButton'));
final polishButton = find.byKey(const Key('polishButton'));

String inputText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(of: memoInput, matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// 입력을 멈추고 자동 저장이 끝날 때까지 기다린다.
Future<void> waitForSave(WidgetTester tester) async {
  await tester.pump(MemoEditorPage.saveDelay);
  await tester.pumpAndSettle();
}

void main() {
  group('로그인', () {
    testWidgets('로그인하지 않으면 메모를 볼 수 없다', (tester) async {
      final fakes = await pumpApp(tester, user: null);
      expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
      expect(find.text('소리노트'), findsOneWidget);
      expect(fakes.memos.calls, isEmpty);
    });

    testWidgets('로그인하면 빈 메모 목록과 안내가 보인다', (tester) async {
      final fakes = await pumpApp(tester, user: null);
      await tester.enterText(
        find.byKey(const Key('emailInput')),
        'me@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('passwordInput')),
        'secret123',
      );
      await tester.tap(find.widgetWithText(FilledButton, '로그인'));
      await tester.pumpAndSettle();

      expect(fakes.auth.calls, ['signIn:me@example.com']);
      expect(find.byKey(const Key('emptyMemos')), findsOneWidget);
      expect(find.byKey(const Key('newVoiceMemo')), findsOneWidget);
    });
  });

  group('메모 목록', () {
    testWidgets('최근 메모가 위에 오고, 첫 줄이 제목·나머지가 미리보기', (tester) async {
      await pumpApp(
        tester,
        memos: [memo('a', '장보기\n우유, 계란', 1), memo('b', '회의 메모\n다음 주 발표 준비', 5)],
      );
      final titles = tester
          .widgetList<Card>(find.byType(Card))
          .map((c) => (c.key as ValueKey<String>).value)
          .toList();
      expect(titles, ['memo-b', 'memo-a']);
      expect(find.text('장보기'), findsOneWidget);
      expect(find.text('우유, 계란'), findsOneWidget);
    });

    testWidgets('검색하면 내용이 들어간 메모만 보인다', (tester) async {
      await pumpApp(
        tester,
        memos: [memo('a', '장보기 우유', 1), memo('b', '회의 메모', 2)],
      );
      await tester.enterText(find.byKey(const Key('searchInput')), '우유');
      await tester.pump();
      expect(find.text('장보기 우유'), findsOneWidget);
      expect(find.text('회의 메모'), findsNothing);

      await tester.enterText(find.byKey(const Key('searchInput')), '없는말');
      await tester.pump();
      expect(find.text('검색 결과가 없어요.'), findsOneWidget);
    });

    testWidgets('불러오기 실패 시 다시 시도할 수 있다', (tester) async {
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fakes = FakeServices(user: testUser)
        ..memos.fetchError = Exception('offline');
      await tester.pumpWidget(SoriNoteApp(services: fakes.services));
      await tester.pumpAndSettle();
      expect(find.textContaining('메모를 불러오지 못했습니다'), findsOneWidget);

      fakes.memos.fetchError = null;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('emptyMemos')), findsOneWidget);
    });
  });

  group('메모 쓰기', () {
    testWidgets('글로 쓰면 잠시 뒤 자동 저장되고, 이어서 쓰면 같은 메모를 고친다', (tester) async {
      final fakes = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('newTextMemo')));
      await tester.pumpAndSettle();

      await tester.enterText(memoInput, '첫 메모');
      await tester.pump();
      expect(find.text('저장 중…'), findsOneWidget);
      await waitForSave(tester);
      expect(fakes.memos.calls.last, 'create:첫 메모');
      expect(find.text('저장됨'), findsOneWidget);

      await tester.enterText(memoInput, '첫 메모\n둘째 줄');
      await waitForSave(tester);
      expect(fakes.memos.calls.last, 'update:m1:첫 메모\n둘째 줄');

      await tester.tap(find.byKey(const Key('backButton')));
      await tester.pumpAndSettle();
      expect(find.text('첫 메모'), findsOneWidget, reason: '목록에 바로 보인다');
    });

    testWidgets('비어 있는 새 메모는 저장하지 않는다', (tester) async {
      final fakes = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('newTextMemo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('backButton')));
      await tester.pumpAndSettle();
      expect(fakes.memos.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    testWidgets('나갈 때 아직 저장하지 않은 내용을 저장한다', (tester) async {
      final fakes = await pumpApp(tester, memos: [memo('a', '원래', 1)]);
      await tester.tap(find.text('원래'));
      await tester.pumpAndSettle();
      await tester.enterText(memoInput, '원래 고침');
      await tester.pump();
      await tester.tap(find.byKey(const Key('backButton')));
      await tester.pumpAndSettle();
      expect(fakes.memos.calls, contains('update:a:원래 고침'));
    });

    testWidgets('저장에 실패하면 알려 주고 다시 시도할 수 있다', (tester) async {
      final fakes = await pumpApp(tester);
      fakes.memos.saveError = Exception('offline');
      await tester.tap(find.byKey(const Key('newTextMemo')));
      await tester.pumpAndSettle();
      await tester.enterText(memoInput, '저장 실패할 글');
      await waitForSave(tester);
      expect(find.byKey(const Key('saveRetry')), findsOneWidget);

      fakes.memos.saveError = null;
      await tester.tap(find.byKey(const Key('saveRetry')));
      await tester.pumpAndSettle();
      expect(find.text('저장됨'), findsOneWidget);
      expect(fakes.memos.rows.single.content, '저장 실패할 글');
    });

    testWidgets('메모를 삭제하면 목록에서 사라진다', (tester) async {
      final fakes = await pumpApp(tester, memos: [memo('a', '지울 메모', 1)]);
      await tester.tap(find.text('지울 메모'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteMemoButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();

      expect(fakes.memos.calls, contains('delete:a'));
      expect(find.text('지울 메모'), findsNothing);
      expect(find.byKey(const Key('emptyMemos')), findsOneWidget);
    });
  });

  group('말로 메모(받아쓰기)', () {
    testWidgets("'말로 메모'는 바로 듣기 시작하고, 들은 글을 넣어 저장한다", (tester) async {
      final fakes = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('newVoiceMemo')));
      await tester.pumpAndSettle();
      expect(fakes.speech.isListening, isTrue);
      expect(find.textContaining('듣고 있어요'), findsOneWidget);

      fakes.speech.hear('오늘 회의');
      await tester.pump();
      expect(inputText(tester), '오늘 회의');
      fakes.speech.hear('오늘 회의는 세 시', isFinal: true);
      await tester.pump();
      expect(inputText(tester), '오늘 회의는 세 시');

      await tester.tap(micButton);
      await tester.pump();
      expect(fakes.speech.isListening, isFalse);
      await waitForSave(tester);
      expect(fakes.memos.calls.last, 'create:오늘 회의는 세 시');
    });

    testWidgets('쓰던 글의 커서 자리에 띄어서 끼워 넣는다', (tester) async {
      final fakes = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('newTextMemo')));
      await tester.pumpAndSettle();
      await tester.enterText(memoInput, '할 일:');
      await tester.pump();

      await tester.tap(micButton);
      await tester.pump();
      fakes.speech.hear('은행 가기', isFinal: true);
      fakes.speech.finish();
      await tester.pump();
      expect(inputText(tester), '할 일: 은행 가기');
    });

    testWidgets('마이크 권한이 없으면 해결 방법을 안내한다', (tester) async {
      final fakes = await pumpApp(tester);
      fakes.speech.initProblem = SpeechStopReason.permissionDenied;
      await tester.tap(find.byKey(const Key('newVoiceMemo')));
      await tester.pumpAndSettle();
      expect(fakes.speech.isListening, isFalse);
      expect(find.textContaining('마이크 권한이 없어요'), findsOneWidget);
    });

    testWidgets('음성 인식을 못 쓰면 키보드 입력으로 바꿀 수 있다', (tester) async {
      final fakes = await pumpApp(tester);
      fakes.speech.initProblem = SpeechStopReason.unsupported;
      await tester.tap(find.byKey(const Key('newVoiceMemo')));
      await tester.pumpAndSettle();
      expect(find.textContaining('음성 인식을 쓸 수 없어요'), findsOneWidget);

      await tester.tap(find.byKey(const Key('typeInstead')));
      await tester.pump();
      expect(find.byKey(const Key('dictationStatus')), findsNothing);
      final input = tester.widget<TextField>(
        find.byKey(const Key('memoInput')),
      );
      expect(input.focusNode!.hasFocus, isTrue);
    });

    testWidgets('아무 말도 인식하지 못하면 다시 말해 달라고 한다', (tester) async {
      final fakes = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('newVoiceMemo')));
      await tester.pumpAndSettle();
      fakes.speech.finish();
      await tester.pump();
      expect(find.textContaining('잘 듣지 못했어요'), findsOneWidget);
    });
  });

  group('AI 다듬기', () {
    Future<FakeServices> openMemo(WidgetTester tester, String content) async {
      final fakes = await pumpApp(tester, memos: [memo('a', content, 1)]);
      await tester.tap(find.text(content));
      await tester.pumpAndSettle();
      return fakes;
    }

    testWidgets('결과를 원문과 함께 보여 주고, 적용하면 바꾸고 저장한다', (tester) async {
      final fakes = await openMemo(tester, '오늘 회의 는 세시');
      fakes.polish.result = (_) => '오늘 회의는 세 시입니다.';

      await tester.tap(polishButton);
      await tester.pumpAndSettle();
      expect(fakes.polish.requests, ['오늘 회의 는 세시']);
      expect(find.byKey(const Key('polishResult')), findsOneWidget);
      expect(find.text('오늘 회의는 세 시입니다.'), findsOneWidget);
      expect(find.textContaining('Google Gemini로 전송'), findsOneWidget);

      await tester.tap(find.byKey(const Key('applyPolish')));
      await tester.pumpAndSettle();
      expect(inputText(tester), '오늘 회의는 세 시입니다.');
      expect(fakes.memos.calls, contains('update:a:오늘 회의는 세 시입니다.'));

      // 되돌리기
      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      expect(inputText(tester), '오늘 회의 는 세시');
      expect(fakes.memos.calls.last, 'update:a:오늘 회의 는 세시');
    });

    testWidgets('취소하면 아무것도 바뀌지 않는다', (tester) async {
      final fakes = await openMemo(tester, '원문 그대로');
      await tester.tap(polishButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '취소'));
      await tester.pumpAndSettle();
      expect(inputText(tester), '원문 그대로');
      expect(fakes.memos.calls.where((c) => c.startsWith('update')), isEmpty);
    });

    testWidgets('기다리는 동안 안내를 보여 준다', (tester) async {
      final fakes = await openMemo(tester, '느린 다듬기');
      fakes.polish.gate = Completer<void>();
      await tester.tap(polishButton);
      await tester.pump();
      await tester.pump();
      expect(find.text('AI가 문장을 다듬고 있어요…'), findsOneWidget);
      fakes.polish.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('polishResult')), findsOneWidget);
    });

    testWidgets('실패하면 이유를 보여 주고 다시 시도할 수 있다', (tester) async {
      final fakes = await openMemo(tester, '다듬을 글');
      fakes.polish.error = const PolishException('ai_quota_exceeded');
      await tester.tap(polishButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('AI 무료 사용량을 모두 사용했습니다'), findsOneWidget);

      fakes.polish.error = null;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('polishResult')), findsOneWidget);
    });

    testWidgets('내용이 없으면 다듬기를 요청하지 않는다', (tester) async {
      final fakes = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('newTextMemo')));
      await tester.pumpAndSettle();
      await tester.tap(polishButton);
      await tester.pumpAndSettle();
      expect(fakes.polish.requests, isEmpty);
      expect(find.textContaining('다듬을 내용이 없어요'), findsOneWidget);
    });
  });

  group('오류 문구', () {
    test('다듬기 오류 코드를 사용자 문구로 바꾼다', () {
      expect(
        describeError(const PolishException('daily_limit_reached')),
        contains('오늘 다듬기 횟수'),
      );
      expect(
        describeError(const PolishException('ai_not_configured')),
        contains('AI 서버가 아직 준비되지 않았습니다'),
      );
      expect(
        describeError(const PolishException('something_else')),
        contains('AI 다듬기에 실패했습니다'),
      );
    });
  });
}
