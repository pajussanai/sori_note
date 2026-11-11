import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../../models/memo_audio.dart';
import '../pending_audio_store.dart';

PendingAudioStore createPlatformPendingAudioStore() =>
    FallbackPendingAudioStore(_IndexedDbPendingAudioStore());

/// 브라우저 IndexedDB(sori_note / pending_audio)에 보관한다.
/// 이 브라우저에만 남고 서버나 다른 기기로는 가지 않는다.
class _IndexedDbPendingAudioStore implements PendingAudioStore {
  static const _dbName = 'sori_note';
  static const _storeName = 'pending_audio';

  Future<web.IDBDatabase>? _db;

  Future<web.IDBDatabase> _open() => _db ??= () {
    final done = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = (web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(
          _storeName,
          web.IDBObjectStoreParameters(keyPath: 'id'.toJS),
        );
      }
    }.toJS;
    request.onsuccess = (web.Event _) {
      done.complete(request.result as web.IDBDatabase);
    }.toJS;
    request.onerror = (web.Event _) {
      _db = null;
      done.completeError(StateError('IndexedDB를 열 수 없습니다.'));
    }.toJS;
    return done.future;
  }();

  Future<JSAny?> _run(
    String mode,
    web.IDBRequest Function(web.IDBObjectStore store) action,
  ) async {
    final db = await _open();
    final tx = db.transaction(_storeName.toJS, mode);
    final request = action(tx.objectStore(_storeName));
    final done = Completer<JSAny?>();
    tx.oncomplete = (web.Event _) {
      if (!done.isCompleted) done.complete(request.result);
    }.toJS;
    tx.onerror = (web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB 오류'));
    }.toJS;
    tx.onabort = (web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB 중단'));
    }.toJS;
    return done.future;
  }

  @override
  Future<void> put(PendingAudio audio) async {
    final record = JSObject()
      ..['id'] = audio.id.toJS
      ..['meta'] = jsonEncode(audio.toMeta()).toJS
      ..['bytes'] = audio.bytes.toJS;
    await _run('readwrite', (store) => store.put(record));
  }

  @override
  Future<List<PendingAudio>> list(String userId) async {
    final result = await _run('readonly', (store) => store.getAll());
    final items = <PendingAudio>[];
    for (final record in (result as JSArray<JSObject>).toDart) {
      try {
        final meta = jsonDecode(
          (record['meta'] as JSString).toDart,
        ) as Map<String, dynamic>;
        if (meta['userId'] != userId) continue;
        final bytes = (record['bytes'] as JSUint8Array).toDart;
        items.add(PendingAudio.fromMeta(meta, bytes));
      } catch (_) {
        // 깨진 항목은 건너뛴다.
      }
    }
    return items..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> remove(String id) =>
      _run('readwrite', (store) => store.delete(id.toJS));
}
