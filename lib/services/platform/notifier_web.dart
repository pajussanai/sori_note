import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../notifier.dart';

Notifier createPlatformNotifier() => _WebNotifier();

/// 브라우저 알림. iPhone은 홈 화면에 추가한 앱(iOS 16.4 이상)에서만 지원한다.
class _WebNotifier implements Notifier {
  bool get _supported => web.window.has('Notification');

  @override
  NotifyPermission get permission {
    if (!_supported) return NotifyPermission.unsupported;
    return switch (web.Notification.permission) {
      'granted' => NotifyPermission.granted,
      'denied' => NotifyPermission.denied,
      _ => NotifyPermission.prompt,
    };
  }

  @override
  Future<NotifyPermission> request() async {
    if (!_supported) return NotifyPermission.unsupported;
    try {
      await web.Notification.requestPermission().toDart;
    } catch (_) {}
    return permission;
  }

  @override
  void show(String title, String body) {
    if (permission != NotifyPermission.granted) return;
    try {
      web.Notification(
        title,
        web.NotificationOptions(body: body, icon: 'icons/Icon-192.png'),
      );
    } catch (_) {
      // 일부 모바일 브라우저는 페이지에서 직접 알림을 만들 수 없다.
    }
  }
}
