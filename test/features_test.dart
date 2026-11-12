import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sori_note/app/note_store.dart';
import 'package:sori_note/app/reminder_scheduler.dart';
import 'package:sori_note/core/seoul_time.dart';
import 'package:sori_note/models/memo.dart';
import 'package:sori_note/models/memo_label.dart';
import 'package:sori_note/models/plan_item.dart';
import 'package:sori_note/services/account_service.dart';
import 'package:sori_note/services/local_store.dart';
import 'package:sori_note/services/notifier.dart';
import 'package:sori_note/services/organizer.dart';
import 'package:sori_note/services/speech_input.dart';

import 'helpers/fakes.dart';
import 'helpers/pump.dart';

/// 오늘(11월 12일, 한국 시간) 쓴 메모
Memo today(String id, String content, int minute) => Memo(
  id: id,
  content: content,
  createdAt: DateTime.utc(2026, 11, 12, 0, minute),
  updatedAt: DateTime.utc(2026, 11, 12, 0, minute),
);

NoteStore newStore(FakeMemoRepository repo, {KeyValueStore? local}) =>
    NoteStore(
      repository: repo,
      local: local ?? MemoryKeyValueStore(),
      organizer: const RuleBasedOrganizer(),
      userId: 'user-1',
      clock: () => testNow,
    );

PlanItem plan(
  String id, {
  DateTime? due,
  ReminderOffset? reminder,
  bool allDay = false,
}) => PlanItem(
  id: id,
  title: '일정 $id',
  createdAt: testNow,
  dueAt: due,
  allDay: allDay,
  reminder: reminder,
);

