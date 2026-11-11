import 'package:flutter/foundation.dart';

import '../../core/errors.dart';
import '../../models/memo.dart';
import '../../services/audio_repository.dart';
import '../../services/memo_repository.dart';
import '../../services/pending_audio_store.dart';

/// 메모 목록 상태: 불러오기, 검색, 삭제, 편집 화면에서 저장한 결과 반영.
/// 녹음 기능이 있으면 녹음이 있는 메모 표시·걸러 보기와 올리지 못한 녹음 다시 올리기도 한다.
class MemosController extends ChangeNotifier {
  MemosController(
    this.repository, {
    this.audio,
    this.pendingAudio,
    this.userId,
  });

  final MemoRepository repository;
  final AudioRepository? audio;
  final PendingAudioStore? pendingAudio;
  final String? userId;

  List<Memo> _memos = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String? _notice;
  bool _disposed = false;
  Set<String> _audioMemoIds = {};
  bool _audioOnly = false;
  int _pendingCount = 0;
  bool _retrying = false;

  bool get loading => _loading;
  String? get error => _error;
  String get query => _query;
  bool get hasMemos => _memos.isNotEmpty;

  /// 녹음이 있는 메모 id
  Set<String> get audioMemoIds => _audioMemoIds;

  /// '음성 기록'만 보기
  bool get audioOnly => _audioOnly;

  /// 이 기기에 남아 있는(서버에 올리지 못한) 녹음 수
  int get pendingCount => _pendingCount;
  bool get retrying => _retrying;

  /// 화면 아래에 잠깐 보여 줄 안내. 보여 준 뒤 [clearNotice]로 지운다.
  String? get notice => _notice;

  /// 검색어가 들어간 메모만, 최근에 고친 순서로
  List<Memo> get memos {
    final q = _query.trim().toLowerCase();
    return [
      for (final m in _memos)
        if ((q.isEmpty || m.content.toLowerCase().contains(q)) &&
            (!_audioOnly || _audioMemoIds.contains(m.id)))
          m,
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
    await refreshAudio();
  }

  /// 녹음이 있는 메모와 올리지 못한 녹음 수를 다시 확인한다(실패해도 목록은 그대로).
  Future<void> refreshAudio() async {
    final audio = this.audio;
    if (audio != null) {
      try {
        _audioMemoIds = await audio.memoIdsWithAudio();
      } catch (e) {
        logError('녹음 메모 확인 실패', e);
      }
    }
    final store = pendingAudio;
    final user = userId;
    if (store != null && user != null) {
      try {
        _pendingCount = (await store.list(user)).length;
      } catch (e) {
        logError('보관 중인 녹음 확인 실패', e);
      }
    }
    if (_audioOnly && _audioMemoIds.isEmpty) _audioOnly = false;
    _notify();
  }

  void search(String query) {
    _query = query;
    _notify();
  }

  void showAudioOnly(bool value) {
    _audioOnly = value;
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
  /// 녹음 파일이 있으면 메모보다 먼저 지운다(메모만 지우면 파일이 남는다).
  Future<void> delete(String id) async {
    final before = _memos;
    _memos = [
      for (final m in _memos)
        if (m.id != id) m,
    ];
    _notify();
    try {
      await audio?.deleteAllForMemo(id);
      await repository.deleteMemo(id);
      _audioMemoIds = {..._audioMemoIds}..remove(id);
      await _forgetPendingFor(id);
    } catch (e) {
      logError('메모 삭제 실패', e);
      _memos = before;
      _notice = '메모를 삭제하지 못했습니다. ${describeError(e)}';
      _notify();
    }
  }

  Future<void> _forgetPendingFor(String memoId) async {
    final store = pendingAudio;
    final user = userId;
    if (store == null || user == null) return;
    try {
      for (final p in await store.list(user)) {
        if (p.memoId == memoId) await store.remove(p.id);
      }
      _pendingCount = (await store.list(user)).length;
    } catch (_) {}
  }

  /// 이 기기에 남아 있는 녹음을 모두 다시 올린다.
  Future<void> retryPending() async {
    final audio = this.audio;
    final store = pendingAudio;
    final user = userId;
    if (audio == null || store == null || user == null || _retrying) return;
    _retrying = true;
    _notify();
    var failed = 0;
    Object? lastError;
    try {
      for (final pending in await store.list(user)) {
        try {
          await audio.upload(pending);
          await store.remove(pending.id);
        } on AudioException catch (e) {
          // 메모가 지워졌으면 붙일 곳이 없으므로 보관한 녹음도 정리한다.
          if (e.code == AudioErrorCode.memoMissing) {
            await store.remove(pending.id);
          } else {
            failed++;
            lastError = e;
          }
        } catch (e) {
          failed++;
          lastError = e;
        }
      }
    } finally {
      _retrying = false;
    }
    final error = lastError;
    _notice = failed == 0
        ? '녹음을 모두 저장했어요.'
        : '녹음 $failed개를 저장하지 못했어요. ${error == null ? '' : describeError(error)}';
    await refreshAudio();
  }

  void clearNotice() => _notice = null;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
