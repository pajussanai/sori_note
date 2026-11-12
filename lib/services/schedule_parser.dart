// 한국어 글에서 일정·할 일 후보를 찾는다(기기 안 규칙, 한국 시간 기준).
//
// 찾는 표현
//   날짜: 오늘·내일·모레·글피, N일 후, (이번 주|다음 주) 금요일, N월 N일, 2026-11-14, 11/14, N일
//   시각: (오전|오후|아침|점심|저녁|밤|새벽) N시 (N분|반), 14:30, 정오, 자정
// 모호하면 경고를 붙이고, 지난 시각·없는 날짜는 등록할 수 없게 표시한다.
import '../core/seoul_time.dart';
import 'organizer.dart';

const _maxCandidates = 10;

final _sentenceSplit = RegExp(r'\n+|(?<=[.!?])\s+');

final _isoDate = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})');
final _monthDay = RegExp(r'(\d{1,2})\s*월\s*(\d{1,2})\s*일');
final _slashDate = RegExp(r'(?<![\d/])(\d{1,2})/(\d{1,2})(?![\d/])');
final _daysLater = RegExp(r'(\d{1,2})\s*일\s*(?:후|뒤)');
final _relativeDay = RegExp(r'오늘|금일|내일|명일|모레|글피');
final _weekday = RegExp(r'(이번\s*주|다음\s*주|다다음\s*주)?\s*([월화수목금토일])요일');
final _bareDay = RegExp(r'(?<![\d월])(\d{1,2})\s*일(?![\d가-힣]*(?:동안|간|째))');

final _clock = RegExp(r'(?<!\d)([01]?\d|2[0-4]):([0-5]\d)(?!\d)');
final _hourMinute = RegExp(
  r'(오전|오후|아침|점심|저녁|밤|새벽|낮)?\s*(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분|\s*(반))?',
);
final _noonMidnight = RegExp(r'정오|자정');

final _remind = RegExp(
  r'(하라고|라고|하도록|하게)?\s*(알려\s*(줘|주세요|줄래|달라)|알림\s*(설정)?\s*(해\s*줘|해\s*주세요)?|리마인드(\s*해\s*줘)?|깨워\s*줘)',
);
final _todoWords = RegExp(
  r'해야|할 일|할일|하기\b|사기|사야|챙기|준비하|보내기|연락하|제출|예약하|신청하|결제하',
);
final _looseParticles = RegExp(
  r'(^|\s)(에|에는|까지|부터|에서|으로|로|은|는|이|가|을|를|쯤|경)(?=\s|$)',
);

const _weekdayIndex = {'월': 1, '화': 2, '수': 3, '목': 4, '금': 5, '토': 6, '일': 7};

/// 글에서 일정·할 일 후보를 찾는다(최대 10개).
List<ScheduleCandidate> parseSchedules(String text, DateTime now) {
  final result = <ScheduleCandidate>[];
  for (final raw in text.split(_sentenceSplit)) {
    final sentence = raw.trim().replaceFirst(RegExp(r'^[-*•·]\s*'), '');
    if (sentence.length < 2) continue;
    final candidate = _parseSentence(sentence, now);
    if (candidate != null) result.add(candidate);
    if (result.length >= _maxCandidates) break;
  }
  return result;
}

class _Span {
  _Span(this.start, this.end);
  final int start;
  final int end;
}

