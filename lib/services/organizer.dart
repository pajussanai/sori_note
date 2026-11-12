import '../models/daily_summary.dart';
import '../models/memo.dart';
import '../models/memo_label.dart';
import 'local_organizer.dart';
import 'schedule_parser.dart';

/// 자동 분류 결과
class LabelSuggestion {
  const LabelSuggestion(this.category, this.tags);

  final MemoCategory category;
  final List<String> tags;
}

/// 메모에서 찾은 일정·할 일 후보. 등록 전에 사용자가 확인한다.
class ScheduleCandidate {
  const ScheduleCandidate({
    required this.title,
    required this.sourceText,
    this.dueAt,
    this.allDay = false,
    this.remindAtTime = false,
    this.warnings = const [],
    this.invalid,
  });

  final String title;

  /// 후보를 찾은 문장
  final String sourceText;

  /// 일정 시각(UTC). null이면 할 일.
  final DateTime? dueAt;
  final bool allDay;

  /// '알려줘'처럼 알림을 요청한 문장인지
  final bool remindAtTime;

  /// 확인이 필요한 점(오전/오후, 날짜 등)
  final List<String> warnings;

  /// 등록할 수 없는 이유(이미 지난 시간, 없는 날짜). 고쳐야 등록할 수 있다.
  final String? invalid;

  bool get needsConfirm => warnings.isNotEmpty || invalid != null;
}

/// 메모 정리(분류·태그·하루 요약·일정 추출).
///
/// 지금은 기기 안에서 규칙(한국어 낱말·날짜 표현)으로 처리한다([LocalOrganizer]).
/// 메모 내용이 밖으로 나가지 않고 비용도 들지 않는다. 나중에 서버 AI로 바꿀 수 있도록
/// 화면은 이 인터페이스만 쓴다.
abstract class MemoOrganizer {
  LabelSuggestion classify(String text);

  /// 하루 메모로 요약 항목을 만든다(메모가 없으면 빈 요약).
  Map<SummarySection, List<String>> summarize(
    List<Memo> memos,
    MemoLabel? Function(String memoId) labelOf,
  );

  /// 글에서 일정·할 일 후보를 찾는다. [now]는 기준 시각(한국 시간으로 계산).
  List<ScheduleCandidate> extractSchedules(String text, DateTime now);
}

class RuleBasedOrganizer implements MemoOrganizer {
  const RuleBasedOrganizer();

  @override
  LabelSuggestion classify(String text) => classifyText(text);

  @override
  Map<SummarySection, List<String>> summarize(
    List<Memo> memos,
    MemoLabel? Function(String memoId) labelOf,
  ) => summarizeMemos(memos, labelOf);

  @override
  List<ScheduleCandidate> extractSchedules(String text, DateTime now) =>
      parseSchedules(text, now);
}
