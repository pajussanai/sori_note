import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/memo_audio.dart';
import '../pending_audio_store.dart';

PendingAudioStore createPlatformPendingAudioStore() =>
    FallbackPendingAudioStore(_FilePendingAudioStore());

/// 앱 전용 폴더(pending_audio)에 `<id>.json`(정보)과 `<id>.bin`(소리)으로 보관한다.
class _FilePendingAudioStore implements PendingAudioStore {
  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/pending_audio').create(recursive: true);
  }

  @override
  Future<void> put(PendingAudio audio) async {
    final dir = await _dir();
    await File('${dir.path}/${audio.id}.bin')
        .writeAsBytes(audio.bytes, flush: true);
    await File('${dir.path}/${audio.id}.json')
        .writeAsString(jsonEncode(audio.toMeta()), flush: true);
  }

  @override
  Future<List<PendingAudio>> list(String userId) async {
    final dir = await _dir();
    final result = <PendingAudio>[];
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      try {
        final meta =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (meta['userId'] != userId) continue;
        final bytes = await File(
          file.path.replaceFirst(RegExp(r'\.json$'), '.bin'),
        ).readAsBytes();
        result.add(PendingAudio.fromMeta(meta, bytes));
      } catch (_) {
        // 깨진 항목은 건너뛴다.
      }
    }
    return result..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> remove(String id) async {
    final dir = await _dir();
    for (final ext in ['json', 'bin']) {
      final file = File('${dir.path}/$id.$ext');
      if (file.existsSync()) await file.delete();
    }
  }
}
