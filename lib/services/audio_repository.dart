import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/memo_audio.dart';

/// 녹음 저장·재생·삭제가 실패한 이유
enum AudioErrorCode {
  /// 서버에 녹음 저장 기능(테이블·버킷)이 아직 없다
  notReady,

  /// 계정 보관 한도(100MB)를 넘는다
  quotaExceeded,

  /// 파일 하나 한도(20MB)를 넘는다
  tooLarge,

  /// 서버가 받지 않는 형식
  unsupportedFormat,

  /// 연결된 메모가 없다(이미 삭제됨)
  memoMissing,

  /// 네트워크 등 그 밖의 실패
  failed,
}

class AudioException implements Exception {
  const AudioException(this.code);

  final AudioErrorCode code;

  @override
  String toString() => 'AudioException(${code.name})';
}

/// 녹음 파일 저장소. 화면은 이 인터페이스만 쓴다(테스트에서 가짜로 바꾼다).
abstract class AudioRepository {
  /// 메모에 딸린 녹음(오래된 것 먼저)
  Future<List<MemoAudio>> fetchForMemo(String memoId);

  /// 녹음이 있는 메모 id. 서버 준비 전이면 빈 집합.
  Future<Set<String>> memoIdsWithAudio();

  /// 파일을 올리고 메모와 연결한다. 같은 녹음을 다시 보내도 중복으로 생기지 않는다.
  Future<MemoAudio> upload(PendingAudio audio);

  /// 재생용 주소(잠시만 유효한 서명된 주소)
  Future<String> playbackUrl(MemoAudio audio);

  Future<void> delete(MemoAudio audio);

  /// 메모를 지우기 전에 그 메모의 녹음 파일을 모두 지운다.
  Future<void> deleteAllForMemo(String memoId);

  Future<AudioUsage> usage();
}

/// Supabase Storage(비공개 버킷 memo-audio)와 memo_audio 테이블.
///
/// 파일은 `<user_id>/<memo_id>/<audio_id>.<확장자>`에 두고, 서버 정책(Storage RLS)이
/// 본인 폴더만 올리기·재생·삭제를 허용한다.
class SupabaseAudioRepository implements AudioRepository {
  SupabaseAudioRepository(this._client);

  final SupabaseClient _client;

  static const bucket = 'memo-audio';
  static const _columns =
      'id, memo_id, storage_path, mime_type, duration_ms, size_bytes, created_at';
  static const _timeout = Duration(seconds: 15);
  static const _uploadTimeout = Duration(minutes: 3);

  /// 재생 주소가 유효한 시간(초)
  static const _signedUrlSeconds = 600;

  StorageFileApi get _files => _client.storage.from(bucket);

  @override
  Future<List<MemoAudio>> fetchForMemo(String memoId) => _guard(() async {
    final rows = await _client
        .from('memo_audio')
        .select(_columns)
        .eq('memo_id', memoId)
        .order('created_at')
        .timeout(_timeout);
    return rows.map(MemoAudio.fromRow).toList();
  });

  @override
  Future<Set<String>> memoIdsWithAudio() async {
    try {
      final rows = await _guard(
        () => _client.from('memo_audio').select('memo_id').timeout(_timeout),
      );
      return {for (final r in rows) r['memo_id'] as String};
    } on AudioException catch (e) {
      if (e.code == AudioErrorCode.notReady) return {};
      rethrow;
    }
  }