void main() {
  group('기록 저장소', () {
    test('저장할 때 분류하고, 내용이 바뀔 때만 다시 분류한다', () async {
      final repo = FakeMemoRepository();
      final store = newStore(repo);
      await store.load();
      final memo = await store.saveMemo(null, '주간 회의\n안건 정리');
      expect(store.labelOf(memo.id)!.category, MemoCategory.meeting);

      // 사용자가 고친 분류는 내용이 바뀌어도 그대로
      await store.setCategory(memo.id, MemoCategory.work);
      await store.saveMemo(memo.id, '장보기 우유 사기 마트');
      expect(store.labelOf(memo.id)!.category, MemoCategory.work);
      expect(store.labelOf(memo.id)!.categoryByUser, isTrue);
      // 태그는 사용자가 고치지 않았으므로 새 내용으로 바뀐다
      expect(store.labelOf(memo.id)!.tags, contains('우유'));

      await store.setTags(memo.id, ['#가족', '가족', ' 마트 ']);
      expect(store.labelOf(memo.id)!.tags, ['가족', '마트']);
      await store.saveMemo(memo.id, '전혀 다른 내용으로 바꿈');
      expect(store.labelOf(memo.id)!.tags, ['가족', '마트']);
    });

    test('분류·일정·요약은 기기 저장소에 남아 다시 열어도 보인다', () async {
      final repo = FakeMemoRepository([today('a', '회의록 정리', 1)]);
      final local = MemoryKeyValueStore();
      final store = newStore(repo, local: local);
      await store.load();
      await store.savePlan(plan('p1', due: seoul(11, 13, 15)));
      await store.createSummary(DateTime.utc(2026, 11, 12));

      final again = newStore(repo, local: local);
      await again.load();
      expect(again.labelOf('a')!.category, MemoCategory.meeting);
      expect(again.plans.single.id, 'p1');
      expect(again.summaryOf(DateTime.utc(2026, 11, 12)), isNotNull);
    });

    test('메모를 지우면 분류를 지우고, 등록한 일정은 남기되 연결만 끊는다', () async {
      final repo = FakeMemoRepository([today('a', '회의', 1)]);
      final store = newStore(repo);
      await store.load();
      await store.savePlan(
        PlanItem(id: 'p', title: '회의', createdAt: testNow, memoId: 'a'),
      );
      await store.deleteMemo('a');
      expect(store.labelOf('a'), isNull);
      expect(store.plans.single.memoId, isNull);
    });

    test('제목·본문·태그·분류로 찾는다', () async {
      final repo = FakeMemoRepository([
        today('a', '출시 회의\n일정 논의', 1),
        today('b', '장보기 우유 사기', 2),
      ]);
      final store = newStore(repo);
      await store.load();
      expect((await store.search('우유')).map((h) => h.memo.id), ['b']);
      await store.setTags('a', ['로드맵']);
      expect((await store.search('로드맵')).map((h) => h.memo.id), ['a']);
      expect((await store.search('', tag: '로드맵')).map((h) => h.memo.id), ['a']);
      expect(
        (await store.search(
          '',
          category: MemoCategory.todo,
        )).map((h) => h.memo.id),
        ['b'],
      );
      final hit = (await store.search('논의')).single;
      expect(hit.preview, contains('논의'));
    });

    test('메모가 없는 날에는 요약을 만들지 않는다', () async {
      final repo = FakeMemoRepository([today('a', '출시일은 12월로 결정했다.', 1)]);
      final store = newStore(repo);
      await store.load();
      expect(await store.createSummary(DateTime.utc(2026, 11, 11)), isNull);
      final summary = await store.createSummary(DateTime.utc(2026, 11, 12));
      expect(summary!.memoCount, 1);
      expect(store.summaries.single.day, '2026-11-12');
      await store.deleteSummary('2026-11-12');
      expect(store.summaries, isEmpty);
    });

    test('지난 시각·제목 없는 일정은 등록하지 않는다', () async {
      final store = newStore(FakeMemoRepository());
      expect(
        store.validatePlan(plan('a', due: seoul(11, 12, 9))),
        contains('지난'),
      );
      expect(
        store.validatePlan(plan('a', due: seoul(11, 11), allDay: true)),
        contains('지난'),
      );
      expect(
        store.validatePlan(plan('a', due: seoul(11, 12), allDay: true)),
        isNull,
      );
      expect(store.validatePlan(plan('a', due: seoul(11, 12, 11))), isNull);
      expect(
        store.validatePlan(PlanItem(id: 'x', title: ' ', createdAt: testNow)),
        contains('제목'),
      );
    });

    test('알림 시각이 되면 한 번만 알린다', () async {
      var now = testNow;
      final store = NoteStore(
        repository: FakeMemoRepository(),
        local: MemoryKeyValueStore(),
        organizer: const RuleBasedOrganizer(),
        userId: 'user-1',
        clock: () => now,
      );
      final notifier = SilentNotifier(NotifyPermission.granted);
      final scheduler = ReminderScheduler(store, notifier);
      await store.savePlan(
        plan('p', due: seoul(11, 12, 11), reminder: ReminderOffset.min10),
      );
      await scheduler.check();
      expect(notifier.shown, isEmpty);

      now = seoul(11, 12, 10, 50);
      await scheduler.check();
      await scheduler.check();
      expect(notifier.shown, ['일정 p|오늘 오전 11:00 · 소리노트 일정']);
      expect(store.sentReminders.single.id, 'p');
      expect(store.pendingReminders, isEmpty);
      scheduler.dispose();
    });

    test('내보내기에 메모·분류·일정·요약이 들어간다', () async {
      final repo = FakeMemoRepository([today('a', '회의록', 1)]);
      final store = newStore(repo);
      await store.load();
      await store.savePlan(plan('p'));
      await store.createSummary(DateTime.utc(2026, 11, 12));
      final data =
          jsonDecode(await store.exportJson(email: 'me@example.com')) as Map;
      expect((data['memos'] as List).single['label']['category'], '회의');
      expect((data['plans'] as List).single['id'], 'p');
      expect((data['dailySummaries'] as List).single['day'], '2026-11-12');
    });
  });

  group('음성 기록 화면', () {
    testWidgets('녹음 → 일시정지·재개 → 종료 → 고치기 → AI 다듬기 → 저장', (tester) async {
      final fakes = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('newVoiceMemo')));
      await tester.pumpAndSettle();
      expect(fakes.speech.isListening, isTrue);
      expect(find.textContaining('녹음 중'), findsOneWidget);

      fakes.speech.hear('내일 오후 3시 치과 예약');
      await tester.pump();
      expect(find.textContaining('치과 예약'), findsOneWidget);

      await tester.tap(find.byKey(const Key('voicePause')));
      await tester.pumpAndSettle();
      expect(fakes.speech.isListening, isFalse);
      await tester.tap(find.byKey(const Key('voiceResume')));
      await tester.pumpAndSettle();
      expect(fakes.speech.isListening, isTrue);
      fakes.speech.hear('그리고 우유 사기');
      await tester.pump();

      await tester.tap(find.byKey(const Key('voiceStop')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const Key('voiceText')),
      );
      expect(field.controller!.text, '내일 오후 3시 치과 예약 그리고 우유 사기');

      await tester.enterText(
        find.byKey(const Key('voiceText')),
        '내일 오후 3시 치과 예약\n우유 사기',
      );
      await tester.tap(find.byKey(const Key('voicePolish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('applyPolish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voiceSave')));
      await tester.pumpAndSettle();

      expect(fakes.memos.rows.single.content, '다듬은: 내일 오후 3시 치과 예약\n우유 사기');
      expect(find.text('음성 기록을 메모로 저장했어요.'), findsOneWidget);
      expect(find.text('다듬은: 내일 오후 3시 치과 예약'), findsOneWidget);
    });

    testWidgets('말을 멈춰 인식이 끝나도 이어서 듣는다', (tester) async {
      final fakes = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('newVoiceMemo')));
      await tester.pumpAndSettle();
      fakes.speech.hear('첫 문장');
      fakes.speech.finish();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(fakes.speech.isListening, isTrue);
      fakes.speech.hear('둘째 문장');
      await tester.pump();
      expect(find.textContaining('첫 문장'), findsOneWidget);
      await tester.tap(find.byKey(const Key('voiceStop')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const Key('voiceText')),
      );
      expect(field.controller!.text, '첫 문장 둘째 문장');
    });

    testWidgets('음성 인식을 쓸 수 없으면 바로 직접 입력해 저장한다', (tester) async {
      final fakes = await pumpApp(
        tester,
        setUp: (f) => f.speech.initProblem = SpeechStopReason.unsupported,
      );
      await tester.tap(find.byKey(const Key('newVoiceMemo')));
      await tester.pumpAndSettle();
      expect(find.textContaining('음성 인식을 쓸 수 없어요'), findsOneWidget);
      expect(find.byKey(const Key('voiceRetry')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('voiceText')), '직접 쓴 메모');
      await tester.tap(find.byKey(const Key('voiceSave')));
      await tester.pumpAndSettle();
      expect(fakes.memos.rows.single.content, '직접 쓴 메모');
    });

    testWidgets('저장하지 않고 나가면 확인한다', (tester) async {
      final fakes = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('newVoiceMemo')));
      await tester.pumpAndSettle();
      fakes.speech.hear('버릴 내용');
      await tester.pump();
      await tester.tap(find.byKey(const Key('voiceBack')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voiceDiscard')));
      await tester.pumpAndSettle();
      expect(fakes.memos.rows, isEmpty);
      expect(find.byKey(const Key('emptyMemos')), findsOneWidget);
    });
  });

  group('정리 화면', () {
    testWidgets('메모에서 일정을 찾아 확인 후 등록하고 일정 탭에서 완료한다', (tester) async {
      await pumpApp(
        tester,
        memos: [memo('a', '정비\n금요일 오후 3시에 자동차 정비 예약하라고 알려줘', 1)],
      );
      await tester.tap(find.text('정비'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('organizeButton')));
      await tester.pumpAndSettle();
      expect(find.text('자동차 정비 예약'), findsOneWidget);
      await tester.tap(find.byKey(const Key('registerCandidate')).first);
      await tester.pumpAndSettle();
      expect(find.text('정시'), findsOneWidget); // '알려줘' → 정시 알림
      await tester.tap(find.byKey(const Key('planSave')));
      await tester.pumpAndSettle();
      expect(find.text('등록됨'), findsOneWidget);

      Navigator.of(tester.element(find.text('등록됨'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('backButton')));
      await tester.pumpAndSettle();
      expect(find.text('자동차 정비 예약'), findsOneWidget); // 홈 '다가오는 일정'

      await goTab(tester, '일정');
      expect(find.text('내일'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('완료 1'));
      await tester.pumpAndSettle();
      expect(find.text('자동차 정비 예약'), findsOneWidget);
    });

    testWidgets('일정 탭에서 할 일을 추가하고 지운다', (tester) async {
      await pumpApp(tester);
      await goTab(tester, '일정');
      await tester.tap(find.byKey(const Key('addPlan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('planSave')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('planError')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('planTitle')), '은행 가기');
      await tester.tap(find.byKey(const Key('planSave')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('할 일 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('은행 가기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('planDelete')));
      await tester.pumpAndSettle();
      expect(find.text('은행 가기'), findsNothing);
    });

    testWidgets('분류를 직접 고치고 기록 탭에서 분류별로 본다', (tester) async {
      await pumpApp(
        tester,
        memos: [memo('a', '주간 회의 안건', 1), memo('b', '우유 사기', 2)],
      );
      await tester.tap(find.text('주간 회의 안건'));
      await tester.pumpAndSettle();
      expect(find.textContaining('회의'), findsWidgets);
      await tester.tap(find.byKey(const Key('labelChip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category-idea')));
      await tester.tap(find.byKey(const Key('saveLabel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('backButton')));
      await tester.pumpAndSettle();

      await goTab(tester, '기록');
      await tester.tap(find.byKey(const Key('filter-idea')));
      await tester.pumpAndSettle();
      expect(find.text('주간 회의 안건'), findsOneWidget);
      expect(find.text('우유 사기'), findsNothing);
    });

    testWidgets('하루 정리: 메모가 있으면 만들고, 고치고, 지운다', (tester) async {
      await pumpApp(
        tester,
        memos: [today('a', '출시 회의\n출시일은 12월 1일로 결정했다.', 1)],
      );
      await tester.tap(find.byKey(const Key('homeSummary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('summaryCreate')));
      await tester.pumpAndSettle();
      expect(find.text('· 출시일은 12월 1일로 결정했다.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('summaryMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('summaryEdit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('summaryField-todos')),
        '발표 자료 만들기',
      );
      await tester.tap(find.byKey(const Key('summarySave')));
      await tester.pumpAndSettle();
      expect(find.text('· 발표 자료 만들기'), findsOneWidget);
      expect(find.textContaining('직접 고침'), findsOneWidget);

      await tester.tap(find.byKey(const Key('summaryMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('summaryDelete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmAction')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('summaryCreate')), findsOneWidget);

      await tester.tap(find.byKey(const Key('prevDay')));
      await tester.pumpAndSettle();
      expect(find.text('이 날 쓴 메모가 없어 요약을 만들 수 없어요.'), findsOneWidget);
    });
  });

  group('설정', () {
    testWidgets('AI 사용량과 데이터 현황을 보여 준다', (tester) async {
      await pumpApp(
        tester,
        memos: [memo('a', '회의', 1)],
        setUp: (f) => f.account.usage = const [
          DailyUsage('2026-11-12', 3),
          DailyUsage('2026-11-10', 2),
        ],
      );
      await goTab(tester, '설정');
      expect(find.text('AI 다듬기 오늘 3회 / 하루 50회 · 최근 7일 5회'), findsOneWidget);
      expect(find.text('서버에 저장된 메모 1개'), findsOneWidget);
    });

    testWidgets('내보내기는 웹이 아니면 클립보드에 복사한다', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await pumpApp(tester, memos: [memo('a', '회의록', 1)]);
      await goTab(tester, '설정');
      await tester.scrollUntilVisible(find.byKey(const Key('exportData')), 200);
      await tester.ensureVisible(find.byKey(const Key('exportData')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exportData')));
      await tester.pumpAndSettle();
      expect(copied, contains('회의록'));
      expect(find.text('내보낸 내용을 클립보드에 복사했어요.'), findsOneWidget);
    });

    testWidgets('계정 삭제: "삭제"를 입력해야 하고, 메모를 모두 지운 뒤 로그아웃한다', (tester) async {
      final fakes = await pumpApp(tester, memos: [memo('a', '회의', 1)]);
      await goTab(tester, '설정');
      await tester.scrollUntilVisible(
        find.byKey(const Key('deleteAccount')),
        200,
      );
      await tester.ensureVisible(find.byKey(const Key('deleteAccount')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteAccount')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('deleteConfirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('deleteConfirmInput')), '삭제');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.textContaining('계정은 남아 있어요'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(fakes.account.calls, ['deleteAccount']);
      expect(fakes.memos.rows, isEmpty);
      expect(fakes.auth.calls.last, 'signOut');
      expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
    });
  });

  group('화면 크기별 메뉴', () {
    testWidgets('휴대폰: 아래 메뉴와 오른쪽 아래 음성 기록 버튼(설정에서는 숨김)', (tester) async {
      final fakes = await pumpApp(tester, size: const Size(390, 844));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const Key('voiceFab')), findsOneWidget);
      await goTab(tester, '기록');
      expect(find.byKey(const Key('voiceFab')), findsOneWidget);
      await tester.tap(find.byKey(const Key('voiceFab')));
      await tester.pumpAndSettle();
      expect(fakes.speech.isListening, isTrue);
      await tester.tap(find.byKey(const Key('voiceBack')));
      await tester.pumpAndSettle();
      await goTab(tester, '설정');
      expect(find.byKey(const Key('voiceFab')), findsNothing);
    });

    testWidgets('태블릿: 왼쪽 아이콘 메뉴와 음성 기록 버튼', (tester) async {
      await pumpApp(tester, size: const Size(800, 1100));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const Key('railVoice')), findsOneWidget);
    });

    testWidgets('PC: 이름이 붙은 사이드바와 음성 기록·새 메모 버튼', (tester) async {
      final fakes = await pumpApp(tester, size: const Size(1280, 800));
      expect(find.byKey(const Key('sidebar')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byKey(const Key('side-일정')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addPlan')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sidebarText')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('memoInput')), findsOneWidget);
      await tester.tap(find.byKey(const Key('backButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sidebarVoice')));
      await tester.pumpAndSettle();
      expect(fakes.speech.isListening, isTrue);
      await tester.tap(find.byKey(const Key('voiceStop')));
      await tester.pumpAndSettle();
    });
  });
}

DateTime seoul(int m, int d, [int h = 0, int min = 0]) =>
    fromSeoul(2026, m, d, h, min)!;
