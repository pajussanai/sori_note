import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../core/seoul_time.dart';
import '../../models/daily_summary.dart';
import '../../models/memo.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/list_rows.dart';
import '../../widgets/status_view.dart';
import '../shell/app_shell.dart';

/// 홈: 개인 기록 대시보드.
/// 상단(로고·날짜·인사말·검색) → 오늘의 기록 → 오늘의 주요 일정 → 최근 기록 → 오늘의 정리.
/// 기록 시작 버튼(텍스트 메모·음성 기록)은 오른쪽 아래에 있다(AppShell).
/// 이미 있는 메모·일정·요약 데이터만 보여 주며, 새 AI 호출을 하지 않는다.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  /// 오른쪽 아래 두 버튼(텍스트 메모·음성 기록)에 가려지지 않게 두는 아래 여백
  static const bottomClearance = 176.0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        // PC는 사이드바에 로고가 있으므로 화면 이름만 보여 준다.
        title: wide
            ? const Text('홈')
            : const AppWordmark(logoSize: 30, fontSize: 20),
        actions: [
          IconButton(
            key: const Key('homeSearch'),
            tooltip: '검색',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => nav.goTab(AppShell.searchTab),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = store.error;
          final now = store.now;
          final today = seoulDay(now);
          final todayMemos = [
            for (final m in store.memos)
              if (seoulDay(m.createdAt) == today ||
                  seoulDay(m.updatedAt) == today)
                m,
          ];
          final summary = store.summaryOf(today);
          return LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 720;
              final record = _TodayRecordCard(
                memos: todayMemos,
                summary: summary,
                onOpen: nav.openMemo,
              );
              final plans = _TodayPlansCard(store: store, nav: nav);
              final recent = _RecentSection(store: store, nav: nav);
              final digest = _TodayDigestCard(
                summary: summary,
                todayMemoCount: todayMemos.length,
                onOpen: () => nav.openSummary(today),
              );
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      4,
                      20,
                      MediaQuery.sizeOf(context).width >= 600
                          ? 32
                          : bottomClearance,
                    ),
                    children: [
                      _Greeting(now: now),
                      const SizedBox(height: 18),
                      if (error != null)
                        SizedBox(
                          height: 260,
                          child: StatusView(
                            icon: Icons.cloud_off_rounded,
                            message: '메모를 불러오지 못했습니다.\n$error',
                            actionLabel: '다시 시도',
                            onAction: store.load,
                          ),
                        )
                      else if (twoColumns) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: record),
                            const SizedBox(width: 16),
                            Expanded(child: plans),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: recent),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 58),
                                child: digest,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        record,
                        const SizedBox(height: 14),
                        plans,
                        recent,
                        const SizedBox(height: 22),
                        digest,
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

const _weekdayNames = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];

/// 날짜와 시간대에 맞는 인사말(한국 시간)
class _Greeting extends StatelessWidget {
  const _Greeting({required this.now});

  final DateTime now;

  static String greeting(int hour) => switch (hour) {
    >= 5 && < 11 => '좋은 아침이에요',
    >= 11 && < 17 => '좋은 오후예요',
    >= 17 && < 22 => '좋은 저녁이에요',
    _ => '편안한 밤 보내세요',
  };

  @override
  Widget build(BuildContext context) {
    final s = seoulNow(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${s.month}월 ${s.day}일 ${_weekdayNames[s.weekday - 1]}',
          style: const TextStyle(fontSize: 14, color: AppColors.textSub),
        ),
        const SizedBox(height: 4),
        Text(
          greeting(s.hour),
          key: const Key('homeGreeting'),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: AppColors.textMain,
          ),
        ),
      ],
    );
  }
}

