import 'package:flutter_test/flutter_test.dart';

import 'package:sori_note/core/seoul_time.dart';
import 'package:sori_note/models/daily_summary.dart';
import 'package:sori_note/models/memo.dart';
import 'package:sori_note/models/memo_label.dart';
import 'package:sori_note/services/local_organizer.dart';
import 'package:sori_note/services/schedule_parser.dart';

/// 기준 시각: 2026-11-12(목) 한국 시간 오전 10시
final now = DateTime.utc(2026, 11, 12, 1);

DateTime seoul(int m, int d, [int h = 0, int min = 0]) =>
    fromSeoul(2026, m, d, h, min)!;

void main() {
  group('한국 시간', () {
    test('UTC 15시는 한국 다음 날 0시', () {
      expect(
        seoulDay(DateTime.utc(2026, 11, 12, 15)),
        DateTime.utc(2026, 11, 13),
      );
      expect(
        seoulDay(DateTime.utc(2026, 11, 12, 14, 59)),
        DateTime.utc(2026, 11, 12),
      );
    });

    test('없는 날짜와 시각은 null', () {
      expect(fromSeoul(2026, 2, 30), isNull);
      expect(fromSeoul(2026, 13, 1), isNull);
      expect(fromSeoul(2026, 1, 1, 24), isNull);
      expect(fromSeoul(2026, 11, 13, 15), DateTime.utc(2026, 11, 13, 6));
    });

    test('표시', () {
      final today = DateTime.utc(2026, 11, 12);
      expect(relativeSeoulDate(DateTime.utc(2026, 11, 13), today: today), '내일');
      expect(
        formatSeoulDate(DateTime.utc(2026, 11, 16), today: today),
        '11월 16일 (월)',
      );
      expect(formatSeoulClock(DateTime.utc(2026, 11, 13, 6)), '오후 3:00');
    });
  });

  group('자동 분류·태그', () {
    test('내용으로 분류한다', () {
      expect(
        classifyText('주간 회의록\n안건: 출시 일정 논의').category,
        MemoCategory.meeting,
      );
      expect(classifyText('장보기 목록 우유 사기, 계란 사기').category, MemoCategory.todo);
      expect(classifyText('고객 보고서 작성하고 팀장 결재 받기').category, MemoCategory.work);
      expect(
        classifyText('앱 아이디어: 음성으로 일기 쓰면 좋겠다').category,
        MemoCategory.idea,
      );
      expect(classifyText('가족이랑 주말 여행').category, MemoCategory.personal);
      expect(classifyText('ㅁㄴㅇㄹ').category, MemoCategory.other);
      expect(classifyText('').category, MemoCategory.other);
    });

    test('조사를 떼고 자주 나온 낱말을 태그로(최대 5개)', () {
      final tags = extractTags('출시 회의에서 출시 일정을 정했다. 디자인 검토는 다음 주에.');
      expect(tags.first, '출시');
      expect(tags, contains('일정'));
      expect(tags, isNot(contains('정했다')));
      expect(tags, isNot(contains('다음')));
      expect(tags.length, lessThanOrEqualTo(5));
      expect(extractTags('3시 15일 금요일'), isEmpty);
    });
  });

  group('일정 찾기', () {
    test('요일·오후·알려줘: 금요일 오후 3시 자동차 정비 예약', () {
      final c = parseSchedules('금요일 오후 3시에 자동차 정비 예약하라고 알려줘', now).single;
      expect(c.title, '자동차 정비 예약');
      expect(c.dueAt, seoul(11, 13, 15));
      expect(c.allDay, isFalse);
      expect(c.remindAtTime, isTrue);
      expect(c.needsConfirm, isFalse);
    });

    test('오전/오후가 없으면 추정하고 확인을 요청한다', () {
      final c = parseSchedules('내일 9시 팀 회의', now).single;
      expect(c.dueAt, seoul(11, 13, 9));
      expect(c.warnings.single, contains('오전/오후'));
      expect(parseSchedules('내일 3시 미팅', now).single.dueAt, seoul(11, 13, 15));
    });

    test('날짜만 있으면 하루 종일, 다음 주 요일', () {
      final c = parseSchedules('다음 주 월요일 보고서 제출', now).single;
      expect(c.allDay, isTrue);
      expect(c.dueAt, seoul(11, 16));
      expect(c.title, '보고서 제출');
    });

    test('여러 날짜 표현', () {
      expect(
        parseSchedules('11월 20일 오후 2시 30분 치과', now).single.dueAt,
        seoul(11, 20, 14, 30),
      );
      expect(
        parseSchedules('2026-12-01 14:00 발표', now).single.dueAt,
        seoul(12, 1, 14),
      );
      expect(
        parseSchedules('모레 저녁 7시 반 저녁 약속', now).single.dueAt,
        seoul(11, 14, 19, 30),
      );
      expect(parseSchedules('3일 후 마감', now).single.dueAt, seoul(11, 15));
      final bare = parseSchedules('15일 병원', now).single;
      expect(bare.dueAt, seoul(11, 15));
      expect(bare.warnings.single, contains('몇 월'));
    });

    test('지난 날짜·없는 날짜는 등록할 수 없게 표시한다', () {
      expect(parseSchedules('11월 1일 회의', now).single.invalid, contains('지난'));
      expect(parseSchedules('오늘 오전 8시 운동', now).single.invalid, contains('지난'));
      expect(
        parseSchedules('2월 30일 행사', now).single.invalid,
        contains('없는 날짜'),
      );
    });

    test('시각만 있으면 오늘(지났으면 내일)로 보고 확인을 요청한다', () {
      final later = parseSchedules('오후 5시 전화하기', now).single;
      expect(later.dueAt, seoul(11, 12, 17));
      expect(later.warnings, contains(contains('오늘')));
      expect(parseSchedules('오전 8시 운동', now).single.dueAt, seoul(11, 13, 8));
    });

    test('날짜 없는 할 일과 일정 아닌 문장', () {
      final todo = parseSchedules('- 우유 사기', now).single;
      expect(todo.dueAt, isNull);
      expect(todo.title, '우유 사기');
      expect(parseSchedules('오늘은 기분이 좋았다. 날씨가 맑음.', now).length, 1);
      expect(parseSchedules('그냥 생각나는 대로 적는 글', now), isEmpty);
    });
  });

  group('하루 요약', () {
    Memo m(String id, String content, int minute) => Memo(
      id: id,
      content: content,
      createdAt: DateTime.utc(2026, 11, 12, 1, minute),
      updatedAt: DateTime.utc(2026, 11, 12, 1, minute),
    );

    test('문장을 항목별로 나눈다', () {
      final memos = [
        m('a', '출시 회의\n출시일은 12월 1일로 결정했다.\n디자인 지연이 문제다.\n금요일까지 QA 해야 함.', 1),
        m('b', '개인 메모\n비밀번호 바꾸는 것 꼭 기억하기', 2),
      ];
      final labels = {
        'a': const MemoLabel(
          memoId: 'a',
          category: MemoCategory.meeting,
          tags: [],
          contentHash: '',
        ),
      };
      final s = summarizeMemos(memos, (id) => labels[id]);
      expect(s[SummarySection.highlights], ['[회의] 출시 회의', '개인 메모']);
      expect(s[SummarySection.decisions]!.single, contains('결정'));
      expect(s[SummarySection.issues]!.single, contains('지연'));
      expect(s[SummarySection.todos]!.single, contains('QA'));
      expect(s[SummarySection.remember]!.single, contains('기억'));
    });

    test('메모가 없으면 빈 요약', () {
      final s = summarizeMemos([], (_) => null);
      expect(s.values.every((v) => v.isEmpty), isTrue);
    });
  });
}
