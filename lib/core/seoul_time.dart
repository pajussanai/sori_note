/// 한국 시간(Asia/Seoul, UTC+9, 일광 절약 시간 없음) 도우미.
///
/// 시각은 UTC로 저장하고, 날짜 계산과 표시는 기기 시간대와 상관없이 한국 시간으로 한다.
/// '한국 벽시계' 값은 UTC로 표시한 DateTime에 담는다(연·월·일·시·분만 의미가 있다).
library;

const seoulOffset = Duration(hours: 9);

/// 실제 시각 → 한국 벽시계
DateTime toSeoul(DateTime instant) => instant.toUtc().add(seoulOffset);

/// 지금의 한국 벽시계
DateTime seoulNow([DateTime? now]) => toSeoul(now ?? DateTime.now());

/// 실제 시각이 속한 한국 날짜(0시)
DateTime seoulDay(DateTime instant) {
  final s = toSeoul(instant);
  return DateTime.utc(s.year, s.month, s.day);
}

/// 한국 벽시계 → 실제 시각(UTC). 잘못된 날짜(2월 30일 등)면 null.
DateTime? fromSeoul(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
]) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  final wall = DateTime.utc(year, month, day, hour, minute);
  if (wall.month != month || wall.day != day) return null;
  return wall.subtract(seoulOffset);
}

/// 한국 날짜의 시작(0시)과 다음 날 시작을 실제 시각으로
({DateTime start, DateTime end}) seoulDayRange(DateTime seoulDate) {
  final start = DateTime.utc(
    seoulDate.year,
    seoulDate.month,
    seoulDate.day,
  ).subtract(seoulOffset);
  return (start: start, end: start.add(const Duration(days: 1)));
}

/// 날짜 저장용 키: 2026-11-12
String dayKey(DateTime seoulDate) =>
    '${seoulDate.year.toString().padLeft(4, '0')}-'
    '${seoulDate.month.toString().padLeft(2, '0')}-'
    '${seoulDate.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 11월 12일 (수)
String formatSeoulDate(DateTime seoulDate, {DateTime? today}) {
  final base =
      '${seoulDate.month}월 ${seoulDate.day}일 (${_weekdays[seoulDate.weekday - 1]})';
  final t = today ?? seoulDay(DateTime.now());
  if (seoulDate.year != t.year) return '${seoulDate.year}년 $base';
  return base;
}

/// 오늘·내일·어제를 말로 바꾼다. 아니면 날짜.
String relativeSeoulDate(DateTime seoulDate, {DateTime? today}) {
  final t = today ?? seoulDay(DateTime.now());
  final diff = seoulDate.difference(t).inDays;
  return switch (diff) {
    0 => '오늘',
    1 => '내일',
    2 => '모레',
    -1 => '어제',
    _ => formatSeoulDate(seoulDate, today: t),
  };
}

/// 오후 3:05
String formatSeoulClock(DateTime instant) {
  final s = toSeoul(instant);
  final h = s.hour;
  final period = h < 12 ? '오전' : '오후';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$period $h12:${s.minute.toString().padLeft(2, '0')}';
}
