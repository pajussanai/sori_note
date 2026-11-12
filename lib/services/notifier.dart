import 'platform/notifier_stub.dart'
    if (dart.library.js_interop) 'platform/notifier_web.dart';

enum NotifyPermission {
  granted,
  denied,

  /// 아직 묻지 않음
  prompt,

  /// 이 브라우저·기기는 알림을 지원하지 않음
  unsupported,
}

/// 기기 알림. 웹은 브라우저 알림(Notification API)으로, 소리노트가 열려 있을 때만 보낸다.
abstract class Notifier {
  NotifyPermission get permission;

  /// 알림 권한을 묻는다(버튼을 누를 때 불러야 한다).
  Future<NotifyPermission> request();

  void show(String title, String body);
}

Notifier createNotifier() => createPlatformNotifier();

/// 알림을 보내지 않는 대체(테스트·미지원 환경)
class SilentNotifier implements Notifier {
  SilentNotifier([this.permission = NotifyPermission.unsupported]);

  @override
  NotifyPermission permission;
  final shown = <String>[];

  @override
  Future<NotifyPermission> request() async => permission;

  @override
  void show(String title, String body) => shown.add('$title|$body');
}
