import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 녹음기가 만든 blob 주소에서 소리와 형식을 읽고 주소를 해제한다.
Future<({Uint8List bytes, String? type})> readRecording(String location) async {
  try {
    final response = await web.window.fetch(location.toJS).toDart;
    final blob = await response.blob().toDart;
    final buffer = await blob.arrayBuffer().toDart;
    return (bytes: buffer.toDart.asUint8List(), type: blob.type);
  } finally {
    web.URL.revokeObjectURL(location);
  }
}
