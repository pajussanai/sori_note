import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../core/seoul_time.dart';
import '../../models/plan_item.dart';
import '../../services/notifier.dart';
import '../../widgets/list_rows.dart';
import '../shell/app_shell.dart';

enum _PlanTab { upcoming, todos, done }

/// 일정: 예정된 일정(날짜별), 미완료 할 일, 완료한 일, 알림 목록.
class PlansPage extends StatefulWidget {
  const PlansPage({
    super.key,
    required this.store,
    required this.nav,
    required this.notifier,
  });

  final NoteStore store;
  final ShellNav nav;
  final Notifier notifier;

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  _PlanTab _tab = _PlanTab.upcoming;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('일정'),
        actions: [
          IconButton(
            key: const Key('reminderList'),
            tooltip: '알림',
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) =>
                  _ReminderSheet(store: store, notifier: widget.notifier),
            ),
          ),
          // 오른쪽 아래는 음성 기록 버튼 자리이므로 추가는 위에 둔다.
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: FilledButton.icon(
              key: const Key('addPlan'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 40),
              ),
              onPressed: () => widget.nav.editPlan(null),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('추가'),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final overdue = store.overdue;
          final upcoming = store.upcoming;
          final todos = store.todos;
          final done = store.completed;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<_PlanTab>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: _PlanTab.upcoming,
                            label: Text(
                              '예정 ${upcoming.length + overdue.length}',
                            ),
                          ),
                          ButtonSegment(
                            value: _PlanTab.todos,
                            label: Text('할 일 ${todos.length}'),
                          ),
                          ButtonSegment(
                            value: _PlanTab.done,
                            label: Text('완료 ${done.length}'),
                          ),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (s) =>
                            setState(() => _tab = s.first),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        fabClearance,
                      ),
                      children: switch (_tab) {
                        _PlanTab.upcoming => _upcoming(overdue, upcoming),
                        _PlanTab.todos => _list(
                          todos,
                          '미완료 할 일이 없어요. 날짜 없이 등록하면 할 일이 돼요.',
                        ),
                        _PlanTab.done => _list(done, '완료한 일정이 없어요.'),
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card(List<PlanItem> plans) =>
      PlanCard(plans: plans, store: widget.store, onTap: widget.nav.editPlan);

  List<Widget> _list(List<PlanItem> items, String empty) => items.isEmpty
      ? [EmptyHint(empty, padding: const EdgeInsets.symmetric(vertical: 12))]
      : [const SizedBox(height: 8), _card(items)];

  /// 지난 일정, 그다음 날짜별 카드로 묶은 예정 일정
  List<Widget> _upcoming(List<PlanItem> overdue, List<PlanItem> upcoming) {
    if (overdue.isEmpty && upcoming.isEmpty) {
      return const [
        EmptyHint(
          '예정된 일정이 없어요.\n메모 화면 위의 일정 버튼으로 메모에서 날짜·시간을 찾아 등록하거나, 추가를 눌러 직접 등록하세요.',
          padding: EdgeInsets.symmetric(vertical: 12),
        ),
      ];
    }
    final today = seoulDay(widget.store.now);
    final widgets = <Widget>[];
    if (overdue.isNotEmpty) {
      widgets
        ..add(const _DayHeader('지난 일정(완료하지 않음)', AppColors.danger))
        ..add(_card(overdue));
    }
    final byDay = <DateTime, List<PlanItem>>{};
    for (final p in upcoming) {
      (byDay[p.seoulDate!] ??= []).add(p);
    }
    for (final MapEntry(key: day, value: plans) in byDay.entries) {
      final diff = day.difference(today).inDays;
      widgets
        ..add(
          _DayHeader(
            relativeSeoulDate(day, today: today),
            // 오늘 피치, 내일 라벤더, 그 뒤 민트
            switch (diff) {
              0 => AppColors.peach,
              1 => AppColors.lavender,
              _ => AppColors.mint,
            },
          ),
        )
        ..add(_card(plans));
    }
    return widgets;
  }
}

/// 날짜 묶음 제목: 상태 색 점 + 날짜
class _DayHeader extends StatelessWidget {
  const _DayHeader(this.title, this.color);

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// 알림 목록과 알림 권한
class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({required this.store, required this.notifier});

  final NoteStore store;
  final Notifier notifier;

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final permission = widget.notifier.permission;
    final pending = store.pendingReminders;
    final sent = store.sentReminders.take(10).toList();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              '알림',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    notifyPermissionText(permission),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
                if (permission == NotifyPermission.prompt)
                  TextButton(
                    onPressed: () async {
                      await widget.notifier.request();
                      if (mounted) setState(() {});
                    },
                    child: const Text('알림 허용'),
                  ),
              ],
            ),
          ),
          const SectionHeader('보낼 알림'),
          if (pending.isEmpty)
            const EmptyHint('알림을 켠 일정이 없어요.')
          else
            for (final p in pending)
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.notifications_active_outlined,
                  color: AppColors.primary,
                ),
                title: Text(p.title),
                subtitle: Text(
                  '${relativeSeoulDate(seoulDay(p.remindAt!), today: seoulDay(store.now))} '
                  '${formatSeoulClock(p.remindAt!)} 알림 (${p.reminder!.label})',
                ),
              ),
          const SectionHeader('보낸 알림'),
          if (sent.isEmpty)
            const EmptyHint('아직 보낸 알림이 없어요.')
          else
            for (final p in sent)
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.notifications_none_rounded,
                  color: AppColors.textMuted,
                ),
                title: Text(p.title),
                subtitle: Text(
                  '${relativeSeoulDate(seoulDay(p.notifiedAt!), today: seoulDay(store.now))} '
                  '${formatSeoulClock(p.notifiedAt!)}에 보냄',
                ),
              ),
        ],
      ),
    );
  }
}

/// 알림 권한 안내 문구(설정 화면과 함께 쓴다)
String notifyPermissionText(NotifyPermission p) => switch (p) {
  NotifyPermission.granted =>
    '알림이 켜져 있어요. 소리노트가 열려 있는 동안 알림 시각에 기기 알림을 보내요(브라우저를 닫으면 오지 않아요).',
  NotifyPermission.prompt => '알림을 받으려면 알림을 허용해 주세요. 소리노트가 열려 있는 동안 알림을 보내요.',
  NotifyPermission.denied =>
    '알림이 차단되어 있어요. 브라우저 설정에서 이 사이트의 알림을 허용해 주세요. 그동안 알림은 앱 안 목록에만 표시돼요.',
  NotifyPermission.unsupported => '이 브라우저는 알림을 지원하지 않아요(iPhone은 홈 화면에 추가한 앱에서만 지원). 알림 시각은 앱 안 목록에서 확인할 수 있어요.',
};
