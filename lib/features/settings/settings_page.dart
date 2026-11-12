import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/note_store.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/seoul_time.dart';
import '../../services/account_service.dart';
import '../../services/auth_service.dart';
import '../../services/file_saver.dart';
import '../../services/notifier.dart';
import '../../widgets/list_rows.dart';
import '../plans/plans_page.dart';

/// 설정: 계정, 알림, AI 사용량, 데이터 사용 현황·내보내기, 계정 삭제.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.services,
    required this.user,
  });

  final NoteStore store;
  final AppServices services;
  final AppUser user;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<List<DailyUsage>> _usage = widget.services.account.polishUsage();
  late Future<int> _memoCount = widget.services.memos.countMemos();
  late Future<int> _localBytes = widget.store.localDataBytes();
  bool _busy = false;

  /// 서버 기본값(POLISH_DAILY_LIMIT 미설정 시)
  static const _polishDailyLimit = 50;

  Notifier get _notifier => widget.services.notifier;

  void _refresh() => setState(() {
    _usage = widget.services.account.polishUsage();
    _memoCount = widget.services.memos.countMemos();
    _localBytes = widget.store.localDataBytes();
  });

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      // 성공하면 AuthGate가 로그인 화면으로 바꾼다.
      await widget.services.auth.signOut();
    } catch (e) {
      logError('로그아웃 실패', e);
      _snack('로그아웃하지 못했습니다. ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final json = await widget.store.exportJson(email: widget.user.email);
      final name = 'sori_note_${dayKey(seoulDay(widget.store.now))}.json';
      if (saveTextFile(name, json)) {
        _snack('$name 파일로 내려받았어요.');
      } else {
        await Clipboard.setData(ClipboardData(text: json));
        _snack('내보낸 내용을 클립보드에 복사했어요.');
      }
    } catch (e) {
      logError('내보내기 실패', e);
      _snack('내보내지 못했어요. ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await widget.services.account.deleteAccount();
      if (result == AccountDeletion.memosOnly) {
        // 서버에 계정 삭제 기능이 아직 없으면 메모와 이 기기의 기록만 지운다.
        await widget.store.deleteEverything();
      } else {
        await widget.store.clearLocal();
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('삭제했어요'),
          content: Text(
            result == AccountDeletion.deleted
                ? '계정과 모든 메모, 이 기기의 기록을 삭제했어요.'
                : '모든 메모와 이 기기의 분류·일정·요약을 삭제했어요.\n'
                      '로그인 계정(이메일) 자체를 지우는 서버 기능은 아직 준비되지 않아 계정은 남아 있어요.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      try {
        await widget.services.auth.signOut();
      } catch (_) {}
    } catch (e) {
      logError('계정 삭제 실패', e);
      _snack('삭제하지 못했어요. ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final permission = _notifier.permission;
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        actions: [
          IconButton(
            tooltip: '새로 고침',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              const SectionHeader('계정'),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(widget.user.email ?? '로그인됨'),
                subtitle: const Text('이메일 계정'),
              ),
              ListTile(
                key: const Key('signOut'),
                leading: const Icon(Icons.logout_rounded),
                title: const Text('로그아웃'),
                enabled: !_busy,
                onTap: _signOut,
              ),
              const SectionHeader('알림'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  notifyPermissionText(permission),
                  key: const Key('notifyStatus'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: AppColors.textSub,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 4,
                  children: [
                    if (permission == NotifyPermission.prompt)
                      TextButton(
                        key: const Key('enableNotify'),
                        onPressed: () async {
                          await _notifier.request();
                          if (mounted) setState(() {});
                        },
                        child: const Text('알림 허용'),
                      ),
                    if (permission == NotifyPermission.granted)
                      TextButton(
                        key: const Key('testNotify'),
                        onPressed: () => _notifier.show('소리노트', '알림이 잘 와요.'),
                        child: const Text('시험 알림 보내기'),
                      ),
                  ],
                ),
              ),
              const SectionHeader('AI 사용량'),
              FutureBuilder<List<DailyUsage>>(
                future: _usage,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: LinearProgressIndicator(),
                    );
                  }
                  if (snapshot.hasError) {
                    return EmptyHint(
                      '사용량을 불러오지 못했어요. ${describeError(snapshot.error!)}',
                    );
                  }
                  final rows = snapshot.data!;
                  final todayKey = dayKey(seoulDay(store.now));
                  final today = rows
                      .where((r) => r.day == todayKey)
                      .fold(0, (s, r) => s + r.count);
                  final week = rows.fold(0, (s, r) => s + r.count);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 다듬기 오늘 $today회 / 하루 $_polishDailyLimit회 · 최근 7일 $week회',
                          key: const Key('aiUsage'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (today / _polishDailyLimit).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: AppColors.track,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'AI 다듬기만 서버의 무료 AI를 써요(누를 때만). 자동 분류·하루 요약·일정 찾기는 '
                          '기기 안에서 처리해 AI 사용량과 비용이 들지 않아요.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: AppColors.textSub,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SectionHeader('데이터'),
              FutureBuilder<int>(
                future: _memoCount,
                builder: (context, snapshot) => ListTile(
                  key: const Key('memoCount'),
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(
                    snapshot.hasData
                        ? '서버에 저장된 메모 ${snapshot.data}개'
                        : snapshot.hasError
                        ? '메모 수를 불러오지 못했어요'
                        : '메모 수 확인 중…',
                  ),
                  subtitle: const Text('본인만 볼 수 있어요'),
                ),
              ),
              FutureBuilder<int>(
                future: _localBytes,
                builder: (context, snapshot) => ListTile(
                  leading: const Icon(Icons.phone_android_rounded),
                  title: Text(
                    '이 기기: 분류 ${store.labelCount}개 · 일정 ${store.plans.length}개 · '
                    '요약 ${store.summaryCount}개',
                  ),
                  subtitle: Text(
                    '${snapshot.hasData ? '${(snapshot.data! / 1024).toStringAsFixed(1)}KB · ' : ''}'
                    '분류·일정·요약은 이 기기(브라우저)에만 저장돼요. 다른 기기에서는 보이지 않아요.',
                  ),
                ),
              ),
              ListTile(
                key: const Key('exportData'),
                leading: const Icon(Icons.download_rounded),
                title: const Text('데이터 내보내기(JSON)'),
                subtitle: const Text('모든 메모와 분류·일정·요약'),
                enabled: !_busy,
                onTap: _export,
              ),
              ListTile(
                key: const Key('deleteAccount'),
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: AppColors.danger,
                ),
                title: const Text(
                  '계정 삭제',
                  style: TextStyle(color: AppColors.danger),
                ),
                subtitle: const Text('모든 메모와 이 기기의 기록을 지워요'),
                enabled: !_busy,
                onTap: _deleteAccount,
              ),
              const SectionHeader('정보'),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Text(
                  '소리노트 1.0 · 음성은 기기(브라우저) 음성 인식으로 바로 글자로 바꾸며, 소리 파일은 저장하지 않아요.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppColors.textMuted,
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

/// '삭제'를 직접 입력해야 진행하는 확인 창
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('계정을 삭제할까요?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '모든 메모와 이 기기의 분류·일정·요약이 지워지며 되돌릴 수 없어요. '
            '필요하면 먼저 데이터를 내보내세요.\n\n계속하려면 아래에 "삭제"를 입력하세요.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('deleteConfirmInput'),
            controller: _text,
            onChanged: (_) => setState(() {}),
            decoration: appFieldDecoration(
              fillColor: AppColors.background,
              hintText: '삭제',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const Key('deleteConfirm'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _text.text.trim() == '삭제'
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('계정 삭제'),
        ),
      ],
    );
  }
}
