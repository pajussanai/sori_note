import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../core/seoul_time.dart';
import '../../models/memo.dart';
import '../../services/organizer.dart';
import '../../widgets/list_rows.dart';
import '../plans/plan_edit_sheet.dart';

/// 메모 정리: 글에서 찾은 일정·할 일 후보(확인 후 등록)와 관련 메모.
Future<void> showOrganizeSheet(
  BuildContext context, {
  required NoteStore store,
  required String text,
  required Memo? memo,
  required void Function(Memo memo) openMemo,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _OrganizeSheet(
      store: store,
      text: text,
      memo: memo,
      openMemo: openMemo,
    ),
  );
}

class _OrganizeSheet extends StatefulWidget {
  const _OrganizeSheet({
    required this.store,
    required this.text,
    required this.memo,
    required this.openMemo,
  });

  final NoteStore store;
  final String text;
  final Memo? memo;
  final void Function(Memo memo) openMemo;

  @override
  State<_OrganizeSheet> createState() => _OrganizeSheetState();
}

class _OrganizeSheetState extends State<_OrganizeSheet> {
  late final List<ScheduleCandidate> _candidates = widget.store.organizer
      .extractSchedules(widget.text, widget.store.now);
  final _registered = <int>{};

  Future<void> _register(int index) async {
    final saved = await showPlanEditSheet(
      context,
      widget.store,
      candidate: _candidates[index],
      memoId: widget.memo?.id,
    );
    if (saved && mounted) setState(() => _registered.add(index));
  }

  @override
  Widget build(BuildContext context) {
    final memo = widget.memo;
    final related = memo == null
        ? const <Memo>[]
        : widget.store.relatedTo(memo);
    final today = seoulDay(widget.store.now);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              '메모 정리',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SectionHeader('일정·할 일 후보'),
          if (_candidates.isEmpty)
            const EmptyHint('이 메모에서 날짜·시간이나 할 일을 찾지 못했어요.')
          else
            for (var i = 0; i < _candidates.length; i++)
              _CandidateRow(
                key: ValueKey('candidate-$i'),
                candidate: _candidates[i],
                today: today,
                registered: _registered.contains(i),
                onRegister: () => _register(i),
              ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: Text(
              '날짜·시간은 한국 시간 기준이며, 등록하기 전에 확인할 수 있어요.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          const SectionHeader('관련 메모'),
          if (related.isEmpty)
            const EmptyHint('태그가 겹치는 메모가 없어요.')
          else
            for (final m in related)
              MemoRow(
                memo: m,
                store: widget.store,
                onTap: () => widget.openMemo(m),
              ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    super.key,
    required this.candidate,
    required this.today,
    required this.registered,
    required this.onRegister,
  });

  final ScheduleCandidate candidate;
  final DateTime today;
  final bool registered;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final due = candidate.dueAt;
    final when = due == null
        ? '할 일'
        : candidate.allDay
        ? '${relativeSeoulDate(seoulDay(due), today: today)} · 하루 종일'
        : '${relativeSeoulDate(seoulDay(due), today: today)} ${formatSeoulClock(due)}';
    final notes = [
      ...candidate.warnings,
      if (candidate.invalid != null) candidate.invalid!,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  when,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSub,
                  ),
                ),
                for (final n in notes)
                  Text(
                    n,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.danger,
                    ),
                  ),
              ],
            ),
          ),
          registered
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '등록됨',
                    style: TextStyle(color: AppColors.primary),
                  ),
                )
              : TextButton(
                  key: const Key('registerCandidate'),
                  onPressed: onRegister,
                  child: Text(candidate.needsConfirm ? '확인 후 등록' : '등록'),
                ),
        ],
      ),
    );
  }
}
