import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../models/memo_label.dart';
import '../../widgets/list_rows.dart';
import '../../widgets/status_view.dart';
import '../shell/app_shell.dart';

/// 기록: 전체 메모와 분류별 보기. 최근 100개씩 불러온다.
class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key, required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  MemoCategory? _category;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Scaffold(
      appBar: AppBar(title: const Text('기록')),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            key: const Key('newTextMemo'),
            heroTag: 'text',
            tooltip: '텍스트 메모',
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.primary,
            onPressed: () => widget.nav.openMemo(null),
            child: const Icon(Icons.edit_rounded),
          ),
          const SizedBox(width: 10),
          FloatingActionButton.extended(
            key: const Key('newVoiceMemo'),
            heroTag: 'voice',
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            onPressed: widget.nav.openVoice,
            icon: const Icon(Icons.mic_rounded),
            label: const Text('음성 기록'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = store.error;
          if (error != null) {
            return StatusView(
              icon: Icons.cloud_off_rounded,
              message: '메모를 불러오지 못했습니다.\n$error',
              actionLabel: '다시 시도',
              onAction: store.load,
            );
          }
          final counts = store.categoryCounts;
          final memos = store.memosIn(_category);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        children: [
                          ChoiceChip(
                            key: const Key('filter-all'),
                            label: Text('전체 ${store.memos.length}'),
                            selected: _category == null,
                            onSelected: (_) => setState(() => _category = null),
                          ),
                          for (final c in MemoCategory.values)
                            if ((counts[c] ?? 0) > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: ChoiceChip(
                                  key: Key('filter-${c.name}'),
                                  label: Text('${c.label} ${counts[c]}'),
                                  selected: _category == c,
                                  onSelected: (_) =>
                                      setState(() => _category = c),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  if (memos.isEmpty)
                    SliverToBoxAdapter(
                      child: EmptyHint(
                        store.memos.isEmpty
                            ? '아직 메모가 없어요. 아래 \'음성 기록\'으로 시작해 보세요.'
                            : '이 분류의 메모가 없어요.',
                      ),
                    ),
                  SliverList.separated(
                    itemCount: memos.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 20, endIndent: 20),
                    itemBuilder: (context, i) => MemoRow(
                      memo: memos[i],
                      store: store,
                      onTap: () => widget.nav.openMemo(memos[i]),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      // 아래 버튼에 마지막 메모가 가려지지 않게 여백을 둔다.
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      child: store.hasMore
                          ? Center(
                              child: store.loadingMore
                                  ? const CircularProgressIndicator()
                                  : TextButton(
                                      key: const Key('loadMore'),
                                      onPressed: store.loadMore,
                                      child: const Text('이전 메모 더 보기'),
                                    ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
