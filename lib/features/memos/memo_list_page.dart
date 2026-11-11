import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/date_utils.dart';
import '../../core/errors.dart';
import '../../models/memo.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/status_view.dart';
import '../audio/editor_audio.dart';
import '../settings/settings_page.dart';
import 'memo_editor_page.dart';
import 'memos_controller.dart';

/// 로그인 후 첫 화면: 메모 목록, 검색, '말로 메모'·'글로 메모' 버튼.
class MemoListPage extends StatefulWidget {
  const MemoListPage({super.key, required this.user, required this.services});

  final AppUser user;
  final AppServices services;

  @override
  State<MemoListPage> createState() => _MemoListPageState();
}

class _MemoListPageState extends State<MemoListPage> {
  late final _memos = MemosController(
    widget.services.memos,
    audio: widget.services.audio,
    pendingAudio: widget.services.pendingAudio,
    userId: widget.user.id,
  );
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _memos.addListener(_showNotice);
    _memos.load();
  }

  @override
  void dispose() {
    _memos.removeListener(_showNotice);
    _memos.dispose();
    super.dispose();
  }

  void _showNotice() {
    final notice = _memos.notice;
    if (notice == null || !mounted) return;
    _memos.clearNotice();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(notice)));
  }

  Future<void> _open({
    Memo? memo,
    bool startRecording = false,
    bool startAudioRecording = false,
  }) async {
    final services = widget.services;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoEditorPage(
          memo: memo,
          repository: services.memos,
          polishService: services.polish,
          speechInput: services.createSpeechInput(),
          onSaved: _memos.saved,
          onDelete: _memos.delete,
          startRecording: startRecording,
          startAudioRecording: startAudioRecording,
          audio: EditorAudio(
            repository: services.audio,
            pendingStore: services.pendingAudio,
            userId: widget.user.id,
            createRecorder: services.createRecorder,
            createPlayer: services.createPlayer,
            settings: services.settings,
          ),
        ),
      ),
    );
    // 편집 화면에서 녹음을 저장·삭제했을 수 있으니 표시를 다시 맞춘다.
    await _memos.refreshAudio();
  }

  Future<void> _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsPage(
        settings: widget.services.settings,
        audio: widget.services.audio,
      ),
    ),
  );

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      // 성공하면 AuthGate가 로그인 화면으로 바꾼다.
      await widget.services.auth.signOut();
    } catch (e) {
      logError('로그아웃 실패', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그아웃하지 못했습니다. ${describeError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            AppLogo(size: 32),
            SizedBox(width: 10),
            Text(
              '소리노트',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '계정',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) =>
                value == 'settings' ? _openSettings() : _signOut(),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  widget.user.email ?? '로그인됨',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const PopupMenuItem<String>(
                key: Key('openSettings'),
                value: 'settings',
                child: Text('설정'),
              ),
              PopupMenuItem<String>(
                key: const Key('signOut'),
                value: 'signOut',
                enabled: !_signingOut,
                child: const Text('로그아웃'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 원본 음성 저장을 켠 경우에만 녹음 버튼을 보여 준다.
          ListenableBuilder(
            listenable: widget.services.settings,
            builder: (context, _) => !widget.services.settings.saveOriginalAudio
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FloatingActionButton(
                      key: const Key('newAudioMemo'),
                      heroTag: 'record',
                      tooltip: '녹음 메모(원본 음성 저장)',
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.recording,
                      onPressed: () => _open(startAudioRecording: true),
                      child: const Icon(Icons.fiber_manual_record_rounded),
                    ),
                  ),
          ),
          FloatingActionButton(
            key: const Key('newTextMemo'),
            heroTag: 'text',
            tooltip: '글로 메모',
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.primary,
            onPressed: () => _open(),
            child: const Icon(Icons.edit_rounded),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            key: const Key('newVoiceMemo'),
            heroTag: 'voice',
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            onPressed: () => _open(startRecording: true),
            icon: const Icon(Icons.mic_rounded),
            label: const Text('말로 메모'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _memos,
        builder: (context, _) => _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_memos.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _memos.error;
    if (error != null) {
      return StatusView(
        icon: Icons.cloud_off_rounded,
        message: '메모를 불러오지 못했습니다.\n$error',
        actionLabel: '다시 시도',
        onAction: _memos.load,
      );
    }
    if (!_memos.hasMemos) return const _EmptyMemos();

    final memos = _memos.memos;
    final audioIds = _memos.audioMemoIds;
    final now = DateTime.now();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: CustomScrollView(
          slivers: [
            if (_memos.pendingCount > 0)
              SliverToBoxAdapter(
                child: _PendingBanner(
                  count: _memos.pendingCount,
                  retrying: _memos.retrying,
                  onRetry: _memos.retryPending,
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  key: const Key('searchInput'),
                  onChanged: _memos.search,
                  decoration: appFieldDecoration(
                    fillColor: AppColors.surface,
                    hintText: '메모 검색',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
            ),
            // 녹음이 있는 메모가 있으면 '음성 기록'만 걸러 볼 수 있다.
            if (audioIds.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        key: const Key('filterAll'),
                        label: const Text('전체'),
                        selected: !_memos.audioOnly,
                        onSelected: (_) => _memos.showAudioOnly(false),
                      ),
                      ChoiceChip(
                        key: const Key('filterAudio'),
                        avatar: const Icon(Icons.graphic_eq_rounded, size: 16),
                        label: Text('음성 기록 ${audioIds.length}'),
                        selected: _memos.audioOnly,
                        onSelected: (_) => _memos.showAudioOnly(true),
                      ),
                    ],
                  ),
                ),
              ),
            if (memos.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    '검색 결과가 없어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSub),
                  ),
                ),
              ),
            SliverPadding(
              // 아래 버튼에 마지막 메모가 가려지지 않게 여백을 둔다.
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              sliver: SliverList.separated(
                itemCount: memos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final memo = memos[index];
                  return _MemoCard(
                    memo: memo,
                    time: formatListTime(memo.updatedAt, now),
                    hasAudio: audioIds.contains(memo.id),
                    onTap: () => _open(memo: memo),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoCard extends StatelessWidget {
  const _MemoCard({
    required this.memo,
    required this.time,
    required this.onTap,
    this.hasAudio = false,
  });

  final Memo memo;
  final String time;
  final VoidCallback onTap;

  /// 원본 음성이 있는 메모
  final bool hasAudio;

  @override
  Widget build(BuildContext context) {
    final preview = memo.preview;
    // 글 없이 녹음만 있는 메모는 '새 메모' 대신 '음성 메모'로 보여 준다.
    final title = hasAudio && memo.content.trim().isEmpty
        ? '음성 메모'
        : memo.title;
    return Card(
      key: ValueKey('memo-${memo.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (hasAudio) ...[
                    const Icon(
                      Icons.graphic_eq_rounded,
                      key: Key('memoHasAudio'),
                      size: 18,
                      color: AppColors.primary,
                      semanticLabel: '녹음 있음',
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.textSub,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 이 기기에 남아 있는(서버에 올리지 못한) 녹음 안내와 다시 올리기
class _PendingBanner extends StatelessWidget {
  const _PendingBanner({
    required this.count,
    required this.retrying,
    required this.onRetry,
  });

  final int count;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pendingBanner'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '저장하지 못한 녹음 $count개가 이 기기에 있어요.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          retrying
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  key: const Key('retryPendingAll'),
                  onPressed: onRetry,
                  child: const Text('다시 저장'),
                ),
        ],
      ),
    );
  }
}

class _EmptyMemos extends StatelessWidget {
  const _EmptyMemos();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none_rounded, size: 56, color: AppColors.iconMuted),
            SizedBox(height: 14),
            Text(
              '아직 메모가 없어요',
              key: Key('emptyMemos'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '아래 \'말로 메모\'를 누르고 말하면 글자로 받아 적어요.\n'
              '받아 적은 글은 \'AI 다듬기\'로 매끄럽게 고칠 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSub, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