  @override
  Future<MemoAudio> upload(PendingAudio audio) => _guard(() async {
    if (audio.bytes.length > AudioLimits.maxFileBytes) {
      throw const AudioException(AudioErrorCode.tooLarge);
    }
    if (!audioExtensions.containsKey(audio.mimeType)) {
      throw const AudioException(AudioErrorCode.unsupportedFormat);
    }
    final usage = await this.usage();
    if (usage.usedBytes + audio.bytes.length > usage.limitBytes) {
      // 이전 시도에서 이미 연결까지 끝났다면 한도와 상관없이 그 결과를 돌려준다.
      final existing = await _find(audio.id);
      if (existing != null) return existing;
      throw const AudioException(AudioErrorCode.quotaExceeded);
    }

    try {
      await _files
          .uploadBinary(
            audio.storagePath,
            audio.bytes,
            fileOptions: FileOptions(contentType: audio.mimeType),
          )
          .timeout(_uploadTimeout);
    } on StorageException catch (e) {
      // 이전 시도에서 파일은 올라갔지만 연결하지 못한 경우: 이어서 연결한다.
      if (!_alreadyExists(e)) rethrow;
    }

    try {
      final row = await _client
          .from('memo_audio')
          .insert({
            'id': audio.id,
            'memo_id': audio.memoId,
            'storage_path': audio.storagePath,
            'mime_type': audio.mimeType,
            'duration_ms': audio.duration.inMilliseconds,
            'size_bytes': audio.bytes.length,
          })
          .select(_columns)
          .single()
          .timeout(_timeout);
      return MemoAudio.fromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final existing = await _find(audio.id);
        if (existing != null) return existing;
      }
      rethrow;
    }
  });

  Future<MemoAudio?> _find(String id) async {
    final row = await _client
        .from('memo_audio')
        .select(_columns)
        .eq('id', id)
        .maybeSingle()
        .timeout(_timeout);
    return row == null ? null : MemoAudio.fromRow(row);
  }

  @override
  Future<String> playbackUrl(MemoAudio audio) => _guard(
    () => _files
        .createSignedUrl(audio.storagePath, _signedUrlSeconds)
        .timeout(_timeout),
  );

  @override
  Future<void> delete(MemoAudio audio) => _guard(() async {
    // 파일을 먼저 지운다. 정보만 남으면 다시 지울 수 있지만,
    // 파일만 남으면 보이지 않는 채로 용량을 차지하기 때문이다.
    await _files.remove([audio.storagePath]).timeout(_timeout);
    await _client
        .from('memo_audio')
        .delete()
        .eq('id', audio.id)
        .timeout(_timeout);
  });

  @override
  Future<void> deleteAllForMemo(String memoId) async {
    final List<MemoAudio> clips;
    try {
      clips = await fetchForMemo(memoId);
    } on AudioException catch (e) {
      if (e.code == AudioErrorCode.notReady) return; // 녹음 기능이 없으면 지울 것도 없다
      rethrow;
    }
    if (clips.isEmpty) return;
    await _guard(
      () => _files
          .remove([for (final c in clips) c.storagePath])
          .timeout(_timeout),
    );
    // 정보 행은 메모를 지우면 함께 지워진다(on delete cascade).
  }

  @override
  Future<AudioUsage> usage() => _guard(() async {
    final rows = await _client.rpc('my_audio_usage').timeout(_timeout);
    final row = (rows as List).first as Map<String, dynamic>;
    return AudioUsage(
      usedBytes: (row['used_bytes'] as num).toInt(),
      limitBytes: (row['limit_bytes'] as num).toInt(),
      fileCount: (row['file_count'] as num).toInt(),
    );
  });

  static bool _alreadyExists(StorageException e) =>
      e.statusCode == '409' ||
      e.message.toLowerCase().contains('already exists') ||
      e.message.toLowerCase().contains('duplicate');

  /// 서버 오류를 앱의 이유로 바꾼다. 네트워크 오류는 그대로 둔다(네트워크 안내).
  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on StorageException catch (e) {
      final message = e.message.toLowerCase();
      if (message.contains('bucket not found')) {
        throw const AudioException(AudioErrorCode.notReady);
      }
      if (e.statusCode == '413' || message.contains('maximum allowed size')) {
        throw const AudioException(AudioErrorCode.tooLarge);
      }
      if (e.statusCode == '415' || message.contains('mime type')) {
        throw const AudioException(AudioErrorCode.unsupportedFormat);
      }
      if (e.statusCode == '403' || message.contains('row-level security')) {
        // 본인 폴더만 허용하므로 정상 사용에서 거부되는 경우는 한도 초과다.
        throw const AudioException(AudioErrorCode.quotaExceeded);
      }
      throw const AudioException(AudioErrorCode.failed);
    } on PostgrestException catch (e) {
      throw AudioException(switch (e.code) {
        '42P01' ||
        'PGRST205' ||
        '42883' ||
        'PGRST202' => AudioErrorCode.notReady,
        '42501' => AudioErrorCode.quotaExceeded,
        '23503' => AudioErrorCode.memoMissing,
        '23514' => AudioErrorCode.unsupportedFormat,
        _ => AudioErrorCode.failed,
      });
    }
  }
}
