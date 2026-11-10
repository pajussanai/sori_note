import 'package:flutter/foundation.dart';

import '../../core/errors.dart';
import '../../models/memo.dart';
import '../../services/memo_repository.dart';

/// 메모 목록 상태: 불러오기, 검색, 삭제, 편집 화면에서 저장한 결과 반영.
class MemosController extends ChangeNotifier {
  MemosController(this.repository);

  final MemoRepository repository;

  List<Memo> _memos = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String? _notice;
  bool _disposed = false;

  bool get loading => _loading;
  String? get error => _error;
  String get query => _query;
  bool get hasMemos => _memos.isNotEmpty;

  /// 화면 아래에 잠깐 보여 줄 안내. 보여 준 뒤 [clearNotice]로 지운다.
  String? get notice => _notice;

  /// 검색어가 들어간 메모만, 최근에 고친 순서로
  List<Memo> get memos {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _memos;
    return [
      for (final m in _memos)
        if (m.content.toLowerCase().contains(q)) m,
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    _notify();
    try {
      _memos = await repository.fetchMemos();
    } catch (e) {
      logError('메모 불러오기 실패', e);
      _error = describeError(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  void search(String query) {
    _query = query;
    _notify();
  }

  /// 편집 화면에서 저장된 메모를 목록 맨 위에 반영한다.
  void saved(Memo memo) {
    _memos = [
      memo,
      for (final m in _memos)
        if (m.id != memo.id) m,
    ];
    _notify();
  }

  /// 목록에서 먼저 지우고, 서버 삭제가 실패하면 되돌린다.
  Future<void> delete(String id) async {
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
    }
  }

  void clearNotice() => _notice = null;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
