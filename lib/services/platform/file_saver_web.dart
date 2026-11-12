import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool savePlatformTextFile(String fileName, String text, String type) {
  final blob = web.Blob(
    [text.toJS].toJS,
    web.BlobPropertyBag(type: '$type;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  try {
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    web.document.body!.append(a);
    a.click();
    a.remove();
    return true;
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
