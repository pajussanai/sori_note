import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../models/memo_audio.dart';
import '../../services/audio_player.dart';
import 'audio_recording.dart';
import 'memo_audio_controller.dart';

/// 녹음하는 동안 편집 화면 아래에 보이는 막대: 녹음 시간, 일시정지·재개, 취소, 저장.
class RecordingPanel extends StatelessWidget {
  const RecordingPanel({
    super.key,
    required this.recording,
    required this.onSave,
    required this.onCancel,
  });

  final AudioRecording recording;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final paused = recording.paused;
    final busy =
        recording.state == RecordingState.starting ||
        recording.state == RecordingState.stopping;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.fiber_manual_record_rounded,
              size: 14,
              color: paused ? AppColors.textMuted : AppColors.recording,
            ),
            const SizedBox(width: 6),
            Text(
              formatDuration(recording.elapsed),
              key: const Key('recordingTime'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                paused
                    ? '일시정지 · 원본 음성 녹음'
                    : '녹음 중 · 최대 ${AudioLimits.maxDuration.inMinutes}분',
                style: const TextStyle(fontSize: 13, color: AppColors.textSub),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton(
              key: const Key('recordCancel'),
              onPressed: busy ? null : onCancel,
              child: const Text('취소'),
            ),
            const Spacer(),
            IconButton.outlined(
              key: const Key('recordPause'),
              tooltip: paused ? '이어서 녹음' : '일시정지',
              iconSize: 26,
              constraints: const BoxConstraints.tightFor(width: 52, height: 52),
              onPressed: busy
                  ? null
                  : (paused ? recording.resume : recording.pause),
              icon: Icon(paused ? Icons.mic_rounded : Icons.pause_rounded),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const Key('recordSave'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                backgroundColor: AppColors.recording,
              ),
              onPressed: busy ? null : onSave,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.stop_rounded),
              label: const Text('끝내고 저장'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 편집 화면 위쪽의 녹음 목록: 재생·위치 이동·삭제, 올리지 못한 녹음 다시 올리기.
class MemoAudioSection extends StatelessWidget {
  const MemoAudioSection({
    super.key,
    required this.controller,
    required this.createPlayer,
  });

  final MemoAudioController controller;
  final AudioPlayback Function() createPlayer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final error = controller.loadError;
        if (controller.isEmpty && error == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null)
                Text(
                  '녹음을 불러오지 못했어요. $error',
                  style: const TextStyle(fontSize: 13, color: AppColors.danger),
                ),
              for (final clip in controller.clips)
                _ClipTile(
                  key: ValueKey('clip-${clip.id}'),
                  clip: clip,
                  controller: controller,
                  createPlayer: createPlayer,
                ),
              for (final pending in controller.pending)
                _PendingTile(
                  key: ValueKey('pending-${pending.audio.id}'),
                  clip: pending,
                  controller: controller,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TileFrame extends StatelessWidget {
  const _TileFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow,
      ),
      child: child,
    );
  }
}

/// 서버에 저장된 녹음 하나: 재생/일시정지, 위치 이동, 삭제
class _ClipTile extends StatefulWidget {
  const _ClipTile({
    super.key,
    required this.clip,
    required this.controller,
    required this.createPlayer,
  });

  final MemoAudio clip;
  final MemoAudioController controller;
  final AudioPlayback Function() createPlayer;

  @override
  State<_ClipTile> createState() => _ClipTileState();
}

class _ClipTileState extends State<_ClipTile> {
  AudioPlayback? _player;
  final _subs = <StreamSubscription<Object?>>[];
  late Duration _duration = widget.clip.duration;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  bool _deleting = false;

  /// 서명된 주소는 잠시만 유효하므로, 오래 지나면 다시 받는다.
  DateTime? _loadedAt;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<AudioPlayback?> _ready() async {
    final loadedAt = _loadedAt;
    if (_player != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(minutes: 8)) {
      return _player;
    }
    setState(() => _loading = true);
    try {
      final player = _player ?? widget.createPlayer();
      if (_player == null) {
        _player = player;
        _subs
          ..add(
            player.positionStream.listen((p) {
              if (mounted) setState(() => _position = p);
            }),
          )
          ..add(
            player.playingStream.listen((p) {
              if (mounted) setState(() => _playing = p);
            }),
          )
          ..add(
            player.completedStream.listen((_) async {
              await player.pause();
              await player.seek(Duration.zero);
            }),
          );
      }
      final url = await widget.controller.repository.playbackUrl(widget.clip);
      final duration = await player.load(url);
      _loadedAt = DateTime.now();
      if (duration != null && duration > Duration.zero) _duration = duration;
      if (_position > Duration.zero) await player.seek(_position);
      return player;
    } catch (e) {
      logError('녹음 재생 준비 실패', e);
      _showSnack('녹음을 재생하지 못했어요. ${describeError(e)}');
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player?.pause();
      return;
    }
    final player = await _ready();
    await player?.play();
  }

  Future<void> _seek(double ms) async {
    final target = Duration(milliseconds: ms.round());
    setState(() => _position = target);
    final player = await _ready();
    await player?.seek(target);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('녹음을 삭제할까요?'),
        content: const Text('녹음 파일이 서버에서 지워지며 되돌릴 수 없습니다. 메모 글은 그대로 남아요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    await _player?.pause();
    try {
      await widget.controller.delete(widget.clip);
    } catch (e) {
      logError('녹음 삭제 실패', e);
      _showSnack('녹음을 삭제하지 못했어요. ${describeError(e)}');
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds.toDouble();
    final value = _position.inMilliseconds.clamp(0, total).toDouble();
    return _TileFrame(
      child: Row(
        children: [
          IconButton(
            key: const Key('clipPlay'),
            tooltip: _playing ? '일시정지' : '재생',
            onPressed: _loading || _deleting ? null : _toggle,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: AppColors.primary,
                  ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                key: const Key('clipSeek'),
                value: total > 0 ? value : 0,
                max: total > 0 ? total : 1,
                onChanged: total > 0 && !_deleting
                    ? (v) => setState(
                        () => _position = Duration(milliseconds: v.round()),
                      )
                    : null,
                onChangeEnd: total > 0 && !_deleting ? _seek : null,
              ),
            ),
          ),
          Text(
            '${formatDuration(_position)} / ${formatDuration(_duration)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSub,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            key: const Key('clipDelete'),
            tooltip: '녹음 삭제',
            onPressed: _deleting ? null : _delete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.textSub,
            ),
          ),
        ],
      ),
    );
  }
}

/// 아직 올리지 못한 녹음: 올리는 중 / 실패(다시 시도·버리기)
class _PendingTile extends StatelessWidget {
  const _PendingTile({super.key, required this.clip, required this.controller});

  final PendingClip clip;
  final MemoAudioController controller;

  Future<void> _discard(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 녹음을 버릴까요?'),
        content: const Text('아직 서버에 올리지 못한 녹음입니다. 버리면 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('버리기'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.discard(clip);
  }

  @override
  Widget build(BuildContext context) {
    final error = clip.error;
    return _TileFrame(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(
              error == null
                  ? Icons.cloud_upload_outlined
                  : Icons.cloud_off_rounded,
              size: 20,
              color: error == null ? AppColors.primary : AppColors.danger,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                switch ((clip.uploading, error)) {
                  (true, _) =>
                    '녹음 ${formatDuration(clip.audio.duration)} · 저장하는 중…',
                  (false, null) =>
                    '녹음 ${formatDuration(clip.audio.duration)} · 아직 서버에 저장하지 않았어요',
                  (false, final e?) =>
                    '녹음 ${formatDuration(clip.audio.duration)} · 저장하지 못했어요\n$e',
                },
                key: const Key('pendingStatus'),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: error == null ? AppColors.textSub : AppColors.danger,
                ),
              ),
            ),
            if (clip.uploading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              TextButton(
                key: const Key('pendingRetry'),
                onPressed: () => controller.retry(clip),
                child: const Text('다시 시도'),
              ),
              IconButton(
                key: const Key('pendingDiscard'),
                tooltip: '녹음 버리기',
                onPressed: () => _discard(context),
                icon: const Icon(Icons.close_rounded, color: AppColors.textSub),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
