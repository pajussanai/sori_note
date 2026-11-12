import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../core/ids.dart';
import '../../core/seoul_time.dart';
import '../../models/plan_item.dart';
import '../../services/organizer.dart';

/// 일정·할 일을 추가하거나 고친다. 저장하면 true.
///
/// [candidate]가 있으면 메모에서 찾은 값을 채우고 확인할 점을 보여 준다.
/// 지난 시각·제목 없음은 저장하지 않는다(한국 시간 기준).
Future<bool> showPlanEditSheet(
  BuildContext context,
  NoteStore store, {
  PlanItem? plan,
  ScheduleCandidate? candidate,
  String? memoId,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _PlanEditSheet(
      store: store,
      plan: plan,
      candidate: candidate,
      memoId: memoId,
    ),
  );
  return saved ?? false;
}

class _PlanEditSheet extends StatefulWidget {
  const _PlanEditSheet({
    required this.store,
    this.plan,
    this.candidate,
    this.memoId,
  });

  final NoteStore store;
  final PlanItem? plan;
  final ScheduleCandidate? candidate;
  final String? memoId;

  @override
  State<_PlanEditSheet> createState() => _PlanEditSheetState();
}

class _PlanEditSheetState extends State<_PlanEditSheet> {
  late final _title = TextEditingController(
    text: widget.plan?.title ?? widget.candidate?.title ?? '',
  );

  /// 날짜(한국 날짜). null이면 할 일.
  DateTime? _date;

  /// 시각. null이면 하루 종일.
  TimeOfDay? _time;
  ReminderOffset? _reminder;
  String? _error;

  @override
  void initState() {
    super.initState();
    final due = widget.plan?.dueAt ?? widget.candidate?.dueAt;
    final allDay = widget.plan?.allDay ?? widget.candidate?.allDay ?? false;
    if (due != null) {
      _date = seoulDay(due);
      if (!allDay) {
        final s = toSeoul(due);
        _time = TimeOfDay(hour: s.hour, minute: s.minute);
      }
    }
    _reminder = widget.plan != null
        ? widget.plan!.reminder
        : due == null
        ? null
        : widget.candidate?.remindAtTime ?? false
        ? ReminderOffset.atTime
        : allDay
        ? null
        : ReminderOffset.min10;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime? get _dueAt {
    final d = _date;
    if (d == null) return null;
    final t = _time;
    return fromSeoul(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
  }

  Future<void> _pickDate() async {
    final today = seoulDay(widget.store.now);
    final initial = _date ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 3)),
      helpText: '날짜 선택',
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime.utc(picked.year, picked.month, picked.day);
      _reminder ??= _time == null ? null : ReminderOffset.min10;
      _error = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: '시간 선택',
    );
    if (picked == null) return;
    setState(() {
      _time = picked;
      _date ??= seoulDay(widget.store.now);
      _error = null;
    });
  }

  Future<void> _save() async {
    final store = widget.store;
    final base = widget.plan;
    final due = _dueAt;
    final plan = PlanItem(
      id: base?.id ?? newUuid(),
      title: _title.text.trim(),
      createdAt: base?.createdAt ?? store.now.toUtc(),
      dueAt: due,
      allDay: due != null && _time == null,
      reminder: due == null ? null : _reminder,
      done: base?.done ?? false,
      memoId: base?.memoId ?? widget.memoId,
      notifiedAt: base?.notifiedAt,
    );
    final problem = store.validatePlan(plan);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    await store.savePlan(plan);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final date = _date;
    final time = _time;
    final today = seoulDay(widget.store.now);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.plan == null ? '일정·할 일 등록' : '일정·할 일 고치기',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (candidate != null) ...[
              const SizedBox(height: 6),
              Text(
                '메모: "${candidate.sourceText}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
              for (final w in [
                ...candidate.warnings,
                if (candidate.invalid != null) candidate.invalid!,
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '확인: $w',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.danger,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            TextField(
              key: const Key('planTitle'),
              controller: _title,
              autofocus: widget.plan == null && candidate == null,
              decoration: appFieldDecoration(
                fillColor: AppColors.background,
                labelText: '제목',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('planDate'),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      date == null
                          ? '날짜 없음(할 일)'
                          : relativeSeoulDate(date, today: today),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('planTime'),
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(
                      time == null
                          ? (date == null ? '시간 없음' : '하루 종일')
                          : formatSeoulClock(_dueAt!),
                    ),
                  ),
                ),
              ],
            ),
            if (date != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 4,
                  children: [
                    if (time != null)
                      TextButton(
                        onPressed: () => setState(() => _time = null),
                        child: const Text('하루 종일로'),
                      ),
                    TextButton(
                      key: const Key('planClearDate'),
                      onPressed: () => setState(() {
                        _date = null;
                        _time = null;
                        _reminder = null;
                      }),
                      child: const Text('날짜 지우기(할 일로)'),
                    ),
                  ],
                ),
              ),
            if (date != null) ...[
              const SizedBox(height: 4),
              DropdownButtonFormField<ReminderOffset?>(
                key: const Key('planReminder'),
                initialValue: _reminder,
                decoration: appFieldDecoration(
                  fillColor: AppColors.background,
                  labelText: time == null ? '알림(당일 오전 9시 기준)' : '알림',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('알림 끄기')),
                  for (final r in ReminderOffset.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) => setState(() => _reminder = v),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const Key('planError'),
                style: const TextStyle(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.plan case final plan?) ...[
                  TextButton(
                    key: const Key('planDelete'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                    onPressed: () async {
                      await widget.store.deletePlan(plan.id);
                      if (context.mounted) Navigator.of(context).pop(true);
                    },
                    child: const Text('삭제'),
                  ),
                  const Spacer(),
                ],
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('planSave'),
                  onPressed: _save,
                  child: Text(widget.plan == null ? '등록' : '저장'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
