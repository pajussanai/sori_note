import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/reminder_scheduler.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/seoul_time.dart';
import '../../models/memo.dart';
import '../../models/plan_item.dart';
import '../../widgets/app_logo.dart';
import '../../services/auth_service.dart';
import '../home/home_page.dart';
import '../memos/memo_editor_page.dart';
import '../memos/records_page.dart';
import '../plans/plan_edit_sheet.dart';
import '../plans/plans_page.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import '../summary/daily_summary_page.dart';
import '../voice/voice_record_page.dart';

/// 화면 사이 이동(각 화면이 함께 쓴다)
class ShellNav {
  const ShellNav({
    required this.openMemo,
    required this.openVoice,
    required this.openSummary,
    required this.editPlan,
    required this.goTab,
  });

  /// 메모 열기(null이면 새 텍스트 메모)
  final void Function(Memo? memo) openMemo;

  /// 음성 기록 시작
  final VoidCallback openVoice;

  /// 하루 정리(null이면 오늘)
  final void Function(DateTime? seoulDate) openSummary;

  /// 일정 추가(null)·고치기
  final void Function(PlanItem? plan) editPlan;

  final void Function(int tab) goTab;
}

/// 로그인 후 앱의 뼈대: 홈·기록·검색·일정·설정.
/// 휴대폰은 아래 탭, 넓은 화면(PC)은 왼쪽 메뉴로 보여 준다.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.user, required this.services});

  final AppUser user;
  final AppServices services;

  static const homeTab = 0;
  static const recordsTab = 1;
  static const searchTab = 2;
  static const plansTab = 3;
  static const settingsTab = 4;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final NoteStore _store = NoteStore(
    repository: widget.services.memos,
    local: widget.services.local,
    organizer: widget.services.organizer,
    userId: widget.user.id,
    clock: widget.services.clock,
  );
  late final _reminders = ReminderScheduler(_store, widget.services.notifier);
  int _tab = AppShell.homeTab;

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, '홈'),
    (Icons.sticky_note_2_outlined, Icons.sticky_note_2_rounded, '기록'),
    (Icons.search_rounded, Icons.search_rounded, '검색'),
    (Icons.event_outlined, Icons.event_rounded, '일정'),
    (Icons.settings_outlined, Icons.settings_rounded, '설정'),
  ];

  @override
  void initState() {
    super.initState();
    _store.addListener(_showNotice);
    _store.load();
  }

  @override
  void dispose() {
    _reminders.dispose();
    _store.removeListener(_showNotice);
    _store.dispose();
    super.dispose();
  }

  void _showNotice() {
    final notice = _store.notice;
    if (notice == null || !mounted) return;
    _store.clearNotice();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(notice)));
  }

  void _openMemo(Memo? memo) {
    final services = widget.services;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoEditorPage(
          memo: memo,
          store: _store,
          polishService: services.polish,
          speechInput: services.createSpeechInput(),
        ),
      ),
    );
  }

  Future<void> _openVoice() async {
    final services = widget.services;
    final saved = await Navigator.of(context).push<Memo>(
      MaterialPageRoute(
        builder: (_) => VoiceRecordPage(
          store: _store,
          polishService: services.polish,
          speechInput: services.createSpeechInput(),
        ),
      ),
    );
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('음성 기록을 메모로 저장했어요.'),
          action: SnackBarAction(
            label: '열기',
            onPressed: () => _openMemo(saved),
          ),
        ),
      );
  }

  void _openSummary(DateTime? day) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DailySummaryPage(
          store: _store,
          initialDay: day ?? seoulDay(_store.now),
          openMemo: _openMemo,
        ),
      ),
    );
  }

  void _editPlan(PlanItem? plan) =>
      showPlanEditSheet(context, _store, plan: plan);

  late final _nav = ShellNav(
    openMemo: _openMemo,
    openVoice: _openVoice,
    openSummary: _openSummary,
    editPlan: _editPlan,
    goTab: (tab) => setState(() => _tab = tab),
  );

  Widget _page() => switch (_tab) {
    AppShell.recordsTab => RecordsPage(store: _store, nav: _nav),
    AppShell.searchTab => SearchPage(store: _store, nav: _nav),
    AppShell.plansTab => PlansPage(
      store: _store,
      nav: _nav,
      notifier: widget.services.notifier,
    ),
    AppShell.settingsTab => SettingsPage(
      store: _store,
      services: widget.services,
      user: widget.user,
    ),
    _ => HomePage(store: _store, nav: _nav),
  };

  void _select(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // PC(넓은 화면): 이름이 붙은 사이드바, 그 위에 음성 기록·새 메모 버튼
    if (width >= 1100) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _Sidebar(
                tab: _tab,
                destinations: _destinations,
                onSelect: _select,
                onVoice: _openVoice,
                onText: () => _openMemo(null),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _page()),
            ],
          ),
        ),
      );
    }
    // 태블릿: 아이콘 레일, 맨 위에 음성 기록 버튼
    if (width >= 600) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: FloatingActionButton(
                    key: const Key('railVoice'),
                    tooltip: '음성 기록',
                    elevation: 0,
                    onPressed: _openVoice,
                    child: const Icon(Icons.mic_rounded),
                  ),
                ),
                destinations: [
                  for (final (icon, selected, label) in _destinations)
                    NavigationRailDestination(
                      icon: Icon(icon),
                      selectedIcon: Icon(selected),
                      label: Text(label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _page()),
            ],
          ),
        ),
      );
    }
    // 휴대폰: 아래 메뉴 + 오른쪽 아래 버튼.
    // 홈은 텍스트 메모(위, 작게)와 음성 기록(아래, 크게)을 세로로 쌓고,
    // 기록·검색·일정은 음성 기록만 둔다(설정에서는 숨김).
    return Scaffold(
      body: _page(),
      floatingActionButton: switch (_tab) {
        AppShell.settingsTab => null,
        AppShell.homeTab => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _TextFab(onPressed: () => _openMemo(null)),
            const SizedBox(height: 14),
            _VoiceFab(key: const Key('newVoiceMemo'), onPressed: _openVoice),
          ],
        ),
        _ => _VoiceFab(key: const Key('voiceFab'), onPressed: _openVoice),
      },
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.track)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _select,
          destinations: [
            for (final (icon, selected, label) in _destinations)
              NavigationDestination(
                key: Key('tab-$label'),
                icon: Icon(icon),
                selectedIcon: Icon(selected),
                label: label,
              ),
          ],
        ),
      ),
    );
  }
}

