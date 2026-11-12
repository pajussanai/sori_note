import 'package:shared_preferences/shared_preferences.dart';

/// 이 기기에 글을 저장하는 곳(웹: 브라우저 localStorage, 앱: 기기 설정 저장소).
///
/// 분류·태그, 하루 요약, 일정은 운영 DB를 바꾸지 않기 위해 지금은 기기에 저장한다.
/// 같은 계정이라도 다른 기기에서는 보이지 않는다.
abstract class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class PrefsKeyValueStore implements KeyValueStore {
  final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> delete(String key) => _prefs.remove(key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
