import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ids.dart';
import '../models/memo.dart';

/// 메모 저장소. 화면은 이 인터페이스만 쓴다(테스트에서 가짜로 바꾼다).
abstract class MemoRepository {
  /// 최근에 고친 메모가 먼저 오도록 정렬해서 돌려준다.
  Future<List<Memo>> fetchMemos();

  Future<Memo> createMemo(String content);

  Future<Memo> updateMemo(String id, String content);

  Future<void> deleteMemo(String id);
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

  @override
  Future<List<Memo>> fetchMemos() async {
    final rows = await _client
        .from('memos')
        .select(_columns)
        .order('updated_at', ascending: false)
        .timeout(_timeout);
    return rows.map(Memo.fromRow).toList();
  }

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
}
