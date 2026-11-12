import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../models/memo_label.dart';

/// 분류와 태그를 고치는 아래 시트. 고친 값은 자동 분류가 덮어쓰지 않는다.
Future<void> showLabelSheet(
  BuildContext context,
  NoteStore store,
  String memoId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _LabelSheet(store: store, memoId: memoId),
  );
}

class _LabelSheet extends StatefulWidget {
  const _LabelSheet({required this.store, required this.memoId});

  final NoteStore store;
  final String memoId;

  @override
  State<_LabelSheet> createState() => _LabelSheetState();
}

class _LabelSheetState extends State<_LabelSheet> {
  late final _label = widget.store.labelOf(widget.memoId);
  late MemoCategory _category = _label?.category ?? MemoCategory.other;
  late final _tags = TextEditingController(
    text: (_label?.tags ?? const []).map((t) => '#$t').join(' '),
  );

  @override
  void dispose() {
    _tags.dispose();
    super.dispose();
  }

  List<String> _parseTags() => _tags.text
      .split(RegExp(r'[\s,]+'))
      .map((t) => t.replaceFirst(RegExp(r'^#+'), ''))
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final store = widget.store;
    if (_category != _label?.category) {
      await store.setCategory(widget.memoId, _category);
    }
    final tags = _parseTags();
    if (tags.join(' ') != (_label?.tags ?? const []).join(' ')) {
      await store.setTags(widget.memoId, tags);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '분류·태그',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '직접 고친 분류와 태그는 내용이 바뀌어도 자동으로 바뀌지 않아요.',
            style: TextStyle(fontSize: 13, color: AppColors.textSub),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in MemoCategory.values)
                ChoiceChip(
                  key: Key('category-${c.name}'),
                  label: Text(c.label),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('tagsInput'),
            controller: _tags,
            decoration: appFieldDecoration(
              fillColor: AppColors.background,
              labelText: '태그(띄어 쓰기로 구분)',
              hintText: '#회의 #출시',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('saveLabel'),
                onPressed: _save,
                child: const Text('저장'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
