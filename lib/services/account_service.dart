import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/seoul_time.dart';

/// 하루 AI 다듬기 사용량
class DailyUsage {
  const DailyUsage(this.day, this.count);

  final String day;
  final int count;
}

/// 계정 삭제 결과
enum AccountDeletion {
  /// 로그인 계정까지 지웠다.
  deleted,

  /// 서버에 계정 삭제 기능이 아직 없어 메모만 지웠다(로그인 계정은 남음).
  memosOnly,
}

/// 계정·사용량 관련 서버 기능
abstract class AccountService {
  /// 서버의 계정 삭제 함수(delete_my_account)를 부른다. 없으면 [AccountDeletion.memosOnly]를
  /// 돌려주며, 그때 메모 삭제는 부르는 쪽이 한다.
  Future<AccountDeletion> deleteAccount();

  /// 최근 [days]일의 AI 다듬기 사용량(한국 날짜, 최근 날짜 먼저)
  Future<List<DailyUsage>> polishUsage({int days = 7});
}

class SupabaseAccountService implements AccountService {
  SupabaseAccountService(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<AccountDeletion> deleteAccount() async {
    try {
      await _client.rpc('delete_my_account').timeout(_timeout);
      return AccountDeletion.deleted;
    } on PostgrestException catch (e) {
      // 함수가 없음(마이그레이션 20261112000000 미적용)
      if (e.code == 'PGRST202' || e.code == '42883') {
        return AccountDeletion.memosOnly;
      }
      rethrow;
    }
  }

  @override
  Future<List<DailyUsage>> polishUsage({int days = 7}) async {
    final from = seoulDay(DateTime.now()).subtract(Duration(days: days - 1));
    final rows = await _client
        .from('polish_usage_daily')
        .select('day, request_count')
        .gte('day', dayKey(from))
        .order('day', ascending: false)
        .timeout(_timeout);
    return [
      for (final r in rows)
        DailyUsage(r['day'] as String, (r['request_count'] as num).toInt()),
    ];
  }
}
