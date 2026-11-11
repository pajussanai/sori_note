import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../models/memo_audio.dart';
import '../../services/app_settings.dart';
import '../../services/audio_repository.dart';

/// 설정: 원본 음성 저장(기본 꺼짐)과 녹음 보관 사용량.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings, required this.audio});

  final AppSettings settings;
  final AudioRepository audio;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<AudioUsage> _usage = widget.audio.usage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const _SectionTitle('음성'),
                Card(
                  child: ListenableBuilder(
                    listenable: widget.settings,
                    builder: (context, _) => SwitchListTile(
                      key: const Key('saveAudioSwitch'),
                      value: widget.settings.saveOriginalAudio,
                      onChanged: widget.settings.setSaveOriginalAudio,
                      title: const Text('원본 음성 저장'),
                      subtitle: const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '켜면 메모 화면에 녹음 버튼이 생겨 말한 소리를 파일로 보관하고 다시 들을 수 있어요. '
                          '이 기기에만 적용됩니다.',
                          style: TextStyle(height: 1.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _InfoCard(
                  lines: [
                    '받아쓰기(마이크 버튼)는 말을 글자로만 바꾸고 소리를 남기지 않아요.',
                    '녹음은 소리를 그대로 파일로 남기고, 글자로 바꾸지 않아요.',
                    '녹음 파일은 본인만 볼 수 있는 비공개 저장소에 보관되며 AI로 보내지 않아요.',
                    '한 번에 최대 ${AudioLimits.maxDuration.inMinutes}분, '
                        '계정당 최대 ${AudioLimits.quotaBytes ~/ (1024 * 1024)}MB'
                        '(약 2시간, 브라우저·기기에 따라 다름)까지 보관할 수 있어요.',
                    '저장하지 못한 녹음은 이 기기에 남겨 두었다가 다시 올릴 수 있어요.',
                  ],
                ),
                const SizedBox(height: 18),
                const _SectionTitle('녹음 보관 사용량'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FutureBuilder<AudioUsage>(
                      future: _usage,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const LinearProgressIndicator();
                        }
                        final error = snapshot.error;
                        if (error != null) {
                          final notReady =
                              error is AudioException &&
                              error.code == AudioErrorCode.notReady;
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  notReady
                                      ? '서버의 녹음 저장 기능이 아직 준비되지 않았어요.'
                                      : '사용량을 불러오지 못했어요. ${describeError(error)}',
                                  key: const Key('usageError'),
                                  style: const TextStyle(
                                    color: AppColors.textSub,
                                  ),
                                ),
                              ),
                              if (!notReady)
                                TextButton(
                                  onPressed: () => setState(
                                    () => _usage = widget.audio.usage(),
                                  ),
                                  child: const Text('다시 시도'),
                                ),
                            ],
                          );
                        }
                        final usage = snapshot.data!;
                        final ratio = usage.limitBytes == 0
                            ? 0.0
                            : (usage.usedBytes / usage.limitBytes).clamp(
                                0.0,
                                1.0,
                              );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatBytes(usage.usedBytes)} / '
                              '${formatBytes(usage.limitBytes)} · 녹음 ${usage.fileCount}개',
                              key: const Key('usageText'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 8,
                                backgroundColor: AppColors.track,
                                color: ratio > 0.9
                                    ? AppColors.danger
                                    : AppColors.primary,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1.2MB 같은 형식
String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)}MB';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSub,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('·  ', style: TextStyle(color: AppColors.primary)),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
