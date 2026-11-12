import '../core/seoul_time.dart';

/// 알림 시점(일정 시각 기준)
enum ReminderOffset {
  atTime('정시', Duration.zero),
  min10('10분 전', Duration(minutes: 10)),
  min30('30분 전', Duration(minutes: 30)),
  hour1('1시간 전', Duration(hours: 1)),
  day1('하루 전', Duration(days: 1));

  const ReminderOffset(this.label, this.before);

  final String label;
  final Duration before;

  static ReminderOffset? byName(String? name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

/// 일정 또는 할 일. 시각([dueAt])이 있으면 일정, 없으면 할 일이다.
class PlanItem {
  const PlanItem({
    required this.id,
    required this.title,
    required this.createdAt,
    this.dueAt,
    this.allDay = false,
    this.reminder,
    this.done = false,
    this.memoId,
    this.notifiedAt,
  });

  final String id;
  final String title;

  /// 일정 시각(UTC). 하루 종일 일정이면 그날 한국 시간 0시.
  final DateTime? dueAt;
  final bool allDay;

  /// 알림. null이면 끔.
  final ReminderOffset? reminder;
  final bool done;

  /// 이 일정을 뽑아 온 메모(메모가 지워지면 null)
  final String? memoId;
  final DateTime createdAt;

  /// 알림을 보낸 시각
  final DateTime? notifiedAt;

  bool get isSchedule => dueAt != null;

  /// 알림을 보낼 시각. 하루 종일 일정은 그날 오전 9시를 기준으로 한다.
  DateTime? get remindAt {
    final due = dueAt;
    final r = reminder;
    if (due == null || r == null) return null;
    final base = allDay ? due.add(const Duration(hours: 9)) : due;
    return base.subtract(r.before);
  }

  /// 한국 날짜
  DateTime? get seoulDate => dueAt == null ? null : seoulDay(dueAt!);

  PlanItem copyWith({
    String? title,
    DateTime? Function()? dueAt,
    bool? allDay,
    ReminderOffset? Function()? reminder,
    bool? done,
    String? Function()? memoId,
    DateTime? Function()? notifiedAt,
  }) => PlanItem(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    dueAt: dueAt == null ? this.dueAt : dueAt(),
    allDay: allDay ?? this.allDay,
    reminder: reminder == null ? this.reminder : reminder(),
    done: done ?? this.done,
    memoId: memoId == null ? this.memoId : memoId(),
    notifiedAt: notifiedAt == null ? this.notifiedAt : notifiedAt(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'dueAt': dueAt?.toUtc().toIso8601String(),
    'allDay': allDay,
    'reminder': reminder?.name,
    'done': done,
    'memoId': memoId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'notifiedAt': notifiedAt?.toUtc().toIso8601String(),
  };

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
    id: json['id'] as String,
    title: json['title'] as String,
    dueAt: _date(json['dueAt']),
    allDay: json['allDay'] as bool? ?? false,
    reminder: ReminderOffset.byName(json['reminder'] as String?),
    done: json['done'] as bool? ?? false,
    memoId: json['memoId'] as String?,
    createdAt: _date(json['createdAt']) ?? DateTime.now().toUtc(),
    notifiedAt: _date(json['notifiedAt']),
  );

  static DateTime? _date(Object? v) => v is String ? DateTime.parse(v) : null;
}
