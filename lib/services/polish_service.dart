import 'package:supabase_flutter/supabase_flutter.dart';

/// AI 문장 다듬기. 원문은 바꾸지 않고 다듬은 글만 돌려준다.
abstract class PolishService {
  Future<String> polish(String text);
}

/// 다듬기 서버(Edge Function `polish`)가 알려 준 오류. 서버 원문은 담지 않는다.
class PolishException implements Exception {
  const PolishException(this.code, {this.status});

  final String code;
  final int? status;

  @override
  String toString() =>
      'PolishException($code${status == null ? '' : ', $status'})';
}

/// Edge Function `polish`를 호출한다. Gemini 키는 서버에만 있다.
class SupabasePolishService implements PolishService {
  SupabasePolishService(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 45);

  @override
  Future<String> polish(String text) async {
    final Object? data;
    try {
      final response = await _client.functions
          .invoke('polish', body: {'text': text})
          .timeout(_timeout);
      data = response.data;
    } on FunctionsFetchException {
      rethrow; // 네트워크 오류는 그대로(네트워크 안내 문구)
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map && details['code'] is String
          ? details['code'] as String
          : (e.status == 401 ? 'unauthorized' : 'http_${e.status}');
      throw PolishException(code, status: e.status);
    }
    if (data is Map && data['text'] is String) return data['text'] as String;
    throw const PolishException('bad_response');
  }
}
