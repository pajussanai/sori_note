import 'dart:io';
import 'dart:typed_data';

/// 녹음 파일을 읽고 임시 파일은 지운다(소리는 서버 또는 보관소로 옮겨 둔다).
Future<({Uint8List bytes, String? type})> readRecording(String location) async {
  final file = File(location);
  final bytes = await file.readAsBytes();
  try {
    await file.delete();
  } catch (_) {}
  return (bytes: bytes, type: null);
}
