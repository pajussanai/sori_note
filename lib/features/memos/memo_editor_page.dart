import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../models/memo.dart';
import '../../services/memo_repository.dart';
import '../../services/polish_service.dart';
import '../../services/speech_input.dart';
import 'dictation.dart';
import 'polish_sheet.dart';

enum SaveState { saved, dirty, saving, failed }

/// 메모 쓰기 화면. 말로 받아쓰기(마이크)와 글자 입력을 함께 쓰고,
/// 잠시 멈추면 자동 저장한다. 'AI 다듬기'로 문장을 문맥에 맞게 고칠 수 있다.
class MemoEditorPage extends StatefulWidget {
  const MemoEditorPage({
    super.key,
    this.memo,
    required this.repository,
    required this.polishService,
    required this.speechInput,
    required this.onSaved,
    required this.onDelete,
    this.startRecording = false,
  });

  /// 없으면 새 메모. 처음 저장할 때 만들어진다.
  final Memo? memo;
  final MemoRepository repository;
  final PolishService polishService;
  final SpeechInput speechInput;
  final ValueChanged<Memo> onSaved;
  final Future<void> Function(String id) onDelete;

  /// 화면을 열자마자 받아쓰기를 시작한다('말로 메모' 버튼).
  final bool startRecording;

  /// 입력을 멈춘 뒤 이 시간이 지나면 저장한다.
  static const saveDelay = Duration(milliseconds: 1200);

  static const maxLength = 20000;

  @override
  State<MemoEditorPage> createState() => _MemoEditorPageState();
}

class _MemoEditorPageState extends State<MemoEditorPage> {
  late final _text = TextEditingController(text: widget.memo?.content ?? '');
  late final _dictation = Dictation(widget.speechInput);
  final _focus = FocusNode();

  Memo? _memo;
  late String _lastSaved = widget.memo?.content ?? '';
  SaveState _saveState = SaveState.saved;
  Timer? _saveTimer;
  Future<void>? _saving;

  /// 받아쓰기를 시작할 때의 글과 끼워 넣을 자리
  String _dictationBase = '';
  int _dictationAt = 0;

  @override
  void initState() {
    super.initState();
    _memo = widget.memo;
    _text.addListener(_onTextChanged);
    if (widget.startRecording) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleMic());
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _focus.dispose();
    _dictation.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- 자동 저장