/// 카드 제목줄: 색 아이콘 + 제목 + 오른쪽 보조 요소
class _CardTitle extends StatelessWidget {
  const _CardTitle({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconFg),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// 오늘의 기록: 오늘 쓴 메모 수, 주요 기록(요약이 있으면), 최근 기록의 핵심
class _TodayRecordCard extends StatelessWidget {
  const _TodayRecordCard({
    required this.memos,
    required this.summary,
    required this.onOpen,
  });

  final List<Memo> memos;
  final DailySummary? summary;
  final void Function(Memo memo) onOpen;

  @override
  Widget build(BuildContext context) {
    final latest = memos.isEmpty ? null : memos.first;
    final highlights = summary?.items(SummarySection.highlights) ?? const [];
    return GradientBorderCard(
      key: const Key('homeToday'),
      onTap: latest == null ? null : () => onOpen(latest),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.auto_awesome_rounded,
            iconBg: AppColors.peachLight,
            iconFg: AppColors.peachDeep,
            title: '오늘의 기록',
          ),
          const SizedBox(height: 14),
          if (latest == null)
            const Text(
              '오늘은 아직 기록이 없어요.\n오른쪽 아래 마이크를 누르고 말하면 바로 메모가 돼요.',
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: AppColors.textSub,
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${memos.length}',
                  key: const Key('todayMemoCount'),
                  style: const TextStyle(
                    fontSize: 34,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 3),
                  child: Text(
                    '개의 메모를 남겼어요',
                    style: TextStyle(fontSize: 14, color: AppColors.textSub),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (highlights.isNotEmpty) ...[
              const _MiniLabel('주요 기록'),
              for (final h in highlights.take(2))
                _Bullet(h, color: AppColors.peach),
              const SizedBox(height: 10),
            ],
            const _MiniLabel('최근 기록'),
            Text(
              latest.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (latest.preview.isNotEmpty)
              Text(
                latest.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppColors.textSub,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 8),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// 오늘의 주요 일정: 다가오는 일정 4개와 미완료 할 일 수(피치 카드)
class _TodayPlansCard extends StatelessWidget {
  const _TodayPlansCard({required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  @override
  Widget build(BuildContext context) {
    final upcoming = store.upcoming.take(4).toList();
    final todos = store.todos.length;
    final overdue = store.overdue.length;
    return AppCard(
      color: AppColors.peachLight,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.event_rounded,
            iconBg: AppColors.surface,
            iconFg: AppColors.peachDeep,
            title: '오늘의 주요 일정',
            trailing: TextButton(
              onPressed: () => nav.goTab(AppShell.plansTab),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.peachDeep,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('모두 보기'),
            ),
          ),
          const SizedBox(height: 8),
          if (upcoming.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '예정된 일정이 없어요. 메모 화면에서 일정을 찾아 등록할 수 있어요.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSub,
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                children: [
                  for (var i = 0; i < upcoming.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 48, endIndent: 12),
                    PlanRow(
                      plan: upcoming[i],
                      store: store,
                      onTap: () => nav.editPlan(upcoming[i]),
                    ),
                  ],
                ],
              ),
            ),
          if (todos > 0 || overdue > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                children: [
                  if (todos > 0) _Pill('미완료 할 일 $todos개', AppColors.peachDeep),
                  if (overdue > 0) _Pill('지난 일정 $overdue개', AppColors.danger),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.fg);

  final String text;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// 최근 기록(메모 카드 4개)과 전체 기록으로 가기
class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  @override
  Widget build(BuildContext context) {
    final recent = store.memos.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          '최근 기록',
          action: recent.isEmpty ? null : '전체 기록',
          onAction: () => nav.goTab(AppShell.recordsTab),
          padding: const EdgeInsets.fromLTRB(4, 24, 0, 10),
        ),
        if (recent.isEmpty)
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아직 메모가 없어요',
                  key: Key('emptyMemos'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  '오른쪽 아래 마이크를 누르고 말하면 글자로 바꿔 메모로 저장해요. '
                  '연필 버튼으로 직접 쓸 수도 있어요.',
                  style: TextStyle(color: AppColors.textSub, height: 1.6),
                ),
              ],
            ),
          )
        else
          MemoList(memos: recent, store: store, onOpen: nav.openMemo),
      ],
    );
  }
}

/// 오늘의 정리: 저장된 하루 요약의 일부(주요 내용·결정·할 일·기억할 것)(라벤더 카드)
class _TodayDigestCard extends StatelessWidget {
  const _TodayDigestCard({
    required this.summary,
    required this.todayMemoCount,
    required this.onOpen,
  });

  final DailySummary? summary;
  final int todayMemoCount;
  final VoidCallback onOpen;

  static const _sections = [
    (SummarySection.highlights, '주요 내용', AppColors.lavender),
    (SummarySection.decisions, '결정', AppColors.peach),
    (SummarySection.todos, '할 일', AppColors.mint),
    (SummarySection.remember, '기억할 것', AppColors.pink),
  ];

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final parts = [
      if (summary != null)
        for (final (section, label, color) in _sections)
          if (summary.items(section).isNotEmpty)
            (label, summary.items(section).first, color),
    ];
    return AppCard(
      key: const Key('homeSummary'),
      color: AppColors.lavenderLight,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.summarize_outlined,
            iconBg: AppColors.surface,
            iconFg: AppColors.primary,
            title: '오늘의 정리',
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (summary == null)
            Text(
              todayMemoCount == 0
                  ? '오늘 메모를 남기면 주요 내용, 결정 사항, 할 일로 정리해 드려요.'
                  : '오늘 메모 $todayMemoCount개로 하루 정리를 만들 수 있어요. 눌러서 만들어 보세요.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: AppColors.textSub,
              ),
            )
          else if (parts.isEmpty)
            const Text(
              '정리할 만한 내용이 아직 없어요.',
              style: TextStyle(fontSize: 14, color: AppColors.textSub),
            )
          else
            for (final (label, text, color) in parts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      margin: const EdgeInsets.only(right: 10, top: 1),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color, width: 1.2),
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSub,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
