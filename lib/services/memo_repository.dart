import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ids.dart';
import '../models/memo.dart';

/// 메모 저장소. 화면은 이 인터페이스만 쓴다(테스트에서 가짜로 바꾼다).
abstract class MemoRepository {
  /// 한 번에 불러오는 메모 수
  static const pageSize = 100;

  /// 최근에 고친 메모부터 [limit]개. [before]가 있으면 그보다 먼저 고친 것만.
  Future<List<Memo>> fetchMemos({int limit = pageSize, DateTime? before});

  /// [start] 이상 [end] 미만에 쓰거나 고친 메모(하루 요약용)
  Future<List<Memo>> fetchMemosBetween(DateTime start, DateTime end);

  /// 내용에 [query]가 들어간 메모(최근 순, 최대 [limit]개)
  Future<List<Memo>> searchMemos(String query, {int limit = 50});

  Future<List<Memo>> fetchMemosByIds(Iterable<String> ids);

  Future<int> countMemos();

  Future<Memo> createMemo(String content);

  Future<Memo> updateMemo(String id, String content);

  Future<void> deleteMemo(String id);

  /// 내 메모를 모두 지운다(계정 삭제).
  Future<void> deleteAllMemos();
}

/// Supabase `memos` 테이블에 저장한다.
///
/// 사용자 구분은 로그인 세션과 RLS(auth.uid() = user_id)가 한다.
/// 앱은 user_id를 보내지 않는다(DB 기본값 auth.uid()가 쓰인다).
class SupabaseMemoRepository implements MemoRepository {
  SupabaseMemoRepository(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 15);
  static const _columns = 'id, content, created_at, updated_at';

  PostgrestFilterBuilder<List<Map<String, dynamic>>> get _select =>
      _client.from('memos').select(_columns);

  @override
  Future<List<Memo>> fetchMemos({
    int limit = MemoRepository.pageSize,
    DateTime? before,
  }) async {
    var query = _select;
    if (before != null) {
      query = query.lt('updated_at', before.toUtc().toIso8601String());
    }
    final rows = await query
        .order('updated_at', ascending: false)
        .limit(limit)
        .timeout(_timeout);
    return rows.map(Memo.fromRow).toList();
  }

  @override
  Future<List<Memo>> fetchMemosBetween(DateTime start, DateTime end) async {
    final a = start.toUtc().toIso8601String();
    final b = end.toUtc().toIso8601String();
    final rows = await _select
        .or(
          'and(created_at.gte.$a,created_at.lt.$b),'
          'and(updated_at.gte.$a,updated_at.lt.$b)',
        )
        .order('created_at')
        .limit(500)
        .timeout(_timeout);
    return rows.map(Memo.fromRow).toList();
  }

  @override
  Future<List<Memo>> searchMemos(String query, {int limit = 50}) async {
    // %, _, \는 그대로 찾도록 이스케이프한다.
    final escaped = query.replaceAllMapped(
      RegExp(r'[%_\\]'),
      (m) => '\\${m[0]}',
    );
    final rows = await _select
        .ilike('content', '%$escaped%')
        .order('updated_at', ascending: false)
        .limit(limit)
        .timeout(_timeout);
    return rows.map(Memo.fromRow).toList();
  }

  @override
  Future<List<Memo>> fetchMemosByIds(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return [];
    final rows = await _select
        .inFilter('id', list.take(200).toList())
        .order('updated_at', ascending: false)
        .timeout(_timeout);
    return rows.map(Memo.fromRow).toList();
  }

  @override
  Future<int> countMemos() =>
      _client.from('memos').count(CountOption.exact).timeout(_timeout);

  @override
  Future<Memo> createMemo(String content) async {
    // id를 앱이 정해 같은 요청을 다시 보내도 중복으로 생기지 않게 한다.
    final row = await _client
        .from('memos')
        .insert({'id': newUuid(), 'content': content})
        .select(_columns)
        .single()
        .timeout(_timeout);
    return Memo.fromRow(row);
  }

  @override
  Future<Memo> updateMemo(String id, String content) async {
    final row = await _client
        .from('memos')
        .update({'content': content})
        .eq('id', id)
        .select(_columns)
        .single()
        .timeout(_timeout);
    return Memo.fromRow(row);
  }

  @override
  Future<void> deleteMemo(String id) async {
    await _client.from('memos').delete().eq('id', id).timeout(_timeout);
  }

  @override
  Future<void> deleteAllMemos() async {
    // RLS가 본인 행만 지우게 한다. 조건 없는 삭제는 막혀 있어 항상 참인 조건을 쓴다.
    await _client
        .from('memos')
        .delete()
        .not('id', 'is', null)
        .timeout(const Duration(seconds: 30));
  }
}