  void _onTextChanged() {
    if (_text.text == _lastSaved) return;
    if (_saveState != SaveState.dirty) {
      setState(() => _saveState = SaveState.dirty);
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(MemoEditorPage.saveDelay, _save);
  }

  /// 지금 내용을 저장한다. 저장 중이면 끝난 뒤 한 번 더 확인한다.
  Future<void> _save() async {
    _saveTimer?.cancel();
    final running = _saving;
    if (running != null) {
      await running;
      if (_text.text != _lastSaved) return _save();
      return;
    }
    final content = _text.text;
    if (content == _lastSaved) return;
    // 아직 만들지 않은 메모가 비어 있으면 저장하지 않는다.
    if (_memo == null && content.trim().isEmpty) {
      _lastSaved = content;
      if (mounted) setState(() => _saveState = SaveState.saved);
      return;
    }

    if (mounted) setState(() => _saveState = SaveState.saving);
    final done = Completer<void>();
    _saving = done.future;
    try {
      final memo = _memo;
      final saved = memo == null
          ? await widget.repository.createMemo(content)
          : await widget.repository.updateMemo(memo.id, content);
      _memo = saved;
      _lastSaved = content;
      widget.onSaved(saved);
      if (mounted) {
        setState(() {
          _saveState = _text.text == _lastSaved
              ? SaveState.saved
              : SaveState.dirty;
        });
      }
    } catch (e) {
      logError('메모 저장 실패', e);
      if (mounted) setState(() => _saveState = SaveState.failed);
    } finally {
      _saving = null;
      done.complete();
    }
    // 저장하는 동안 더 쓴 내용이 있으면 이어서 저장한다.
    if (mounted && _saveState == SaveState.dirty) {
      _saveTimer = Timer(MemoEditorPage.saveDelay, _save);
    }
  }

  /// 나가기 전에 남은 내용을 저장한다. 실패하면 나갈지 묻는다.
  Future<void> _leave() async {
    await _dictation.stop();
    await _save();
    if (!mounted) return;
    if (_saveState == SaveState.failed) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('저장하지 못했어요'),
          content: const Text('네트워크를 확인해 주세요. 지금 나가면 마지막 변경 내용이 사라집니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('머무르기'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('그래도 나가기'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final memo = _memo;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('메모를 삭제할까요?'),
        content: const Text('삭제한 메모는 되돌릴 수 없습니다.'),
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
    _saveTimer?.cancel();
    await _dictation.stop();
    if (memo != null) await widget.onDelete(memo.id);
    if (mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------------- 받아쓰기

  /// 들은 글을 커서 자리에 끼워 넣는다. 말하는 동안 중간 결과로 계속 바꾼다.
  Future<void> _toggleMic() async {
    if (!_dictation.active) {
      _dictationBase = _text.text;
      final selection = _text.selection;
      _dictationAt = selection.isValid
          ? selection.end.clamp(0, _dictationBase.length)
          : _dictationBase.length;
    }
    await _dictation.toggle((spoken, {required isFinal}) {
      if (!mounted) return;
      final words = spoken.trim();
      if (words.isEmpty) return;
      final before = _dictationBase.substring(0, _dictationAt);
      final after = _dictationBase.substring(_dictationAt);
      final needsSpace = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before);
      final inserted = '${needsSpace ? ' ' : ''}$words';
      var text = '$before$inserted$after';
      if (text.length > MemoEditorPage.maxLength) {
        text = text.substring(0, MemoEditorPage.maxLength);
      }
      final caret = (before.length + inserted.length).clamp(0, text.length);
      _text.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret),
      );
      if (isFinal) {
        // 다음 받아쓰기는 이번에 넣은 글 뒤에서 이어진다.
        _dictationBase = text;
        _dictationAt = caret;
      }
    });
  }

  // ------------------------------------------------------------- AI 다듬기

  Future<void> _polish() async {
    await _dictation.stop();
    final original = _text.text;
    if (original.trim().isEmpty) {
      _showSnack('다듬을 내용이 없어요. 먼저 말하거나 입력해 주세요.');
      return;
    }
    if (!mounted) return;
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

    _text.value = TextEditingValue(
      text: improved,
      selection: TextSelection.collapsed(offset: improved.length),
    );
    unawaited(_save());
    _showSnack(
      '다듬은 글로 바꿨어요.',
      action: SnackBarAction(
        label: '되돌리기',
        onPressed: () {
          _text.value = TextEditingValue(
            text: original,
            selection: TextSelection.collapsed(offset: original.length),
          );
          unawaited(_save());
        },
      ),
    );
  }

  void _showSnack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  // ------------------------------------------------------------- 화면

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('backButton'),
            tooltip: '목록으로',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _leave,
          ),
          title: _SaveStatus(state: _saveState, onRetry: _save),
          actions: [
            IconButton(
              key: const Key('deleteMemoButton'),
              tooltip: '메모 삭제',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: TextField(
                        key: const Key('memoInput'),
                        controller: _text,
                        focusNode: _focus,
                        maxLines: null,
                        expands: true,
                        maxLength: MemoEditorPage.maxLength,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.65,
                          color: AppColors.textMain,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          hintText: '마이크를 누르고 말하거나, 여기에 입력하세요.',
                          hintStyle: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _EditorBar(
                dictation: _dictation,
                onMic: _toggleMic,
                onPolish: _polish,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 상단 저장 상태: 저장됨 / 저장 중 / 저장 실패(다시 시도)
class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.state, required this.onRetry});

  final SaveState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13, color: AppColors.textSub);
    return switch (state) {
      SaveState.saved => const Text(
        '저장됨',
        key: Key('saveStatus'),
        style: style,
      ),
      SaveState.dirty || SaveState.saving => const Text(
        '저장 중…',
        key: Key('saveStatus'),
        style: style,
      ),
      SaveState.failed => TextButton.icon(
        key: const Key('saveRetry'),
        onPressed: onRetry,
        icon: const Icon(
          Icons.cloud_off_rounded,
          size: 16,
          color: AppColors.danger,
        ),
        label: const Text(
          '저장하지 못했어요 · 다시 시도',
          style: TextStyle(fontSize: 13, color: AppColors.danger),
        ),
      ),
    };
  }
}

/// 아래 도구 막대: 받아쓰기 안내, AI 다듬기 버튼, 큰 마이크 버튼
class _EditorBar extends StatelessWidget {
  const _EditorBar({
    required this.dictation,
    required this.onMic,
    required this.onPolish,
  });

  final Dictation dictation;
  final VoidCallback onMic;
  final VoidCallback onPolish;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dictation,
      builder: (context, _) {
        final status = dictation.status;
        final recording = dictation.active;
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: softShadow,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(
                            dictation.statusIsError
                                ? Icons.info_outline_rounded
                                : Icons.graphic_eq_rounded,
                            size: 16,
                            color: dictation.statusIsError
                                ? AppColors.danger
                                : AppColors.recording,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              status,
                              key: const Key('dictationStatus'),
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: dictation.statusIsError
                                    ? AppColors.danger
                                    : AppColors.textSub,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        key: const Key('polishButton'),
                        onPressed: recording ? null : onPolish,
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                        label: const Text('AI 다듬기'),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: recording ? '받아쓰기 멈추기' : '말로 입력하기',
                        child: Material(
                          color: recording
                              ? AppColors.recording
                              : AppColors.primary,
                          shape: const CircleBorder(),
                          elevation: recording ? 6 : 2,
                          child: InkWell(
                            key: const Key('micButton'),
                            customBorder: const CircleBorder(),
                            onTap: onMic,
                            child: SizedBox.square(
                              dimension: 64,
                              child: dictation.starting
                                  ? const Padding(
                                      padding: EdgeInsets.all(22),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      recording
                                          ? Icons.stop_rounded
                                          : Icons.mic_rounded,
                                      size: 30,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
