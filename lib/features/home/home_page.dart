import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../core/seoul_time.dart';
import '../../models/daily_summary.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/list_rows.dart';
import '../../widgets/status_view.dart';
import '../shell/app_shell.dart';

/// 홈: 바로 기록 시작, 빠른 검색, 다가오는 일정, 하루 정리, 최근 기록.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            AppLogo(size: 30),
            SizedBox(width: 10),
            Text(
              '소리노트',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = store.error;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _QuickActions(nav: nav),
                  _SearchEntry(onTap: () => nav.goTab(AppShell.searchTab)),
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
                  else ...[
                    _UpcomingSection(store: store, nav: nav),
                    _SummarySection(store: store, nav: nav),
                    _RecentSection(store: store, nav: nav),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.nav});

  final ShellNav nav;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                key: const Key('newVoiceMemo'),
                onPressed: nav.openVoice,
                icon: const Icon(Icons.mic_rounded),
                label: const Text('음성 기록', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                key: const Key('newTextMemo'),
                onPressed: () => nav.openMemo(null),
                icon: const Icon(Icons.edit_rounded, size: 20),
                label: const Text('텍스트 메모'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const Key('homeSearch'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: AppColors.textSub),
                SizedBox(width: 10),
                Text('메모·태그 검색', style: TextStyle(color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingSection extends StatelessWidget {
  const _UpcomingSection({required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  @override
  Widget build(BuildContext context) {
    final upcoming = store.upcoming.take(3).toList();
    final todos = store.todos.length;
    final overdue = store.overdue.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          '다가오는 일정',
          action: '모두 보기',
          onAction: () => nav.goTab(AppShell.plansTab),
        ),
        if (upcoming.isEmpty)
          const EmptyHint('예정된 일정이 없어요. 메모 화면의 일정 버튼으로 메모에서 일정을 찾아 등록할 수 있어요.')
        else
          for (final p in upcoming)
            PlanRow(plan: p, store: store, onTap: () => nav.editPlan(p)),
        if (todos > 0 || overdue > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: Text(
              [
                if (todos > 0) '미완료 할 일 $todos개',
                if (overdue > 0) '지난 일정 $overdue개',
              ].join(' · '),
              style: const TextStyle(fontSize: 13, color: AppColors.textSub),
            ),
          ),
      ],
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  @override
  Widget build(BuildContext context) {
    final today = seoulDay(store.now);
    final todaySummary = store.summaryOf(today);
    final latest =
        todaySummary ??
        (store.summaries.isEmpty ? null : store.summaries.first);
    final highlights = latest?.items(SummarySection.highlights) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          '하루 정리',
          action: '날짜별 보기',
          onAction: () => nav.openSummary(null),
        ),
        InkWell(
          key: const Key('homeSummary'),
          onTap: () =>
              nav.openSummary(latest == null ? today : parseDayKey(latest.day)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: latest == null
                ? const Text(
                    '오늘 쓴 메모를 모아 주요 내용·할 일·결정 사항으로 정리할 수 있어요. 눌러서 요약을 만들어 보세요.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textSub,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${relativeSeoulDate(parseDayKey(latest.day), today: today)} 요약 · 메모 ${latest.memoCount}개',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final h in highlights.take(3))
                        Text(
                          '· $h',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, height: 1.5),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  @override
  Widget build(BuildContext context) {
    final recent = store.memos.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          '최근 기록',
          action: recent.isEmpty ? null : '모두 보기',
          onAction: () => nav.goTab(AppShell.recordsTab),
        ),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아직 메모가 없어요',
                  key: Key('emptyMemos'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  '\'음성 기록\'을 누르고 말하면 글자로 바꿔 메모로 저장해요.\n'
                  '저장한 메모는 자동으로 분류되고, 일정과 하루 요약으로 정리할 수 있어요.',
                  style: TextStyle(color: AppColors.textSub, height: 1.6),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 20, endIndent: 20),
            MemoRow(
              memo: recent[i],
              store: store,
              onTap: () => nav.openMemo(recent[i]),
            ),
          ],
      ],
    );
  }
}
