import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/seoul_time.dart';
import '../../models/memo.dart';
import '../../services/polish_service.dart';
import '../../services/speech_input.dart';
import '../../widgets/list_rows.dart';
import 'dictation.dart';
import 'label_sheet.dart';
import 'organize_sheet.dart';
import 'polish_sheet.dart';

enum SaveState { saved, dirty, saving, failed }

/// 메모 화면(보기·고치기). 글자 입력과 말로 받아쓰기(마이크)를 함께 쓰고,
/// 잠시 멈추면 자동 저장한다. 'AI 다듬기'로 문장을 문맥에 맞게 고칠 수 있다.
/// 위에는 작성 시각·분류·태그, 오른쪽 위 '정리'에는 일정 후보와 관련 메모가 있다.
class MemoEditorPage extends StatefulWidget {
  const MemoEditorPage({
    super.key,
    this.memo,
    required this.store,
    required this.polishService,
    required this.speechInput,
    this.startRecording = false,
  });

  /// 없으면 새 메모. 처음 저장할 때 만들어진다.
  final Memo? memo;
  final NoteStore store;
  final PolishService polishService;
  final SpeechInput speechInput;

  /// 화면을 열자마자 받아쓰기를 시작한다.
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

  NoteStore get _store => widget.store;

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
      // 저장하면서 내용이 바뀐 경우에만 다시 분류한다(NoteStore).
      final saved = await _store.saveMemo(_memo?.id, content);
      _memo = saved;
      _lastSaved = content;
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
        content: const Text('삭제한 메모는 되돌릴 수 없습니다. 이 메모에서 등록한 일정은 남습니다.'),
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
    if (memo != null) await _store.deleteMemo(memo.id);
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

  /// 음성 입력이 안 될 때 글자 입력으로 바꾼다. 버튼을 눌러 포커스를 주므로
  /// 휴대폰 브라우저에서도 키보드가 열린다.
  void _typeInstead() {
    _dictation.clearStatus();
    _focus.requestFocus();
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

  // ------------------------------------------------------------- 분류·정리

  /// 분류·태그를 고친다(먼저 저장해 메모를 만든다).
  Future<void> _editLabel() async {
    await _save();
    final memo = _memo;
    if (memo == null || !mounted) {
      _showSnack('먼저 내용을 입력해 주세요.');
      return;
    }
    await showLabelSheet(context, _store, memo.id);
  }

  /// 일정 후보와 관련 메모
  Future<void> _organize() async {
    await _dictation.stop();
    await _save();
    if (!mounted) return;
    final memo = _memo;
    await showOrganizeSheet(
      context,
      store: _store,
      text: _text.text,
      memo: memo,
      openMemo: (m) {
        Navigator.of(context).pop();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => MemoEditorPage(
              memo: m,
              store: _store,
              polishService: widget.polishService,
              speechInput: widget.speechInput,
            ),
          ),
        );
      },
    );
  }

  void _showSnack(String text, {SnackBarAction? action}) {
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
            tooltip: '뒤로',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _leave,
          ),
          title: _SaveStatus(state: _saveState, onRetry: _save),
          actions: [
            IconButton(
              key: const Key('organizeButton'),
              tooltip: '일정 추출·관련 메모',
              icon: const Icon(Icons.event_note_outlined),
              onPressed: _organize,
            ),
            PopupMenuButton<String>(
              key: const Key('memoMenu'),
              tooltip: '더 보기',
              onSelected: (value) {
                if (value == 'delete') _delete();
                if (value == 'label') _editLabel();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'label', child: Text('분류·태그 고치기')),
                PopupMenuItem(
                  key: Key('deleteMemoButton'),
                  value: 'delete',
                  child: Text(
                    '메모 삭제',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListenableBuilder(
                    listenable: _store,
                    builder: (context, _) => _MetaRow(
                      memo: _memo,
                      store: _store,
                      onEdit: _editLabel,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
                          hintText: '첫 줄은 제목이 돼요. 마이크를 누르고 말하거나 입력하세요.',
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
                onKeyboard: _typeInstead,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 작성 시각·분류·태그 한 줄. 누르면 분류·태그를 고친다.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.memo,
    required this.store,
    required this.onEdit,
  });

  final Memo? memo;
  final NoteStore store;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final memo = this.memo;
    final label = memo == null ? null : store.labelOf(memo.id);
    const muted = TextStyle(fontSize: 12.5, color: AppColors.textSub);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            memo == null
                ? '새 메모'
                : '${relativeSeoulDate(seoulDay(memo.createdAt))} ${formatSeoulClock(memo.createdAt)} 작성',
            style: muted,
            overflow: TextOverflow.ellipsis,
          ),
          if (label != null) ...[
            const SizedBox(height: 6),
            InkWell(
              key: const Key('labelChip'),
              borderRadius: BorderRadius.circular(8),
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: LabelLine(
                        category: label.category.label,
                        tags: label.tags.take(4).toList(),
                      ),
                    ),
                    const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: AppColors.textMuted,
                      semanticLabel: '분류·태그 고치기',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
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
    required this.onKeyboard,
  });

  final Dictation dictation;
  final VoidCallback onMic;
  final VoidCallback onPolish;

  /// 받아쓰기가 실패했을 때 글자 입력으로 바꾼다.
  final VoidCallback onKeyboard;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dictation,
      builder: (context, _) {
        final status = dictation.status;
        final dictating = dictation.active;
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.track)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
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
                          if (dictation.statusIsError) ...[
                            const SizedBox(width: 6),
                            TextButton.icon(
                              key: const Key('typeInstead'),
                              onPressed: onKeyboard,
                              icon: const Icon(
                                Icons.keyboard_rounded,
                                size: 18,
                              ),
                              label: const Text('키보드로 입력'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        key: const Key('polishButton'),
                        onPressed: dictating ? null : onPolish,
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                        label: const Text('AI 다듬기'),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: dictating ? '받아쓰기 멈추기' : '말로 입력하기',
                        child: Material(
                          color: dictating
                              ? AppColors.recording
                              : AppColors.primary,
                          shape: const CircleBorder(),
                          elevation: dictating ? 4 : 1,
                          child: InkWell(
                            key: const Key('micButton'),
                            customBorder: const CircleBorder(),
                            onTap: onMic,
                            child: SizedBox.square(
                              dimension: 56,
                              child: dictation.starting
                                  ? const Padding(
                                      padding: EdgeInsets.all(18),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      dictating
                                          ? Icons.stop_rounded
                                          : Icons.mic_rounded,
                                      size: 28,
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
