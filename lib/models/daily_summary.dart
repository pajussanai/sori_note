/// 일일 요약의 항목
enum SummarySection {
  highlights('오늘의 주요 내용'),
  progress('주요 업무 및 진행 상황'),
  decisions('중요한 결정 사항'),
  issues('주요 이슈 및 문제'),
  todos('해야 할 일'),
  remember('기억해야 할 내용');

  const SummarySection(this.label);

  final String label;
}

/// 하루(한국 날짜)의 메모를 모아 만든 요약. 사용자가 고치거나 지울 수 있다.
class DailySummary {
  const DailySummary({
    required this.day,
    required this.sections,
    required this.memoCount,
    required this.createdAt,
    this.edited = false,
  });

  /// 2026-11-12
  final String day;
  final Map<SummarySection, List<String>> sections;
  final int memoCount;
  final DateTime createdAt;

  /// 사용자가 고쳤는지
  final bool edited;

  List<String> items(SummarySection section) => sections[section] ?? const [];

  bool get isEmpty => sections.values.every((v) => v.isEmpty);

  DailySummary copyWith({
    Map<SummarySection, List<String>>? sections,
    bool? edited,
  }) => DailySummary(
    day: day,
    sections: sections ?? this.sections,
    memoCount: memoCount,
    createdAt: createdAt,
    edited: edited ?? this.edited,
  );

  Map<String, Object> toJson() => {
    'day': day,
    'sections': {for (final e in sections.entries) e.key.name: e.value},
    'memoCount': memoCount,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'edited': edited,
  };

  factory DailySummary.fromJson(Map<String, dynamic> json) {
    final raw = json['sections'] as Map<String, dynamic>? ?? const {};
    return DailySummary(
      day: json['day'] as String,
      sections: {
        for (final s in SummarySection.values)
          s: [for (final v in raw[s.name] as List? ?? const []) v as String],
      },
      memoCount: (json['memoCount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      edited: json['edited'] as bool? ?? false,
    );
  }
}
