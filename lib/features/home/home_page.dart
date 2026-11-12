import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../core/seoul_time.dart';
import '../../models/daily_summary.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/list_rows.dart';
import '../../widgets/status_view.dart';
import '../shell/app_shell.dart';

/// 홈: 브랜드·검색 → 날짜·인사말 → 음성 기록·텍스트 메모 → 오늘의 요약 →
/// 다가오는 일정 → 최근 메모. 오른쪽 아래 음성 기록 버튼은 앱 뼈대(AppShell)에 있다.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        // PC는 사이드바에 로고가 있으므로 화면 이름만 보여 준다.
        title: MediaQuery.sizeOf(context).width >= 1100
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
          return LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 720;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, fabClearance),
                    children: [
                      _Greeting(today: seoulDay(store.now)),
                      const SizedBox(height: 16),
                      _EntryCards(nav: nav),
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
                        const SizedBox(height: 20),
                        if (twoColumns)
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _SummaryCard(store: store, nav: nav),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _UpcomingCard(store: store, nav: nav),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          _SummaryCard(store: store, nav: nav),
                          const SizedBox(height: 16),
                          _UpcomingCard(store: store, nav: nav),
                        ],
                        _RecentSection(store: store, nav: nav),
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

class _Greeting extends StatelessWidget {
  const _Greeting({required this.today});

  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${today.month}월 ${today.day}일 ${_weekdayNames[today.weekday - 1]}',
          style: const TextStyle(fontSize: 14, color: AppColors.textSub),
        ),
        const SizedBox(height: 4),
        const Text(
          '오늘도 말로 가볍게 기록해 보세요',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.textMain,
          ),
        ),
      ],
    );
  }
}

/// 음성 기록(주요, 딥 틸)과 텍스트 메모(보조, 흰 카드)
class _EntryCards extends StatelessWidget {
  const _EntryCards({required this.nav});

  final ShellNav nav;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: AppCard(
              key: const Key('newVoiceMemo'),
              color: AppColors.primary,
              onTap: nav.openVoice,
              padding: const EdgeInsets.all(18),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.mint,
                    child: Icon(Icons.mic_rounded, color: AppColors.primary),
                  ),
                  Spacer(),
                  Text(
                    '음성 기록',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '말하면 글자로 바꿔 메모해요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: AppColors.mint),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: AppCard(
              key: const Key('newTextMemo'),
              onTap: () => nav.openMemo(null),
              padding: const EdgeInsets.all(18),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryLight,
                    child: Icon(Icons.edit_outlined, color: AppColors.primary),
                  ),
                  Spacer(),
                  Text(
                    '텍스트 메모',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMain,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '직접 입력',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSub),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 카드 안 제목줄(제목 + 오른쪽 작은 버튼)
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action!,
                    style: const TextStyle(fontSize: 13, color: AppColors.teal),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.teal,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.store, required this.nav});

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
    final todos = latest?.items(SummarySection.todos) ?? const [];
    return AppCard(
      key: const Key('homeSummary'),
      onTap: () =>
          nav.openSummary(latest == null ? today : parseDayKey(latest.day)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            latest == null || latest.day == dayKey(today)
                ? '오늘의 요약'
                : '최근 요약 · ${relativeSeoulDate(parseDayKey(latest.day), today: today)}',
            action: '하루 정리',
            onAction: () => nav.openSummary(null),
          ),
          const SizedBox(height: 10),
          if (latest == null)
            const Text(
              '오늘 쓴 메모를 모아 주요 내용, 할 일, 결정 사항으로 정리해 드려요. 눌러서 요약을 만들어 보세요.',
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: AppColors.textSub,
              ),
            )
          else ...[
            for (final h in highlights.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '· $h',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              ),
            if (todos.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '해야 할 일 ${todos.length}개 · ${todos.first}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  @override
  Widget build(BuildContext context) {
    final upcoming = store.upcoming.take(3).toList();
    final todos = store.todos.length;
    final overdue = store.overdue.length;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            '다가오는 일정',
            action: '모두 보기',
            onAction: () => nav.goTab(AppShell.plansTab),
          ),
          const SizedBox(height: 4),
          if (upcoming.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
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
            for (final p in upcoming)
              // 체크박스를 카드 왼쪽 여백에 맞춘다.
              Transform.translate(
                offset: const Offset(-12, 0),
                child: PlanRow(
                  plan: p,
                  store: store,
                  onTap: () => nav.editPlan(p),
                ),
              ),
          if (todos > 0 || overdue > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                [
                  if (todos > 0) '미완료 할 일 $todos개',
                  if (overdue > 0) '지난 일정 $overdue개',
                ].join(' · '),
                style: const TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
            ),
        ],
      ),
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
          '최근 메모',
          action: recent.isEmpty ? null : '모두 보기',
          onAction: () => nav.goTab(AppShell.recordsTab),
          padding: const EdgeInsets.fromLTRB(4, 26, 0, 10),
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
                  '\'음성 기록\'을 누르고 말하면 글자로 바꿔 메모로 저장해요.\n'
                  '저장한 메모는 자동으로 분류되고, 일정과 하루 요약으로 정리할 수 있어요.',
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
