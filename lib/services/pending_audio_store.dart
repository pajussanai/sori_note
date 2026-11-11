import '../models/memo_audio.dart';
import 'platform/pending_audio_store_stub.dart'
    if (dart.library.js_interop) 'platform/pending_audio_store_web.dart'
    if (dart.library.io) 'platform/pending_audio_store_io.dart';

/// 서버에 올리지 못한 녹음을 기기에 보관한다. 앱을 다시 열어도 남아 있어
/// 나중에 다시 올릴 수 있다(웹: 브라우저 IndexedDB, 앱: 앱 전용 폴더).
abstract class PendingAudioStore {
  Future<void> put(PendingAudio audio);

  /// 이 사용자의 보관 중인 녹음(오래된 것 먼저)
  Future<List<PendingAudio>> list(String userId);

  Future<void> remove(String id);
}

/// 실행 환경에 맞는 보관소. 쓸 수 없으면(사생활 보호 모드 등) 메모리에만 둔다.
PendingAudioStore createPendingAudioStore() =>
    createPlatformPendingAudioStore();

/// 메모리에만 두는 보관소(앱을 닫으면 사라진다). 테스트와 대체용.
class MemoryPendingAudioStore implements PendingAudioStore {
  final _items = <String, PendingAudio>{};

  @override
  Future<void> put(PendingAudio audio) async => _items[audio.id] = audio;

  @override
  Future<List<PendingAudio>> list(String userId) async =>
      _items.values.where((a) => a.userId == userId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> remove(String id) async => _items.remove(id);
}

/// 기기 보관소가 실패하면 메모리 보관소로 넘어간다(녹음을 잃지 않도록).
class FallbackPendingAudioStore implements PendingAudioStore {
  FallbackPendingAudioStore(this._primary);

  final PendingAudioStore _primary;
  final _memory = MemoryPendingAudioStore();

  @override
  Future<void> put(PendingAudio audio) async {
    try {
      await _primary.put(audio);
    } catch (_) {
      await _memory.put(audio);
    }
  }

  @override
  Future<List<PendingAudio>> list(String userId) async {
    final stored = await _primary
        .list(userId)
        .catchError((_) => <PendingAudio>[]);
    final ids = {for (final a in stored) a.id};
    return [
      ...stored,
      for (final a in await _memory.list(userId))
        if (!ids.contains(a.id)) a,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> remove(String id) async {
    await _memory.remove(id);
    try {
      await _primary.remove(id);
    } catch (_) {}
  }
}
