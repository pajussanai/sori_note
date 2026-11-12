import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';

/// AI 다듬기 결과를 원문과 비교해 보여 준다. '적용'을 누를 때만 바뀐다.
///
/// 적용하면 다듬은 글을, 취소하면 null을 돌려준다.
class PolishSheet extends StatefulWidget {
  const PolishSheet({super.key, required this.original, required this.polish});

  final String original;
  final Future<String> Function() polish;

  @override
  State<PolishSheet> createState() => _PolishSheetState();
}

class _PolishSheetState extends State<PolishSheet> {
  String? _result;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.polish();
      if (!mounted) return;
      setState(() {
        _result = result.trim();
        _loading = false;
      });
    } catch (e) {
      logError('AI 다듬기 실패', e);
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final unchanged = result != null && result == widget.original.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 손잡이는 테마(bottomSheetTheme.showDragHandle)가 그린다.
            const Row(
              children: [
                Icon(Icons.auto_fix_high_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'AI 다듬기',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '받아쓰기 오타, 띄어쓰기, 문장 부호를 문맥에 맞게 고칩니다. '
              '이 메모 내용은 다듬기를 위해 Google Gemini로 전송됩니다.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSub,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Label('다듬은 글'),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text(
                              'AI가 문장을 다듬고 있어요…',
                              style: TextStyle(color: AppColors.textSub),
                            ),
                          ],
                        ),
                      )
                    else if (_error != null)
                      _Box(
                        color: AppColors.danger.withValues(alpha: 0.07),
                        child: Text(
                          _error!,
                          key: const Key('polishError'),
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      )
                    else
                      _Box(
                        color: AppColors.primaryLight,
                        child: SelectableText(
                          unchanged ? '고칠 곳이 없어요. 원문 그대로 좋아요.' : result!,
                          key: const Key('polishResult'),
                          style: const TextStyle(fontSize: 15, height: 1.6),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const _Label('원문'),
                    _Box(
                      color: AppColors.background,
                      child: Text(
                        widget.original,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: AppColors.textSub,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _error != null
                      ? FilledButton.icon(
                          onPressed: _run,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('다시 시도'),
                        )
                      : FilledButton(
                          key: const Key('applyPolish'),
                          onPressed: _loading || unchanged
                              ? null
                              : () => Navigator.of(context).pop(result),
                          child: const Text('적용'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textMain,
      ),
    ),
  );
}

class _Box extends StatelessWidget {
  const _Box({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}
