import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../models/memo_label.dart';
import '../../widgets/list_rows.dart';
import '../../widgets/status_view.dart';
import '../shell/app_shell.dart';

/// 기록: 전체 메모와 분류별 보기. 최근 100개씩 불러온다.
/// 음성 기록은 오른쪽 아래 버튼, 텍스트 메모는 오른쪽 위 버튼으로 시작한다.
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
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('기록'),
        actions: [
          IconButton(
            key: const Key('recordsNewMemo'),
            tooltip: '새 텍스트 메모',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => widget.nav.openMemo(null),
          ),
          const SizedBox(width: 8),
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
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
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
                            ? '아직 메모가 없어요. 오른쪽 아래 마이크 버튼으로 음성 기록을 시작해 보세요.'
                            : '이 분류의 메모가 없어요.',
                      ),
                    ),
                  SliverPadding(
                    padding: pagePadding,
                    sliver: SliverList.separated(
                      itemCount: memos.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => MemoRow(
                        memo: memos[i],
                        store: store,
                        onTap: () => widget.nav.openMemo(memos[i]),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        fabClearance,
                      ),
                      child: store.hasMore
                          ? Center(
                              child: store.loadingMore
                                  ? const CircularProgressIndicator()
                                  : OutlinedButton(
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
