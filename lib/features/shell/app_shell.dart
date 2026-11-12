import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/reminder_scheduler.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/seoul_time.dart';
import '../../models/memo.dart';
import '../../models/plan_item.dart';
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
    (Icons.notes_rounded, Icons.notes_rounded, '기록'),
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

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                labelType: NavigationRailLabelType.all,
                backgroundColor: AppColors.background,
                indicatorColor: AppColors.primaryLight,
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
    return Scaffold(
      body: _page(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryLight,
        height: 64,
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
    );
  }
}
