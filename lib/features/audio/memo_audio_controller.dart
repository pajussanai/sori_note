import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors.dart';
import '../../core/ids.dart';
import '../../models/memo_audio.dart';
import '../../services/audio_recorder.dart';
import '../../services/audio_repository.dart';
import '../../services/pending_audio_store.dart';

/// 아직 서버에 올리지 못한 녹음과 상태
class PendingClip {
  PendingClip(this.audio);

  final PendingAudio audio;
  bool uploading = false;
  String? error;
}

/// 메모 하나의 녹음 목록: 불러오기, 저장(올리기), 다시 올리기, 삭제.
///
/// 올리기 전에 먼저 기기 보관소에 넣어 두므로, 올리기가 실패하거나 앱을 닫아도
/// 녹음이 사라지지 않고 나중에 다시 올릴 수 있다.
class MemoAudioController extends ChangeNotifier {
  MemoAudioController({
    required this.repository,
    required this.pendingStore,
    required this.userId,
  });

  final AudioRepository repository;
  final PendingAudioStore pendingStore;
  final String userId;

  String? _memoId;
  List<MemoAudio> _clips = [];
  List<PendingClip> _pending = [];
  String? _loadError;
  bool _disposed = false;
  final _uploads = <Future<void>>{};

  List<MemoAudio> get clips => _clips;
  List<PendingClip> get pending => _pending;
  String? get loadError => _loadError;
  bool get isEmpty => _clips.isEmpty && _pending.isEmpty;
  bool get uploading => _pending.any((p) => p.uploading);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 메모의 녹음과 이 기기에 남은(올리지 못한) 녹음을 불러온다.
  Future<void> load(String memoId) async {
    _memoId = memoId;
    _loadError = null;
    try {
      _clips = await repository.fetchForMemo(memoId);
    } on AudioException catch (e) {
      // 서버에 녹음 기능이 없으면 녹음이 없는 것과 같다.
      if (e.code != AudioErrorCode.notReady) _loadError = describeError(e);
    } catch (e) {
      logError('녹음 불러오기 실패', e);
      _loadError = describeError(e);
    }
    try {
      final stored = await pendingStore.list(userId);
      final uploaded = {for (final c in _clips) c.id};
      _pending = [
        for (final a in stored)
          if (a.memoId == memoId && !uploaded.contains(a.id)) PendingClip(a),
      ];
      // 이미 올라간 것이 보관소에 남아 있으면 지운다.
      for (final a in stored) {
        if (uploaded.contains(a.id)) unawaited(pendingStore.remove(a.id));
      }
    } catch (e) {
      logError('보관 중인 녹음 확인 실패', e);
    }
    _notify();
  }

  /// 녹음을 메모에 저장한다: 기기 보관소에 넣고 서버에 올린다.
  Future<void> save(
    RecordedAudio recorded,
    Duration duration,
    String memoId,
  ) async {
    _memoId = memoId;
    final audio = PendingAudio(
      id: newUuid(),
      userId: userId,
      memoId: memoId,
      mimeType: recorded.mimeType,
      duration: duration,
      bytes: recorded.bytes,
      createdAt: DateTime.now().toUtc(),
    );
    final clip = PendingClip(audio);
    _pending = [..._pending, clip];
    _notify();
    try {
      await pendingStore.put(audio);
    } catch (e) {
      logError('녹음 임시 보관 실패', e); // 메모리에는 남아 있으므로 계속 올린다.
    }
    await _upload(clip);
  }

  Future<void> retry(PendingClip clip) => _upload(clip);

  Future<void> _upload(PendingClip clip) {
    if (clip.uploading) return Future.value();
    final future = () async {
      clip
        ..uploading = true
        ..error = null;
      _notify();
      try {
        final saved = await repository.upload(clip.audio);
        _pending = [
          for (final p in _pending)
            if (p != clip) p,
        ];
        _clips = [..._clips.where((c) => c.id != saved.id), saved];
        try {
          await pendingStore.remove(clip.audio.id);
        } catch (_) {}
      } catch (e) {
        logError('녹음 올리기 실패', e);
        clip.error = describeError(e);
      } finally {
        clip.uploading = false;
        _notify();
      }
    }();
    _uploads.add(future);
    return future.whenComplete(() => _uploads.remove(future));
  }

  /// 진행 중인 올리기가 끝날 때까지 기다린다(화면을 나가기 전).
  Future<void> waitForUploads() => Future.wait([..._uploads]);

  /// 올리지 못한 녹음을 버린다.
  Future<void> discard(PendingClip clip) async {
    _pending = [
      for (final p in _pending)
        if (p != clip) p,
    ];
    _notify();
    await pendingStore.remove(clip.audio.id);
  }

  /// 서버의 녹음을 지운다. 실패하면 오류를 던진다(화면에서 안내).
  Future<void> delete(MemoAudio clip) async {
    await repository.delete(clip);
    _clips = [
      for (final c in _clips)
        if (c.id != clip.id) c,
    ];
    _notify();
  }

  /// 메모를 지울 때: 이 메모의 보관 중인 녹음도 지운다.
  Future<void> forgetPending() async {
    for (final p in _pending) {
      await pendingStore.remove(p.audio.id);
    }
    _pending = [];
    _notify();
  }

  String? get memoId => _memoId;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
