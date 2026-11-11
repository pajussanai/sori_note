import 'dart:typed_data';

/// 녹음 파일 한도. 서버(마이그레이션 20261111090000_memo_audio.sql)와 같은 값이다.
abstract final class AudioLimits {
  /// 한 번에 녹음할 수 있는 최대 시간.
  /// 브라우저가 비트레이트 설정을 따르지 않는 경우가 있어(Chrome AAC 실측 약 103kbps)
  /// 128kbps로 녹음돼도 파일 한도(20MB) 안에 들도록 20분으로 둔다.
  static const maxDuration = Duration(minutes: 20);

  /// 파일 하나의 최대 크기(버킷 file_size_limit)
  static const maxFileBytes = 20 * 1024 * 1024;

  /// 사용자 한 명이 보관할 수 있는 합계
  static const quotaBytes = 100 * 1024 * 1024;
}

/// 서버가 받는 녹음 형식과 파일 확장자
const audioExtensions = {
  'audio/mp4': 'm4a',
  'audio/aac': 'aac',
  'audio/webm': 'webm',
  'audio/ogg': 'ogg',
};

/// 'audio/webm; codecs=opus' 같은 값을 서버가 받는 형식으로 맞춘다. 모르면 null.
String? normalizeAudioType(String? type) {
  final base = type?.split(';').first.trim().toLowerCase() ?? '';
  if (base == 'audio/x-m4a' || base == 'video/mp4') return 'audio/mp4';
  if (base == 'video/webm') return 'audio/webm';
  return audioExtensions.containsKey(base) ? base : null;
}

/// 서버에 저장된 녹음 파일 정보(파일은 Storage 버킷 memo-audio에 있다).
class MemoAudio {
  const MemoAudio({
    required this.id,
    required this.memoId,
    required this.storagePath,
    required this.mimeType,
    required this.duration,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String memoId;
  final String storagePath;
  final String mimeType;
  final Duration duration;
  final int sizeBytes;
  final DateTime createdAt;

  factory MemoAudio.fromRow(Map<String, dynamic> row) => MemoAudio(
    id: row['id'] as String,
    memoId: row['memo_id'] as String,
    storagePath: row['storage_path'] as String,
    mimeType: row['mime_type'] as String,
    duration: Duration(milliseconds: (row['duration_ms'] as num).toInt()),
    sizeBytes: (row['size_bytes'] as num).toInt(),
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

/// 아직 서버에 올리지 못한 녹음. 올릴 때까지 기기에 보관한다.
class PendingAudio {
  const PendingAudio({
    required this.id,
    required this.userId,
    required this.memoId,
    required this.mimeType,
    required this.duration,
    required this.bytes,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String memoId;
  final String mimeType;
  final Duration duration;
  final Uint8List bytes;
  final DateTime createdAt;

  /// 저장 위치: `<user_id>/<memo_id>/<audio_id>.<확장자>` (서버 정책이 본인 폴더만 허용)
  String get storagePath =>
      '$userId/$memoId/$id.${audioExtensions[mimeType] ?? 'bin'}';

  Map<String, Object> toMeta() => {
    'id': id,
    'userId': userId,
    'memoId': memoId,
    'mimeType': mimeType,
    'durationMs': duration.inMilliseconds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PendingAudio.fromMeta(Map<String, dynamic> meta, Uint8List bytes) =>
      PendingAudio(
        id: meta['id'] as String,
        userId: meta['userId'] as String,
        memoId: meta['memoId'] as String,
        mimeType: meta['mimeType'] as String,
        duration: Duration(milliseconds: (meta['durationMs'] as num).toInt()),
        bytes: bytes,
        createdAt: DateTime.parse(meta['createdAt'] as String),
      );
}

/// 사용자의 녹음 보관 사용량
class AudioUsage {
  const AudioUsage({
    required this.usedBytes,
    required this.limitBytes,
    required this.fileCount,
  });

  final int usedBytes;
  final int limitBytes;
  final int fileCount;
}
