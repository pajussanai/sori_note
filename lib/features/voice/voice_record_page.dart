import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../models/memo.dart';
import '../../services/polish_service.dart';
import '../../services/speech_input.dart';
import '../memos/memo_editor_page.dart';
import '../memos/polish_sheet.dart';
import 'voice_session.dart';

/// 음성 기록: 녹음 시작 → 일시정지·재개 → 종료 → 글자 확인·고치기 → AI 다듬기 → 메모 저장.
///
/// 말은 기기(브라우저) 음성 인식이 바로 글자로 바꾼다. 소리 파일은 만들지 않고 서버에 보내지 않는다.
/// 음성 인식을 쓸 수 없으면 바로 글자로 입력할 수 있다. 저장하면 만든 메모를 돌려준다.
class VoiceRecordPage extends StatefulWidget {
  const VoiceRecordPage({
    super.key,
    required this.store,
    required this.polishService,
    required this.speechInput,
    this.autoStart = true,
  });

  final NoteStore store;
  final PolishService polishService;
  final SpeechInput speechInput;

  /// 화면을 열자마자 녹음을 시작한다.
  final bool autoStart;

  @override
  State<VoiceRecordPage> createState() => _VoiceRecordPageState();
}

class _VoiceRecordPageState extends State<VoiceRecordPage> {
  late final _session = VoiceSession(widget.speechInput);
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _saving = false;

