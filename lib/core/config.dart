import 'dart:convert';

/// Supabase 연결 정보. 빌드할 때 넣는다(코드에 기본값을 두지 않는다).
///
/// Flutter 웹에서는 여기 값이 브라우저로 내려가는 JavaScript에 포함된다.
/// 그래서 공개해도 되는 publishable 키만 쓴다. 데이터 보호는 로그인과
/// 테이블의 RLS 정책이 맡는다. Gemini 같은 AI 키는 Edge Function 비밀값으로만 둔다.
///
/// ```sh
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// ```
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

/// 연결 정보 없이 빌드했는지(이때 앱은 설정 안내 화면을 보여 준다)
bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

/// 클라이언트에 넣으면 안 되는 키(secret, service_role)가 설정됐는지 검사한다.
///
/// 이런 키는 RLS를 우회하므로, 실수로 들어가면 앱을 시작하지 않는다.
void checkSupabaseConfig({required String url, required String key}) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw StateError('Supabase URL이 올바르지 않습니다.');
  }
  if (key.isEmpty) {
    throw StateError('Supabase publishable 키가 설정되지 않았습니다.');
  }
  if (key.startsWith('sb_secret_')) {
    throw StateError('secret 키는 앱에 넣을 수 없습니다. publishable 키를 사용하세요.');
  }
  // 예전 형식(JWT) 키라면 role이 service_role인지 확인한다.
  final parts = key.split('.');
  if (parts.length == 3) {
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      if (jsonDecode(payload) case {'role': 'service_role'}) {
        throw StateError('service_role 키는 앱에 넣을 수 없습니다. publishable 키를 사용하세요.');
      }
    } on FormatException {
      // JWT 형식이 아니면 검사하지 않는다.
    }
  }
}