/// PC 사이드바: 워드마크, 음성 기록(주요 액션)·새 메모, 메뉴
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.tab,
    required this.destinations,
    required this.onSelect,
    required this.onVoice,
    required this.onText,
  });

  final int tab;
  final List<(IconData, IconData, String)> destinations;
  final ValueChanged<int> onSelect;
  final VoidCallback onVoice;
  final VoidCallback onText;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('sidebar'),
      width: 248,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 24),
            child: AppWordmark(logoSize: 34, fontSize: 21),
          ),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              key: const Key('sidebarVoice'),
              onPressed: onVoice,
              icon: const Icon(Icons.mic_rounded),
              label: const Text('음성 기록', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              key: const Key('sidebarText'),
              onPressed: onText,
              icon: const Icon(Icons.edit_outlined, size: 20),
              label: const Text('새 메모'),
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < destinations.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: i == tab ? AppColors.primaryLight : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: Key('side-${destinations[i].$3}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          i == tab ? destinations[i].$2 : destinations[i].$1,
                          color: i == tab
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          destinations[i].$3,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: i == tab
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: i == tab
                                ? AppColors.primary
                                : AppColors.textSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 음성 기록 버튼(크게): 진한 라벤더 원, 바깥에 피치→라벤더 그라데이션 테두리
class _VoiceFab extends StatelessWidget {
  const _VoiceFab({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: brandGradient,
        boxShadow: softShadow,
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surface,
        ),
        child: SizedBox.square(
          dimension: 60,
          child: FloatingActionButton(
            tooltip: '음성 기록',
            heroTag: 'voiceFab',
            elevation: 0,
            highlightElevation: 0,
            onPressed: onPressed,
            child: const Icon(Icons.mic_rounded, size: 30),
          ),
        ),
      ),
    );
  }
}

/// 텍스트 메모 버튼(작게, 보조): 흰 원, 피치 연필
class _TextFab extends StatelessWidget {
  const _TextFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 아래 큰 버튼과 가운데를 맞춘다.
      padding: const EdgeInsets.only(right: 11),
      child: SizedBox.square(
        dimension: 48,
        child: FloatingActionButton(
          key: const Key('newTextMemo'),
          tooltip: '텍스트 메모',
          heroTag: 'textFab',
          elevation: 2,
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.peachDeep,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.peach, width: 1.2),
          ),
          onPressed: onPressed,
          child: const Icon(Icons.edit_rounded, size: 22),
        ),
      ),
    );
  }
}
