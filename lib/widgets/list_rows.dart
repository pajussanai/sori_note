import 'package:flutter/material.dart';

import '../app/note_store.dart';
import '../app/theme.dart';
import '../core/date_utils.dart';
import '../core/seoul_time.dart';
import '../models/memo.dart';
import '../models/plan_item.dart';

/// 화면 좌우 기본 여백
const pagePadding = EdgeInsets.symmetric(horizontal: 20);

/// 오른쪽 아래 음성 기록 버튼에 마지막 항목이 가려지지 않게 두는 아래 여백
const fabClearance = 104.0;

/// 흰 카드: 옅은 테두리, 둥근 모서리. [onTap]이 있으면 눌린다.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.surface,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: cardShape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 구역 제목(오른쪽에 '모두 보기' 같은 버튼)
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(20, 22, 8, 8),
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.teal,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// 분류·태그 표시(민트 알약 + 태그 글자)
class LabelLine extends StatelessWidget {
  const LabelLine({super.key, required this.category, required this.tags});

  final String? category;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (category != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              category!,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        if (tags.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tags.map((t) => '#$t').join('  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.teal),
            ),
          ),
        ],
      ],
    );
  }
}

/// 메모 카드: 제목, 시각, 미리보기, 분류·태그.
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
    return AppCard(
      key: ValueKey('memo-${memo.id}'),
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                    fontWeight: FontWeight.w700,
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
            const SizedBox(height: 4),
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
          if (label != null) ...[
            const SizedBox(height: 10),
            LabelLine(
              category: label.category.label,
              tags: label.tags.take(3).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// 메모 카드 목록(카드 사이 간격)
class MemoList extends StatelessWidget {
  const MemoList({
    super.key,
    required this.memos,
    required this.store,
    required this.onOpen,
  });

  final List<Memo> memos;
  final NoteStore store;
  final void Function(Memo memo) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < memos.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          MemoRow(memo: memos[i], store: store, onTap: () => onOpen(memos[i])),
        ],
      ],
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
        padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
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
                    ? AppColors.teal
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

/// 일정 행을 카드 하나에 구분선으로 묶는다.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plans,
    required this.store,
    required this.onTap,
  });

  final List<PlanItem> plans;
  final NoteStore store;
  final void Function(PlanItem plan) onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < plans.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 52, endIndent: 16),
            PlanRow(plan: plans[i], store: store, onTap: () => onTap(plans[i])),
          ],
        ],
      ),
    );
  }
}

/// 비어 있을 때 안내 한 줄
class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
