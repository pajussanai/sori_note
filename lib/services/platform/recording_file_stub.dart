import 'dart:typed_data';

/// 녹음기가 남긴 파일(웹: blob 주소, 앱: 파일 경로)을 읽는다.
Future<({Uint8List bytes, String? type})> readRecording(String location) =>
    throw UnsupportedError('이 환경에서는 녹음 파일을 읽을 수 없습니다.');
