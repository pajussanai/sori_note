import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/note_store.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../models/memo_label.dart';
import '../../widgets/list_rows.dart';
import '../shell/app_shell.dart';

/// 검색: 제목·본문·태그 통합 검색, 분류·태그 걸러 보기, 결과 미리보기.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.store, required this.nav});

  final NoteStore store;
  final ShellNav nav;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  MemoCategory? _category;
  String? _tag;
  List<SearchHit> _hits = [];
  bool _searching = false;
  String? _error;

  /// 늦게 도착한 이전 검색 결과를 버리기 위한 번호
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    // 글자를 칠 때마다 서버에 묻지 않도록 잠시 멈춘 뒤 찾는다.
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  Future<void> _run() async {
    final id = ++_request;
    final q = _query.text;
    if (q.trim().isEmpty && _category == null && _tag == null) {
      setState(() {
        _hits = [];
        _error = null;
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final hits = await widget.store.search(q, category: _category, tag: _tag);
      if (!mounted || id != _request) return;
      setState(() => _hits = hits);
    } catch (e) {
      logError('검색 실패', e);
      if (mounted && id == _request) setState(() => _error = describeError(e));
    } finally {
      if (mounted && id == _request) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final tags = store.allTags.take(12).toList();
    final hasFilter =
        _query.text.trim().isNotEmpty || _category != null || _tag != null;
    return Scaffold(
      appBar: AppBar(titleSpacing: 20, title: const Text('검색')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: TextField(
                  key: const Key('searchInput'),
                  controller: _query,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _run(),
                  decoration: appFieldDecoration(
                    fillColor: AppColors.surface,
                    hintText: '제목, 본문, 태그로 찾기',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '지우기',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _query.clear();
                              _run();
                            },
                          ),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final c in MemoCategory.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          key: Key('searchCategory-${c.name}'),
                          avatar: CategoryDot(c.label),
                          label: Text(c.label),
                          selected: _category == c,
                          onSelected: (on) {
                            setState(() => _category = on ? c : null);
                            _run();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              if (tags.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      for (final t in tags)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            key: Key('searchTag-$t'),
                            label: Text('#$t'),
                            selected: _tag == t,
                            onSelected: (on) {
                              setState(() => _tag = on ? t : null);
                              _run();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              if (_searching) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: _error != null
                    ? EmptyHint('검색하지 못했어요. $_error')
                    : !hasFilter
                    ? const EmptyHint('메모 제목과 본문, 분류, 태그로 찾을 수 있어요.')
                    : _hits.isEmpty && !_searching
                    ? const EmptyHint('검색 결과가 없어요.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          8,
                          20,
                          fabClearance,
                        ),
                        itemCount: _hits.length + 1,
                        separatorBuilder: (_, i) =>
                            SizedBox(height: i == 0 ? 6 : 10),
                        itemBuilder: (context, i) => i == 0
                            ? Text(
                                '검색 결과 ${_hits.length}개',
                                key: const Key('searchCount'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSub,
                                ),
                              )
                            : MemoRow(
                                memo: _hits[i - 1].memo,
                                store: store,
                                preview: _hits[i - 1].preview,
                                onTap: () =>
                                    widget.nav.openMemo(_hits[i - 1].memo),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
