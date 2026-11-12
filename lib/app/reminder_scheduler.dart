import 'dart:async';

import '../core/seoul_time.dart';
import '../services/notifier.dart';
import 'note_store.dart';

/// 소리노트가 열려 있는 동안 알림 시각이 된 일정을 기기 알림으로 보낸다.
///
/// 서버 푸시(브라우저를 닫아도 오는 알림)는 서버 비밀 키가 필요해 쓰지 않는다.
/// 보낼 알림이 있을 때만 30초마다 확인하고, 없으면 타이머를 멈춘다.
class ReminderScheduler {
  ReminderScheduler(this.store, this.notifier) {
    store.addListener(_reschedule);
    _reschedule();
  }

  final NoteStore store;
  final Notifier notifier;

  static const interval = Duration(seconds: 30);

  Timer? _timer;
  bool _checking = false;

  void _reschedule() {
    final needed = store.pendingReminders.isNotEmpty;
    if (needed && _timer == null) {
      _timer = Timer.periodic(interval, (_) => check());
      unawaited(check());
    } else if (!needed) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// 알림 시각이 지난 일정을 알린다(같은 일정은 한 번만).
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      final now = store.now;
      for (final plan in store.pendingReminders) {
        final at = plan.remindAt!;
        if (at.isAfter(now)) break;
        final due = plan.dueAt!;
        final when = plan.allDay
            ? '${relativeSeoulDate(seoulDay(due), today: seoulDay(now))} 하루 종일'
            : '${relativeSeoulDate(seoulDay(due), today: seoulDay(now))} ${formatSeoulClock(due)}';
        notifier.show(plan.title, '$when · 소리노트 일정');
        await store.markNotified(plan.id, now);
      }
    } finally {
      _checking = false;
    }
  }

  void dispose() {
    store.removeListener(_reschedule);
    _timer?.cancel();
    _timer = null;
  }
}
