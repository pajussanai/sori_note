import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/seoul_time.dart';
import '../../models/daily_summary.dart';
import '../../models/memo.dart';
import '../../widgets/list_rows.dart';

/// 하루 정리: 날짜별 요약 보기·만들기·고치기·지우기. 메모가 없는 날은 만들지 않는다.
class DailySummaryPage extends StatefulWidget {
  const DailySummaryPage({
    super.key,
    required this.store,
    required this.initialDay,
    required this.openMemo,
  });

  final NoteStore store;

  /// 한국 날짜(0시, UTC 표시)
  final DateTime initialDay;
  final void Function(Memo memo) openMemo;

  @override
  State<DailySummaryPage> createState() => _DailySummaryPageState();
}

class _DailySummaryPageState extends State<DailySummaryPage> {
  late DateTime _day = widget.initialDay;
  List<Memo>? _memos;
  String? _error;
  bool _working = false;
  bool _editing = false;
  final _editors = <SummarySection, TextEditingController>{};

  NoteStore get _store => widget.store;
  DateTime get _today => seoulDay(_store.now);

  @override
  void initState() {
    super.initState();
    _loadMemos();
  }

  @override
  void dispose() {
    for (final c in _editors.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMemos() async {
    setState(() {
      _memos = null;
      _error = null;
    });
    final day = _day;
    try {
      final memos = await _store.memosOfDay(day);
      if (mounted && day == _day) setState(() => _memos = memos);
    } catch (e) {
      logError('하루 메모 불러오기 실패', e);
      if (mounted && day == _day) setState(() => _error = describeError(e));
    }
  }

  void _moveTo(DateTime day) {
    if (day.isAfter(_today)) return;
    setState(() {
      _day = day;
      _editing = false;
    });
    _loadMemos();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.utc(2020),
      lastDate: _today,
      helpText: '날짜 선택',
    );
    if (picked != null) {
      _moveTo(DateTime.utc(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _create() async {
    final existing = _store.summaryOf(_day);
    if (existing != null && existing.edited) {
      final ok = await _confirm(
        '요약을 다시 만들까요?',
        '직접 고친 내용은 새 요약으로 바뀝니다.',
        '다시 만들기',
      );
      if (!ok) return;
    }
    setState(() => _working = true);
    try {
      final summary = await _store.createSummary(_day);
      if (!mounted) return;
      if (summary == null) {
        _snack('이 날 쓴 메모가 없어 요약을 만들지 않았어요.');
      }
      await _loadMemos();
    } catch (e) {
      logError('하루 요약 만들기 실패', e);
      _snack('요약을 만들지 못했어요. ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _startEdit(DailySummary summary) {
    for (final s in SummarySection.values) {
      (_editors[s] ??= TextEditingController()).text = summary
          .items(s)
          .join('\n');
    }
    setState(() => _editing = true);
  }

  Future<void> _saveEdit(DailySummary summary) async {
    await _store.saveSummary(
      summary.copyWith(
        edited: true,
        sections: {
          for (final s in SummarySection.values)
            s: _editors[s]!.text
                .split('\n')
                .map((l) => l.trim().replaceFirst(RegExp(r'^[-·•]\s*'), ''))
                .where((l) => l.isNotEmpty)
                .toList(),
        },
      ),
    );
    if (mounted) setState(() => _editing = false);
  }

  Future<void> _delete(DailySummary summary) async {
    final ok = await _confirm('요약을 삭제할까요?', '메모는 지워지지 않아요.', '삭제');
    if (ok) await _store.deleteSummary(summary.day);
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('confirmAction'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('하루 정리')),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final summary = _store.summaryOf(_day);
          final memos = _memos;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _DayBar(
                        day: _day,
                        today: _today,
                        onPrev: () =>
                            _moveTo(_day.subtract(const Duration(days: 1))),
                        onNext: _day.isBefore(_today)
                            ? () => _moveTo(_day.add(const Duration(days: 1)))
                            : null,
                        onPick: _pickDay,
                      ),
                    ),
                  ),
                  if (_error != null)
                    EmptyHint('메모를 불러오지 못했어요. $_error')
                  else if (memos == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    if (summary == null)
                      _emptyState(memos)
                    else
                      _summaryView(summary),
                    if (memos.isNotEmpty) ...[
                      SectionHeader('이 날의 메모 ${memos.length}개'),
                      Padding(
                        padding: pagePadding,
                        child: MemoList(
                          memos: memos,
                          store: _store,
                          onOpen: widget.openMemo,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState(List<Memo> memos) {
    final count = memos.where((m) => m.content.trim().isNotEmpty).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            count == 0
                ? '이 날 쓴 메모가 없어 요약을 만들 수 없어요.'
                : '이 날 쓴 메모 $count개를 모아 주요 내용, 진행 상황, 결정 사항, 이슈, 할 일, 기억할 내용으로 정리해요.',
            key: const Key('summaryEmpty'),
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSub,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('summaryCreate'),
              onPressed: _working ? null : _create,
              icon: const Icon(Icons.summarize_outlined),
              label: Text(_working ? '정리하는 중…' : '요약 만들기'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryView(DailySummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '메모 ${summary.memoCount}개 요약${summary.edited ? ' · 직접 고침' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSub,
                  ),
                ),
              ),
              if (_editing) ...[
                TextButton(
                  onPressed: () => setState(() => _editing = false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  key: const Key('summarySave'),
                  onPressed: () => _saveEdit(summary),
                  child: const Text('저장'),
                ),
              ] else
                PopupMenuButton<String>(
                  key: const Key('summaryMenu'),
                  tooltip: '요약 메뉴',
                  onSelected: (v) => switch (v) {
                    'edit' => _startEdit(summary),
                    'regen' => _create(),
                    _ => _delete(summary),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      key: Key('summaryEdit'),
                      value: 'edit',
                      child: Text('고치기'),
                    ),
                    PopupMenuItem(value: 'regen', child: Text('다시 만들기')),
                    PopupMenuItem(
                      key: Key('summaryDelete'),
                      value: 'delete',
                      child: Text(
                        '삭제',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        for (final s in SummarySection.values)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _sectionColor(s),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_editing)
                    TextField(
                      key: Key('summaryField-${s.name}'),
                      controller: _editors[s],
                      maxLines: null,
                      minLines: 2,
                      decoration: appFieldDecoration(
                        fillColor: AppColors.background,
                        hintText: '한 줄에 하나씩',
                      ),
                    )
                  else if (summary.items(s).isEmpty)
                    const Text(
                      '없음',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    )
                  else
                    for (final item in summary.items(s))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '· $item',
                          style: const TextStyle(fontSize: 15, height: 1.55),
                        ),
                      ),
                ],
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Text(
            '요약은 이 기기 안에서 메모의 낱말을 바탕으로 정리해요. 메모 내용을 외부로 보내지 않아요.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.day,
    required this.today,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  final DateTime day;
  final DateTime today;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final relative = relativeSeoulDate(day, today: today);
    final full = formatSeoulDate(day, today: today);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('prevDay'),
            tooltip: '이전 날',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: TextButton(
              key: const Key('pickDay'),
              onPressed: onPick,
              child: Text(
                relative == full ? full : '$full · $relative',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('nextDay'),
            tooltip: '다음 날',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

/// 섹션마다 보조 색을 달리해 구분한다(피치·라벤더 중심).
Color _sectionColor(SummarySection s) => switch (s) {
  SummarySection.highlights => AppColors.lavender,
  SummarySection.progress => AppColors.peach,
  SummarySection.decisions => AppColors.primary,
  SummarySection.issues => AppColors.pink,
  SummarySection.todos => AppColors.mint,
  SummarySection.remember => AppColors.peachDeep,
};