  /// 결과를 고치는 단계(녹음이 끝났거나 실패해 직접 입력)
  bool get _editing =>
      _session.state == VoiceState.finished ||
      _session.state == VoiceState.failed;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _session.start());
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _session.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  VoiceState? _lastState;

  void _onSession() {
    final state = _session.state;
    if (state != _lastState) {
      // 고치는 단계가 되면 들은 글을 입력창에 넣는다.
      if ((state == VoiceState.finished || state == VoiceState.failed) &&
          _text.text != _session.transcript) {
        _text.text = _session.transcript;
      }
      _lastState = state;
    }
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    await _session.finish();
    if (_text.text.trim().isEmpty) _focus.requestFocus();
  }

  Future<void> _retry() async {
    _session.setText(_text.text);
    await _session.retry();
  }

  Future<void> _polish() async {
    final original = _text.text;
    if (original.trim().isEmpty) {
      _snack('다듬을 내용이 없어요.');
      return;
    }
    final improved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => PolishSheet(
        original: original,
        polish: () => widget.polishService.polish(original),
      ),
    );
    if (improved == null || !mounted || improved == original) return;
    _text.text = improved;
    _snack(
      '다듬은 글로 바꿨어요.',
      action: SnackBarAction(
        label: '되돌리기',
        onPressed: () => _text.text = original,
      ),
    );
  }

  Future<void> _save() async {
    final content = _text.text.trim();
    if (content.isEmpty) {
      _snack('저장할 내용이 없어요. 말하거나 입력해 주세요.');
      return;
    }
    if (content.length > MemoEditorPage.maxLength) {
      _snack('메모가 너무 길어요(최대 20,000자).');
      return;
    }
    setState(() => _saving = true);
    try {
      final Memo memo = await widget.store.saveMemo(null, content);
      if (!mounted) return;
      // 저장 후 돌아간 화면을 이전 안내(AI 다듬기 등)가 가리지 않게 지운다.
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      Navigator.of(context).pop(memo);
    } catch (e) {
      logError('음성 기록 저장 실패', e);
      _snack('저장하지 못했어요. ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 나가기: 들은 글이 있으면 버릴지 묻는다.
  Future<void> _leave() async {
    final hasText =
        _session.transcript.trim().isNotEmpty || _text.text.trim().isNotEmpty;
    if (hasText) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('기록을 저장하지 않고 나갈까요?'),
          content: const Text('글자로 바꾼 내용이 사라집니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('계속 쓰기'),
            ),
            FilledButton(
              key: const Key('voiceDiscard'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('나가기'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    await _session.finish();
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: action,
          // 아래 버튼 막대를 가리지 않도록 그 위에 띄운다.
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = _session.state;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('voiceBack'),
            tooltip: '취소',
            icon: const Icon(Icons.close_rounded),
            onPressed: _leave,
          ),
          title: const Text('음성 기록'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  _StatusBar(session: _session),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(cardRadius),
                        border: Border.all(
                          color: _editing ? AppColors.mint : AppColors.track,
                        ),
                      ),
                      child: _editing
                          ? TextField(
                              key: const Key('voiceText'),
                              controller: _text,
                              focusNode: _focus,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              keyboardType: TextInputType.multiline,
                              style: const TextStyle(
                                fontSize: 17,
                                height: 1.65,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: '여기에 내용을 입력하거나 고치세요. 첫 줄은 제목이 돼요.',
                                hintStyle: TextStyle(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            )
                          : _LiveTranscript(session: _session),
                    ),
                  ),
                  _Controls(
                    state: state,
                    saving: _saving,
                    onStart: _session.start,
                    onPause: _session.pause,
                    onResume: _session.resume,
                    onStop: _finish,
                    onRetry: _retry,
                    onPolish: _polish,
                    onSave: _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 녹음 상태 표시: 녹음 중(빨강)·일시정지(호박색)·완료(딥 틸)·직접 입력(회색).
/// 듣는 동안에는 큰 원과 시간을, 글을 고치는 단계에서는 한 줄로 줄여 보여 준다.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.session});

  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    final state = session.state;
    final message = session.message;
    final (label, color, icon) = switch (state) {
      VoiceState.ready => ('녹음 준비', AppColors.primary, Icons.mic_none_rounded),
      VoiceState.starting => (
        '마이크 준비 중',
        AppColors.accent,
        Icons.mic_none_rounded,
      ),
      VoiceState.listening => (
        '녹음 중 · 말하는 내용을 글자로 바꾸고 있어요',
        AppColors.recording,
        Icons.mic_rounded,
      ),
      VoiceState.paused => ('일시정지', AppColors.paused, Icons.pause_rounded),
      VoiceState.finished => ('변환 완료', AppColors.done, Icons.check_rounded),
      VoiceState.failed => ('직접 입력', AppColors.textSub, Icons.keyboard_rounded),
    };
    final elapsed = session.elapsed;
    final time =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
        '${elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    final big = state != VoiceState.finished && state != VoiceState.failed;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              key: const Key('voiceState'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
    final timeText = Text(
      time,
      key: const Key('voiceTime'),
      style: TextStyle(
        fontSize: big ? 34 : 20,
        fontWeight: FontWeight.w800,
        color: AppColors.textMain,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, big ? 12 : 4, 20, 8),
      child: Column(
        crossAxisAlignment: big
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (big) ...[
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(
                  color: color.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: Center(
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: color,
                  child: Icon(icon, size: 34, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 14),
            timeText,
            const SizedBox(height: 10),
            _Waveform(
              active: state == VoiceState.listening,
              tick: elapsed.inMilliseconds ~/ 500,
            ),
            const SizedBox(height: 10),
            pill,
          ] else
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: color,
                  child: Icon(icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                timeText,
                const SizedBox(width: 10),
                Flexible(child: pill),
              ],
            ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                message,
                key: const Key('voiceMessage'),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: session.messageIsError
                      ? AppColors.danger
                      : AppColors.textSub,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 듣는 동안 보이는 글(확정된 글은 진하게, 듣는 중인 글은 흐리게)
class _LiveTranscript extends StatelessWidget {
  const _LiveTranscript({required this.session});

  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    final committed = session.committed;
    final partial = session.partial;
    if (committed.isEmpty && partial.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Text(
          '말하면 여기에 글자로 나타나요.\n잠깐 멈춰도 계속 들어요. 다 말했으면 종료를 눌러 주세요.',
          style: TextStyle(
            fontSize: 16,
            height: 1.6,
            color: AppColors.textMuted,
          ),
        ),
      );
    }
    // 짧을 때는 위에서부터, 길어지면 마지막 줄이 보이도록 아래로 붙여 스크롤한다.
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        reverse: true,
        child: SizedBox(
          width: double.infinity,
          child: Text.rich(
            key: const Key('voiceLive'),
            TextSpan(
              children: [
                TextSpan(text: committed),
                if (partial.isNotEmpty)
                  TextSpan(
                    text: committed.isEmpty ? partial : ' $partial',
                    style: const TextStyle(color: AppColors.textSub),
                  ),
              ],
            ),
            style: const TextStyle(
              fontSize: 17,
              height: 1.65,
              color: AppColors.textMain,
            ),
          ),
        ),
      ),
    );
  }
}

/// 아래 버튼: 상태에 따라 시작 / 일시정지·종료 / 재개·종료 / 다시 시도·AI 다듬기·저장
class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.saving,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onRetry,
    required this.onPolish,
    required this.onSave,
  });

  final VoiceState state;
  final bool saving;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onRetry;
  final VoidCallback onPolish;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final children = switch (state) {
      VoiceState.ready || VoiceState.starting => [
        Expanded(
          child: _BigButton(
            key: const Key('voiceStart'),
            icon: Icons.mic_rounded,
            label: state == VoiceState.starting ? '준비 중…' : '녹음 시작',
            onPressed: state == VoiceState.starting ? null : onStart,
          ),
        ),
      ],
      VoiceState.listening || VoiceState.paused => [
        Expanded(
          child: OutlinedButton.icon(
            key: Key(state == VoiceState.paused ? 'voiceResume' : 'voicePause'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 54)),
            onPressed: state == VoiceState.paused ? onResume : onPause,
            icon: Icon(
              state == VoiceState.paused
                  ? Icons.mic_rounded
                  : Icons.pause_rounded,
            ),
            label: Text(state == VoiceState.paused ? '재개' : '일시정지'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BigButton(
            key: const Key('voiceStop'),
            icon: Icons.stop_rounded,
            label: '종료',
            color: AppColors.recording,
            onPressed: onStop,
          ),
        ),
      ],
      VoiceState.finished || VoiceState.failed => [
        if (state == VoiceState.failed) ...[
          IconButton.outlined(
            key: const Key('voiceRetry'),
            tooltip: '다시 녹음',
            constraints: const BoxConstraints.tightFor(width: 54, height: 54),
            onPressed: onRetry,
            icon: const Icon(Icons.mic_rounded),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: AiPolishButton(
            key: const Key('voicePolish'),
            height: 54,
            onPressed: saving ? null : onPolish,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BigButton(
            key: const Key('voiceSave'),
            icon: Icons.check_rounded,
            label: saving ? '저장 중…' : '메모 저장',
            onPressed: saving ? null : onSave,
          ),
        ),
      ],
    };
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.track)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(children: children),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        backgroundColor: color,
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontSize: 16)),
    );
  }
}

/// 녹음 진행 표시 파형(피치·라벤더 막대). 실제 음량이 아니라 녹음 중임을 보여 주는 표시다.
/// 따로 애니메이션 타이머를 돌리지 않고, 녹음 시간 갱신(0.5초)마다 막대 높이를 부드럽게 바꾼다.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.active, required this.tick});

  final bool active;
  final int tick;

  static const _count = 21;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('voiceWave'),
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _count; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              width: 4,
              height: active ? _height(i) : 6,
              decoration: BoxDecoration(
                color: (i.isEven ? AppColors.peach : AppColors.lavender)
                    .withValues(alpha: active ? 1 : 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 가운데가 높고 가장자리가 낮은 모양에, 시간에 따라 조금씩 다른 높이를 더한다.
  double _height(int i) {
    final center = (_count - 1) / 2;
    final envelope = 1 - ((i - center).abs() / center) * 0.6;
    final wobble = ((i * 7 + tick * 5) % 11) / 10; // 0.0 ~ 1.0
    return 8 + 30 * envelope * (0.35 + 0.65 * wobble);
  }
}