ScheduleCandidate? _parseSentence(String sentence, DateTime now) {
  final today = seoulDay(now);
  final spans = <_Span>[];
  final warnings = <String>[];
  String? invalid;

  bool free(Match m) => !spans.any((s) => m.start < s.end && m.end > s.start);
  void take(Match m) => spans.add(_Span(m.start, m.end));

  // ----------------------------------------------------------- 날짜
  DateTime? date; // 한국 날짜(0시)
  bool dateInvalid = false;

  DateTime? safeDate(int y, int m, int d) {
    final v = fromSeoul(y, m, d);
    if (v == null) {
      dateInvalid = true;
      return null;
    }
    return DateTime.utc(y, m, d);
  }

  final iso = _isoDate.firstMatch(sentence);
  if (iso != null) {
    take(iso);
    date = safeDate(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  }
  if (date == null && !dateInvalid) {
    final m = _monthDay.firstMatch(sentence);
    if (m != null && free(m)) {
      take(m);
      date = safeDate(today.year, int.parse(m[1]!), int.parse(m[2]!));
    }
  }
  if (date == null && !dateInvalid) {
    final m = _slashDate.firstMatch(sentence);
    if (m != null && free(m)) {
      take(m);
      date = safeDate(today.year, int.parse(m[1]!), int.parse(m[2]!));
    }
  }
  if (date == null && !dateInvalid) {
    final m = _daysLater.firstMatch(sentence);
    if (m != null && free(m)) {
      take(m);
      date = today.add(Duration(days: int.parse(m[1]!)));
    }
  }
  if (date == null && !dateInvalid) {
    final m = _relativeDay.firstMatch(sentence);
    if (m != null && free(m)) {
      take(m);
      final offset = switch (m[0]) {
        '오늘' || '금일' => 0,
        '내일' || '명일' => 1,
        '모레' => 2,
        _ => 3,
      };
      date = today.add(Duration(days: offset));
    }
  }
  var bareWeekdayToday = false;
  if (date == null && !dateInvalid) {
    final m = _weekday.firstMatch(sentence);
    if (m != null && free(m)) {
      take(m);
      final target = _weekdayIndex[m[2]]!;
      final week = m[1]?.replaceAll(RegExp(r'\s'), '');
      if (week == null) {
        var diff = (target - today.weekday) % 7;
        if (diff == 0) bareWeekdayToday = true;
        date = today.add(Duration(days: diff));
      } else {
        final monday = today.subtract(Duration(days: today.weekday - 1));
        final weeks = switch (week) {
          '이번주' => 0,
          '다음주' => 1,
          _ => 2,
        };
        date = monday.add(Duration(days: weeks * 7 + target - 1));
      }
    }
  }
  if (date == null && !dateInvalid) {
    final m = _bareDay.firstMatch(sentence);
    if (m != null && free(m)) {
      take(m);
      final day = int.parse(m[1]!);
      var month = today.month;
      var year = today.year;
      if (day < today.day) {
        month++;
        if (month > 12) {
          month = 1;
          year++;
        }
      }
      date = safeDate(year, month, day);
      if (date != null) {
        warnings.add('${date.month}월 ${date.day}일로 보았어요. 몇 월인지 확인해 주세요.');
      }
    }
  }
  if (dateInvalid) invalid = '없는 날짜예요.';

  // ----------------------------------------------------------- 시각
  int? hour;
  var minute = 0;
  final clock = _clock.firstMatch(sentence);
  if (clock != null && free(clock)) {
    take(clock);
    hour = int.parse(clock[1]!);
    minute = int.parse(clock[2]!);
  } else {
    final hm = _hourMinute.firstMatch(sentence);
    if (hm != null && free(hm)) {
      take(hm);
      final period = hm[1];
      final h = int.parse(hm[2]!);
      minute = hm[4] != null ? 30 : int.parse(hm[3] ?? '0');
      if (h > 24 || minute > 59) {
        invalid ??= '없는 시각이에요.';
      } else {
        hour = _applyPeriod(h, period, warnings);
      }
    } else {
      final nm = _noonMidnight.firstMatch(sentence);
      if (nm != null && free(nm)) {
        take(nm);
        hour = nm[0] == '정오' ? 12 : 0;
      }
    }
  }
  if (hour == 24) hour = 0;

  final remind = _remind.firstMatch(sentence);
  final remindAtTime = remind != null;

  // ----------------------------------------------------------- 후보 만들기
  final title = _title(sentence, spans);
  if (date == null && hour == null) {
    if (invalid != null) {
      return ScheduleCandidate(
        title: title.isEmpty ? '일정' : title,
        sourceText: sentence,
        invalid: invalid,
      );
    }
    // 날짜·시각은 없지만 할 일로 보이는 문장
    if (!_todoWords.hasMatch(sentence) && !remindAtTime) return null;
    return ScheduleCandidate(
      title: title.isEmpty ? '할 일' : title,
      sourceText: sentence,
      remindAtTime: remindAtTime,
    );
  }

  final nowSeoul = seoulNow(now);
  DateTime? dueAt;
  var allDay = false;
  if (date != null && hour == null) {
    allDay = true;
    dueAt = fromSeoul(date.year, date.month, date.day);
    if (date.isBefore(today)) invalid ??= '이미 지난 날짜예요.';
  } else if (hour != null) {
    var d = date;
    if (d == null) {
      // 시각만 있으면 오늘(이미 지났으면 내일)로 본다.
      final laterToday =
          hour > nowSeoul.hour ||
          (hour == nowSeoul.hour && minute > nowSeoul.minute);
      d = laterToday ? today : today.add(const Duration(days: 1));
      warnings.add('날짜가 없어 ${laterToday ? '오늘' : '내일'}로 보았어요.');
    }
    dueAt = fromSeoul(d.year, d.month, d.day, hour, minute);
    if (dueAt != null && !dueAt.isAfter(now)) {
      if (bareWeekdayToday) {
        // 오늘이 그 요일인데 시각이 지났으면 다음 주로 본다.
        final next = d.add(const Duration(days: 7));
        dueAt = fromSeoul(next.year, next.month, next.day, hour, minute);
        bareWeekdayToday = false;
        warnings.add('다음 주 ${_weekdayName(next)}로 보았어요.');
      } else {
        invalid ??= '이미 지난 시간이에요.';
      }
    }
  }
  if (bareWeekdayToday) warnings.add('오늘인지 다음 주인지 확인해 주세요.');

  return ScheduleCandidate(
    title: title.isEmpty ? '일정' : title,
    sourceText: sentence,
    dueAt: dueAt,
    allDay: allDay,
    remindAtTime: remindAtTime,
    warnings: warnings,
    invalid: invalid,
  );
}

int _applyPeriod(int h, String? period, List<String> warnings) {
  switch (period) {
    case '오전' || '아침' || '새벽':
      return h == 12 ? 0 : h;
    case '오후' || '저녁' || '밤' || '낮':
      return h < 12 ? h + 12 : h;
    case '점심':
      return h <= 5 ? h + 12 : h;
  }
  if (h == 0 || h >= 12) return h;
  // 오전/오후가 없으면 1~6시는 오후, 7~11시는 오전으로 보고 확인을 요청한다.
  if (h <= 6) {
    warnings.add('$h시를 오후로 보았어요. 오전/오후를 확인해 주세요.');
    return h + 12;
  }
  warnings.add('$h시를 오전으로 보았어요. 오전/오후를 확인해 주세요.');
  return h;
}

String _weekdayName(DateTime d) =>
    '${['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1]}요일';

/// 날짜·시각·알림 표현과 남는 조사를 빼서 제목을 만든다(최대 60자).
String _title(String sentence, List<_Span> spans) {
  final sorted = [...spans]..sort((a, b) => b.start.compareTo(a.start));
  var text = sentence;
  for (final s in sorted) {
    text = '${text.substring(0, s.start)} ${text.substring(s.end)}';
  }
  text = text.replaceAll(_remind, ' ');
  for (var i = 0; i < 2; i++) {
    text = text.replaceAll(_looseParticles, ' ');
  }
  text = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s,.:;~-]+|[\s,.:;~!?-]+$'), '')
      .trim();
  return text.length > 60 ? text.substring(0, 60) : text;
}
