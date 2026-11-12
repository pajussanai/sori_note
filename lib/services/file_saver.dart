import 'platform/file_saver_stub.dart'
    if (dart.library.js_interop) 'platform/file_saver_web.dart';

/// 글을 파일로 내려받는다. 웹이 아니면 false(부르는 쪽이 복사 등으로 대신한다).
bool saveTextFile(
  String fileName,
  String text, {
  String type = 'application/json',
}) => savePlatformTextFile(fileName, text, type);
