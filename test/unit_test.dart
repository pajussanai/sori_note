import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sori_note/core/config.dart';
import 'package:sori_note/models/memo.dart';
import 'package:sori_note/services/speech_input.dart';

void main() {
  group('메모 제목과 미리보기', () {
    Memo m(String content) => Memo(
      id: 'x',
      content: content,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    test('첫 줄이 제목, 다음 줄들이 미리보기', () {
      final memo = m('\n  장보기  \n우유\n\n계란');
      expect(memo.title, '장보기');
      expect(memo.preview, '우유 계란');
    });

    test('비어 있으면 새 메모, 긴 제목은 40자에서 자른다', () {
      expect(m('   ').title, '새 메모');
      expect(m('가' * 50).title, '${'가' * 40}…');
      expect(m('한 줄').preview, isEmpty);
    });

    test('서버 행을 읽는다', () {
      final memo = Memo.fromRow({
        'id': 'a',
        'content': null,
        'created_at': '2026-11-10T01:02:03Z',
        'updated_at': '2026-11-10T01:05:03Z',
      });
      expect(memo.content, isEmpty);
      expect(memo.updatedAt, DateTime.utc(2026, 11, 10, 1, 5, 3));
    });
  });

  group('Supabase 설정', () {
    test('기본값은 소리노트 프로젝트(publishable 키)', () {
      expect(isSupabaseConfigured, isTrue);
      expect(supabaseUrl, 'https://aexzuuzsdlnnklqklauw.supabase.co');
      expect(supabasePublishableKey, startsWith('sb_publishable_'));
      expect(
        () =>
            checkSupabaseConfig(url: supabaseUrl, key: supabasePublishableKey),
        returnsNormally,
      );
    });

    test('publishable 키만 허용하고 secret·service_role 키는 거부', () {
      const url = 'https://example.supabase.co';
      expect(
        () => checkSupabaseConfig(url: url, key: 'sb_publishable_x'),
        returnsNormally,
      );
      expect(
        () => checkSupabaseConfig(url: url, key: 'sb_secret_x'),
        throwsStateError,
      );
      String jwt(Map<String, dynamic> payload) =>
          'eyJhbGciOiJIUzI1NiJ9.'
          '${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}'
          '.sig';
      expect(
        () => checkSupabaseConfig(url: url, key: jwt({'role': 'service_role'})),
        throwsStateError,
      );
      expect(
        () => checkSupabaseConfig(url: 'http://x.com', key: 'sb_publishable_x'),
        throwsStateError,
      );
    });
  });

  test('음성 인식 오류 코드를 이유로 바꾼다', () {
    expect(
      DeviceSpeechInput.reasonFor('not-allowed'),
      SpeechStopReason.permissionDenied,
    );
    expect(DeviceSpeechInput.reasonFor('no-speech'), SpeechStopReason.noMatch);
    expect(DeviceSpeechInput.reasonFor('network'), SpeechStopReason.error);
  });
}
