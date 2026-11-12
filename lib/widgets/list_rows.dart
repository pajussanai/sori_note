import 'package:flutter/material.dart';

import '../app/note_store.dart';
import '../app/theme.dart';
import '../core/date_utils.dart';
import '../core/seoul_time.dart';
import '../models/memo.dart';
import '../models/plan_item.dart';

/// 구역 제목(오른쪽에 '모두 보기' 같은 버튼)
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// 메모 한 줄: 제목, 시각, 미리보기, 분류·태그. 카드 대신 구분선으로 나눈다.
class MemoRow extends StatelessWidget {
  const MemoRow({
    super.key,
    required this.memo,
    required this.store,
    required this.onTap,
    this.preview,
  });

  final Memo memo;
  final NoteStore store;
  final VoidCallback onTap;

  /// 검색 결과처럼 따로 보여 줄 미리보기(없으면 메모의 둘째 줄부터)
  final String? preview;

  @override
  Widget build(BuildContext context) {
    final label = store.labelOf(memo.id);
    // 한 줄짜리 메모는 미리보기가 제목과 같으므로 보여 주지 않는다.
    final raw = preview ?? memo.preview;
    final text = raw == memo.title ? '' : raw;
    final meta = [
      if (label != null) label.category.label,
      for (final t in label?.tags.take(3) ?? const <String>[]) '#$t',
    ].join('  ');
    return InkWell(
      key: ValueKey('memo-${memo.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    memo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatListTime(memo.updatedAt, DateTime.now()),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.textSub,
                ),
              ),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 일정·할 일 한 줄: 완료 체크, 제목, 날짜·시각, 알림 표시
class PlanRow extends StatelessWidget {
  const PlanRow({
    super.key,
    required this.plan,
    required this.store,
    required this.onTap,
  });

  final PlanItem plan;
  final NoteStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final due = plan.dueAt;
    final today = seoulDay(store.now);
    final when = due == null
        ? '할 일'
        : plan.allDay
        ? '${relativeSeoulDate(seoulDay(due), today: today)} · 하루 종일'
        : '${relativeSeoulDate(seoulDay(due), today: today)} ${formatSeoulClock(due)}';
    final late = !plan.done && due != null && seoulDay(due).isBefore(today);
    return InkWell(
      key: ValueKey('plan-${plan.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('planDone-${plan.id}'),
              value: plan.done,
              onChanged: (v) => store.setDone(plan.id, v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: plan.done
                          ? AppColors.textMuted
                          : AppColors.textMain,
                      decoration: plan.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    late ? '$when · 지남' : when,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: late ? AppColors.danger : AppColors.textSub,
                    ),
                  ),
                ],
              ),
            ),
            if (plan.reminder != null && !plan.done)
              Icon(
                plan.notifiedAt == null
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none_rounded,
                size: 18,
                color: plan.notifiedAt == null
                    ? AppColors.primary
                    : AppColors.textMuted,
                semanticLabel: plan.notifiedAt == null
                    ? '알림 ${plan.reminder!.label}'
                    : '알림 보냄',
              ),
          ],
        ),
      ),
    );
  }
}

/// 비어 있을 때 안내 한 줄
class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textMuted,
          height: 1.5,
        ),
      ),
    );
  }
}
