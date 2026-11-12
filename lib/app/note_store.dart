import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../core/seoul_time.dart';
import '../models/daily_summary.dart';
import '../models/memo.dart';
import '../models/memo_label.dart';
import '../models/plan_item.dart';
import '../services/local_store.dart';
import '../services/memo_repository.dart';
import '../services/organizer.dart';

/// 검색 결과 한 건: 메모와 찾은 곳 주변의 미리보기
class SearchHit {
  const SearchHit(this.memo, this.preview);

  final Memo memo;
  final String preview;
}

/// 로그인한 사용자의 기록 전체 상태. 모든 화면(홈·기록·검색·일정·설정)이 함께 쓴다.
///
/// - 메모: 서버(memos 테이블)에서 필요한 만큼 불러온다(최근 100개씩).
/// - 분류·태그, 일정·할 일, 하루 요약: 이 기기에 저장한다(운영 DB를 바꾸지 않기 위해).
class NoteStore extends ChangeNotifier {
  NoteStore({
    required this.repository,
    required this.local,
    required this.organizer,
    required this.userId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final MemoRepository repository;
  final KeyValueStore local;
  final MemoOrganizer organizer;
  final String userId;
  final DateTime Function() _clock;

  DateTime get now => _clock();

  String get _labelsKey => 'sori:$userId:labels';
  String get _plansKey => 'sori:$userId:plans';
  String get _summariesKey => 'sori:$userId:summaries';

  List<Memo> _memos = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  String? _notice;
  bool _disposed = false;

  final _labels = <String, MemoLabel>{};
  List<PlanItem> _plans = [];
  final _summaries = <String, DailySummary>{};

  // ------------------------------------------------------------- 상태

  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;

  /// 최근에 고친 순서의 메모(불러온 범위)
  List<Memo> get memos => _memos;

  /// 화면 아래에 잠깐 보여 줄 안내. 보여 준 뒤 [clearNotice]로 지운다.
  String? get notice => _notice;
  void clearNotice() => _notice = null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ------------------------------------------------------------- 불러오기

  Future<void> load() async {
    _loading = true;
    _error = null;
    _notify();
    await _loadLocal();
    try {
      final page = await repository.fetchMemos();
      _memos = page;
      _hasMore = page.length >= MemoRepository.pageSize;
      _labelNew(page);
    } catch (e) {
      logError('메모 불러오기 실패', e);
      _error = describeError(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// 더 오래된 메모를 이어서 불러온다.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || _memos.isEmpty) return;
    _loadingMore = true;
    _notify();
    try {
      final page = await repository.fetchMemos(before: _memos.last.updatedAt);
      _hasMore = page.length >= MemoRepository.pageSize;
      _merge(page);
      _labelNew(page);
    } catch (e) {
      logError('메모 더 불러오기 실패', e);
      _notice = '메모를 더 불러오지 못했습니다. ${describeError(e)}';
    } finally {
      _loadingMore = false;
      _notify();
    }
  }

  Future<void> _loadLocal() async {
    try {
      final labels = await local.read(_labelsKey);
      _labels.clear();
      if (labels != null) {
        for (final j in jsonDecode(labels) as List) {
          final label = MemoLabel.fromJson(j as Map<String, dynamic>);
          _labels[label.memoId] = label;
        }
      }
      final plans = await local.read(_plansKey);
      _plans = plans == null
          ? []
          : [
              for (final j in jsonDecode(plans) as List)
                PlanItem.fromJson(j as Map<String, dynamic>),
            ];
      final summaries = await local.read(_summariesKey);
      _summaries.clear();
      if (summaries != null) {
        for (final j in jsonDecode(summaries) as List) {
          final s = DailySummary.fromJson(j as Map<String, dynamic>);
          _summaries[s.day] = s;
        }
      }
    } catch (e) {
      // 기기 저장소를 읽지 못해도 메모는 쓸 수 있어야 한다.
      logError('기기 저장 데이터 읽기 실패', e);
    }
  }

  Future<void> _persistLabels() => _write(
    _labelsKey,
    jsonEncode([for (final l in _labels.values) l.toJson()]),
  );
  Future<void> _persistPlans() =>
      _write(_plansKey, jsonEncode([for (final p in _plans) p.toJson()]));
  Future<void> _persistSummaries() => _write(
    _summariesKey,
    jsonEncode([for (final s in _summaries.values) s.toJson()]),
  );

  Future<void> _write(String key, String value) async {
    try {
      await local.write(key, value);
    } catch (e) {
      logError('기기 저장 실패', e);
      _notice = '이 기기에 저장하지 못했습니다. 브라우저 저장 공간을 확인해 주세요.';
      _notify();
    }
  }

  void _merge(Iterable<Memo> more) {
    final byId = {for (final m in _memos) m.id: m};
    for (final m in more) {
      byId[m.id] = m;
    }
    _memos = byId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Memo? memoById(String id) {
    for (final m in _memos) {
      if (m.id == id) return m;
    }
    return null;
  }

  // ------------------------------------------------------------- 메모 저장·삭제

  /// 메모를 만들거나 고친다. 내용이 실제로 바뀐 경우에만 다시 분류한다.
  Future<Memo> saveMemo(String? id, String content) async {
    final memo = id == null
        ? await repository.createMemo(content)
        : await repository.updateMemo(id, content);
    _merge([memo]);
    if (_relabel(memo)) unawaited(_persistLabels());
    _notify();
    return memo;
  }

  /// 목록에서 먼저 지우고, 서버 삭제가 실패하면 되돌린다.
  /// 분류는 지우고, 이 메모에서 등록한 일정은 남기되 연결만 끊는다.
  Future<void> deleteMemo(String id) async {
    final before = _memos;
    _memos = [
      for (final m in _memos)
        if (m.id != id) m,
    ];
    _notify();
    try {
      await repository.deleteMemo(id);
    } catch (e) {
      logError('메모 삭제 실패', e);
      _memos = before;
      _notice = '메모를 삭제하지 못했습니다. ${describeError(e)}';
      _notify();
      return;
    }
    if (_labels.remove(id) != null) await _persistLabels();
    if (_plans.any((p) => p.memoId == id)) {
      _plans = [
        for (final p in _plans)
          p.memoId == id ? p.copyWith(memoId: () => null) : p,
      ];
      await _persistPlans();
    }
    _notify();
  }

  // ------------------------------------------------------------- 분류·태그

  MemoLabel? labelOf(String memoId) => _labels[memoId];

  /// 아직 분류하지 않았거나 내용이 바뀐 메모만 분류한다(기기 안, 서버 호출 없음).
  void _labelNew(Iterable<Memo> memos) {
    var changed = false;
    for (final m in memos) {
      changed = _relabel(m) || changed;
    }
    if (changed) unawaited(_persistLabels());
  }

  /// 분류가 바뀌었으면 true. 사용자가 고친 분류·태그는 덮어쓰지 않는다.
  bool _relabel(Memo memo) {
    final hash = contentHash(memo.content);
    final existing = _labels[memo.id];
    if (existing != null && existing.contentHash == hash) return false;
    if (memo.content.trim().isEmpty && existing == null) return false;
    final s = organizer.classify(memo.content);
    _labels[memo.id] = MemoLabel(
      memoId: memo.id,
      category: existing?.categoryByUser ?? false
          ? existing!.category
          : s.category,
      tags: existing?.tagsByUser ?? false ? existing!.tags : s.tags,
      contentHash: hash,
      categoryByUser: existing?.categoryByUser ?? false,
      tagsByUser: existing?.tagsByUser ?? false,
    );
    return true;
  }

  /// 사용자가 분류를 고친다(이후 자동 분류가 덮어쓰지 않는다).
  Future<void> setCategory(String memoId, MemoCategory category) async {
    final memo = memoById(memoId);
    final current =
        _labels[memoId] ??
        MemoLabel(
          memoId: memoId,
          category: category,
          tags: const [],
          contentHash: memo == null ? '' : contentHash(memo.content),
        );
    _labels[memoId] = current.copyWith(
      category: category,
      categoryByUser: true,
    );
    _notify();
    await _persistLabels();
  }

  /// 사용자가 태그를 고친다(앞뒤 공백·# 제거, 중복 제거, 최대 8개).
  Future<void> setTags(String memoId, List<String> tags) async {
    final clean = <String>[];
    for (final t in tags) {
      final v = t.trim().replaceFirst(RegExp(r'^#+'), '').trim();
      if (v.isNotEmpty && v.length <= 20 && !clean.contains(v)) clean.add(v);
    }
    final memo = memoById(memoId);
    final current =
        _labels[memoId] ??
        MemoLabel(
          memoId: memoId,
          category: MemoCategory.other,
          tags: const [],
          contentHash: memo == null ? '' : contentHash(memo.content),
        );
    _labels[memoId] = current.copyWith(
      tags: clean.take(8).toList(),
      tagsByUser: true,
    );
    _notify();
    await _persistLabels();
  }

  /// 불러온 메모 중 [category]에 속한 것(null이면 전체)
  List<Memo> memosIn(MemoCategory? category) => category == null
      ? _memos
      : [
          for (final m in _memos)
            if (_labels[m.id]?.category == category) m,
        ];

  /// 분류별 메모 수(불러온 범위)
  Map<MemoCategory, int> get categoryCounts {
    final counts = <MemoCategory, int>{};
    for (final m in _memos) {
      final c = _labels[m.id]?.category;
      if (c != null) counts[c] = (counts[c] ?? 0) + 1;
    }
    return counts;
  }

  /// 자주 쓴 태그 순서
  List<String> get allTags {
    final counts = <String, int>{};
    for (final l in _labels.values) {
      for (final t in l.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  /// 태그가 겹치거나 같은 분류인 메모(최대 [max]개)
  List<Memo> relatedTo(Memo memo, {int max = 3}) {
    final label = _labels[memo.id];
    if (label == null) return [];
    final scored = <(Memo, int)>[];
    for (final m in _memos) {
      if (m.id == memo.id) continue;
      final other = _labels[m.id];
      if (other == null) continue;
      var score = other.tags.where(label.tags.contains).length * 2;
      if (score == 0) continue;
      if (other.category == label.category &&
          label.category != MemoCategory.other) {
        score += 1;
      }
      scored.add((m, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final s in scored.take(max)) s.$1];
  }

  // ------------------------------------------------------------- 검색

  /// 제목·본문(서버 검색)과 분류·태그(기기)를 함께 찾는다.
  Future<List<SearchHit>> search(
    String query, {
    MemoCategory? category,
    String? tag,
  }) async {
    final q = query.trim();
    if (q.isEmpty && category == null && tag == null) return [];
    final lower = q.toLowerCase();
    final found = <String, Memo>{};

    if (q.isNotEmpty) {
      for (final m in await repository.searchMemos(q)) {
        found[m.id] = m;
      }
      // 태그·분류 이름으로 찾은 메모
      final byLabel = [
        for (final l in _labels.values)
          if (l.tags.any((t) => t.toLowerCase().contains(lower)) ||
              l.category.label == q)
            l.memoId,
      ];
      await _collect(byLabel, found);
    } else {
      final ids = [
        for (final l in _labels.values)
          if ((tag == null || l.tags.contains(tag)) &&
              (category == null || l.category == category))
            l.memoId,
      ];
      await _collect(ids, found);
    }
    _merge(found.values);
    _labelNew(found.values);

    final hits = <SearchHit>[];
    for (final m in found.values) {
      final label = _labels[m.id];
      if (category != null && label?.category != category) continue;
      if (tag != null && !(label?.tags.contains(tag) ?? false)) continue;
      hits.add(SearchHit(m, _preview(m.content, lower)));
    }
    hits.sort((a, b) => b.memo.updatedAt.compareTo(a.memo.updatedAt));
    _notify();
    return hits;
  }

  /// 불러온 메모에 없으면 서버에서 가져온다.
  Future<void> _collect(List<String> ids, Map<String, Memo> into) async {
    final missing = <String>[];
    for (final id in ids) {
      final m = memoById(id);
      if (m != null) {
        into[id] = m;
      } else {
        missing.add(id);
      }
    }
    if (missing.isNotEmpty) {
      for (final m in await repository.fetchMemosByIds(missing)) {
        into[m.id] = m;
      }
    }
  }

  /// 찾은 낱말 주변 80자 정도를 보여 준다.
  static String _preview(String content, String lower) {
    final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = flat.length > 90 ? '${flat.substring(0, 90)}…' : flat;
    if (lower.isEmpty) return short;
    final index = flat.toLowerCase().indexOf(lower);
    if (index < 0) return short;
    final start = (index - 30).clamp(0, flat.length);
    final end = (index + lower.length + 50).clamp(0, flat.length);
    return '${start > 0 ? '…' : ''}${flat.substring(start, end)}${end < flat.length ? '…' : ''}';
  }

  // ------------------------------------------------------------- 일정·할 일

  List<PlanItem> get plans => _plans;

  /// 다가오는 일정(완료 전, 오늘 0시 이후, 가까운 순)
  List<PlanItem> get upcoming {
    final todayStart = seoulDayRange(seoulDay(now)).start;
    return [
      for (final p in _plans)
        if (!p.done && p.dueAt != null && !p.dueAt!.isBefore(todayStart)) p,
    ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  }

  /// 날짜를 넘긴 미완료 일정
  List<PlanItem> get overdue {
    final todayStart = seoulDayRange(seoulDay(now)).start;
    return [
      for (final p in _plans)
        if (!p.done && p.dueAt != null && p.dueAt!.isBefore(todayStart)) p,
    ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  }

  /// 날짜 없는 미완료 할 일(최근 순)
  List<PlanItem> get todos => [
    for (final p in _plans)
      if (!p.done && p.dueAt == null) p,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<PlanItem> get completed => [
    for (final p in _plans)
      if (p.done) p,
  ]..sort((a, b) => (b.dueAt ?? b.createdAt).compareTo(a.dueAt ?? a.createdAt));

  /// 등록할 수 없으면 이유를 돌려준다.
  String? validatePlan(PlanItem plan) {
    if (plan.title.trim().isEmpty) return '제목을 입력해 주세요.';
    final due = plan.dueAt;
    if (due == null || plan.done) return null;
    if (plan.allDay) {
      if (seoulDay(due).isBefore(seoulDay(now))) {
        return '이미 지난 날짜예요. 날짜를 확인해 주세요.';
      }
    } else if (!due.isAfter(now)) {
      return '이미 지난 시간이에요. 날짜와 시간을 확인해 주세요.';
    }
    return null;
  }

  /// 일정을 추가하거나 고친다. 알림 시각이 바뀌면 다시 알린다.
  Future<void> savePlan(PlanItem plan) async {
    final index = _plans.indexWhere((p) => p.id == plan.id);
    if (index < 0) {
      _plans = [..._plans, plan];
    } else {
      final old = _plans[index];
      final reset = old.remindAt != plan.remindAt
          ? plan.copyWith(notifiedAt: () => null)
          : plan;
      _plans = [..._plans]..[index] = reset;
    }
    _notify();
    await _persistPlans();
  }

  Future<void> deletePlan(String id) async {
    _plans = [
      for (final p in _plans)
        if (p.id != id) p,
    ];
    _notify();
    await _persistPlans();
  }

  Future<void> setDone(String id, bool done) async {
    _plans = [for (final p in _plans) p.id == id ? p.copyWith(done: done) : p];
    _notify();
    await _persistPlans();
  }

  Future<void> markNotified(String id, DateTime at) async {
    _plans = [
      for (final p in _plans) p.id == id ? p.copyWith(notifiedAt: () => at) : p,
    ];
    _notify();
    await _persistPlans();
  }

  /// 알림이 켜져 있고 아직 보내지 않은 일정(알림 시각 순)
  List<PlanItem> get pendingReminders => [
    for (final p in _plans)
      if (!p.done && p.remindAt != null && p.notifiedAt == null) p,
  ]..sort((a, b) => a.remindAt!.compareTo(b.remindAt!));

  /// 보낸 알림(최근 순)
  List<PlanItem> get sentReminders => [
    for (final p in _plans)
      if (p.notifiedAt != null) p,
  ]..sort((a, b) => b.notifiedAt!.compareTo(a.notifiedAt!));

  // ------------------------------------------------------------- 하루 요약

  DailySummary? summaryOf(DateTime seoulDate) => _summaries[dayKey(seoulDate)];

  /// 최근 날짜 먼저
  List<DailySummary> get summaries =>
      _summaries.values.toList()..sort((a, b) => b.day.compareTo(a.day));

  /// 그날(한국 날짜) 쓰거나 고친 메모
  Future<List<Memo>> memosOfDay(DateTime seoulDate) async {
    final range = seoulDayRange(seoulDate);
    final memos = await repository.fetchMemosBetween(range.start, range.end);
    _labelNew(memos);
    return memos;
  }

  /// 그날 메모로 요약을 만들어 저장한다. 메모가 없으면 만들지 않고 null.
  Future<DailySummary?> createSummary(DateTime seoulDate) async {
    final memos = await memosOfDay(seoulDate);
    if (memos.where((m) => m.content.trim().isNotEmpty).isEmpty) return null;
    final summary = DailySummary(
      day: dayKey(seoulDate),
      sections: organizer.summarize(memos, labelOf),
      memoCount: memos.length,
      createdAt: now.toUtc(),
    );
    _summaries[summary.day] = summary;
    _notify();
    await _persistSummaries();
    return summary;
  }

  Future<void> saveSummary(DailySummary summary) async {
    _summaries[summary.day] = summary;
    _notify();
    await _persistSummaries();
  }

  Future<void> deleteSummary(String day) async {
    _summaries.remove(day);
    _notify();
    await _persistSummaries();
  }

  // ------------------------------------------------------------- 데이터 관리

  /// 이 기기에 저장한 분류·일정·요약의 대략적인 크기(바이트)
  Future<int> localDataBytes() async {
    var total = 0;
    for (final key in [_labelsKey, _plansKey, _summariesKey]) {
      total += utf8.encode(await local.read(key) ?? '').length;
    }
    return total;
  }

  int get labelCount => _labels.length;
  int get summaryCount => _summaries.length;

  /// 모든 메모(서버)와 이 기기의 분류·일정·요약을 JSON으로 만든다.
  Future<String> exportJson({String? email}) async {
    final all = <Memo>[];
    DateTime? before;
    for (var i = 0; i < 100; i++) {
      final page = await repository.fetchMemos(limit: 500, before: before);
      all.addAll(page);
      if (page.length < 500) break;
      before = page.last.updatedAt;
    }
    final data = {
      'app': 'sori_note',
      'exportedAt': now.toUtc().toIso8601String(),
      'account': email,
      'memos': [
        for (final m in all)
          {
            'id': m.id,
            'content': m.content,
            'createdAt': m.createdAt.toUtc().toIso8601String(),
            'updatedAt': m.updatedAt.toUtc().toIso8601String(),
            if (_labels[m.id] case final l?)
              'label': {'category': l.category.label, 'tags': l.tags},
          },
      ],
      'plans': [for (final p in _plans) p.toJson()],
      'dailySummaries': [
        for (final s in summaries)
          {
            'day': s.day,
            for (final sec in SummarySection.values) sec.label: s.items(sec),
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 계정 삭제: 서버의 내 메모와 이 기기의 기록을 모두 지운다.
  Future<void> deleteEverything() async {
    await repository.deleteAllMemos();
    await clearLocal();
  }

  Future<void> clearLocal() async {
    for (final key in [_labelsKey, _plansKey, _summariesKey]) {
      try {
        await local.delete(key);
      } catch (_) {}
    }
    _labels.clear();
    _plans = [];
    _summaries.clear();
    _memos = [];
    _notify();
  }
}
