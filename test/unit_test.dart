import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sori_note/core/config.dart';
import 'package:sori_note/models/memo.dart';
import 'package:sori_note/services/speech_input.dart';
import 'package:sori_note/widgets/app_logo.dart';

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
      expect(supabaseUrl, 'https://tkbhtdkhipmsmfwfhhom.supabase.co');
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

  test('로고는 모든 아이콘 모양으로 그려진다', () async {
    for (final painter in const [
      SoriLogoPainter(),
      SoriLogoPainter(simple: true),
      SoriLogoPainter(background: LogoBackground.square, scale: 0.8),
      SoriLogoPainter(background: LogoBackground.none, scale: 0.62),
      SoriLogoPainter(
        background: LogoBackground.square,
        paintForeground: false,
      ),
    ]) {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size.square(96));
      final image = await recorder.endRecording().toImage(96, 96);
      final pixels = await image.toByteData();
      image.dispose();
      // 무언가 그려졌는지(완전히 투명하지 않은지) 확인한다.
      final bytes = pixels!.buffer.asUint8List();
      var opaque = 0;
      for (var i = 3; i < bytes.length; i += 4) {
        if (bytes[i] > 0) opaque++;
      }
      expect(opaque, greaterThan(500));
    }
  });

  test('음성 인식 오류 코드를 이유로 바꾼다', () {
    expect(
      DeviceSpeechInput.reasonFor('not-allowed'),
      SpeechStopReason.permissionDenied,
    );
    expect(
      DeviceSpeechInput.reasonFor('service-not-allowed'),
      SpeechStopReason.serviceBlocked,
    );
    expect(
      DeviceSpeechInput.reasonFor('not supported'),
      SpeechStopReason.unsupported,
    );
    expect(DeviceSpeechInput.reasonFor('no-speech'), SpeechStopReason.noMatch);
    expect(DeviceSpeechInput.reasonFor('network'), SpeechStopReason.error);
  });
}
