import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 설정 값 저장소(이 기기에 저장). 테스트에서는 메모리 저장소를 쓴다.
abstract class SettingsStore {
  Future<bool?> getBool(String key);

  Future<void> setBool(String key, bool value);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  final _prefs = SharedPreferencesAsync();

  @override
  Future<bool?> getBool(String key) => _prefs.getBool(key);

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
}

class MemorySettingsStore implements SettingsStore {
  final values = <String, bool>{};

  @override
  Future<bool?> getBool(String key) async => values[key];

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
}

/// 앱 설정. 바뀌면 화면에 알린다.
class AppSettings extends ChangeNotifier {
  AppSettings(this._store);

  final SettingsStore _store;

  static const _saveAudioKey = 'save_original_audio';

  bool _saveOriginalAudio = false;

  /// 원본 음성(녹음 파일) 저장. 기본은 꺼짐이고, 켜야 녹음 버튼이 보인다.
  bool get saveOriginalAudio => _saveOriginalAudio;

  Future<void> load() async {
    try {
      _saveOriginalAudio = await _store.getBool(_saveAudioKey) ?? false;
    } catch (_) {
      _saveOriginalAudio = false;
    }
    notifyListeners();
  }

  Future<void> setSaveOriginalAudio(bool value) async {
    _saveOriginalAudio = value;
    notifyListeners();
    try {
      await _store.setBool(_saveAudioKey, value);
    } catch (_) {
      // 저장하지 못해도 이번 실행 동안은 설정대로 동작한다.
    }
  }
}
