// 기기 안에서 규칙으로 하는 메모 정리: 분류, 태그, 하루 요약.
import '../models/daily_summary.dart';
import '../models/memo.dart';
import '../models/memo_label.dart';
import 'organizer.dart';

/// 분류별 단서 낱말. 앞에 있는 분류가 동점일 때 우선한다.
const _categoryWords = <MemoCategory, List<String>>{
  MemoCategory.meeting: [
    '회의',
    '미팅',
    '회의록',
    '안건',
    '참석',
    '논의',
    '브리핑',
    '워크숍',
    '면담',
    '1:1',
  ],
  MemoCategory.schedule: [
    '약속',
    '예약',
    '일정',
    '마감',
    '생일',
    '기념일',
    '병원',
    '진료',
    '출장',
    '내일',
    '모레',
    '다음 주',
    '다음주',
    '이번 주',
    '요일',
    '오전',
    '오후',
    '시까지',
  ],
  MemoCategory.todo: [
    '할 일',
    '할일',
    '해야',
    '사기',
    '사야',
    '구매',
    '장보기',
    '장 보기',
    '주문',
    '쇼핑',
    '챙기기',
    '챙겨',
    '준비물',
    '체크리스트',
    '우유',
    '마트',
  ],
  MemoCategory.work: [
    '업무',
    '보고서',
    '보고',
    '프로젝트',
    '고객',
    '거래처',
    '회사',
    '팀장',
    '결재',
    '메일',
    '발표',
    '기획',
    '계약',
    '매출',
    '개발',
    '배포',
    '출근',
    '견적',
    '납품',
  ],
  MemoCategory.idea: [
    '아이디어',
    '구상',
    '영감',
    '떠올',
    '만들면',
    '좋겠',
    '어떨까',
    '해 보면',
    '해보면',
    '만약',
    '착안',
    '브레인스토밍',
  ],
  MemoCategory.personal: [
    '가족',
    '엄마',
    '아빠',
    '아이',
    '아들',
    '딸',
    '운동',
    '건강',
    '다이어트',
    '여행',
    '친구',
    '취미',
    '일기',
    '기분',
    '주말',
    '영화',
    '독서',
    '산책',
    '요리',
  ],
};

const _stopwords = {
  '그리고',
  '그래서',
  '그런데',
  '하지만',
  '그러나',
  '또는',
  '그냥',
  '정말',
  '너무',
  '오늘',
  '내일',
  '모레',
  '어제',
  '이번',
  '다음',
  '지난',
  '우리',
  '저희',
  '나는',
  '내가',
  '이것',
  '그것',
  '저것',
  '여기',
  '거기',
  '이거',
  '그거',
  '것',
  '수',
  '등',
  '좀',
  '더',
  '하다',
  '있다',
  '없다',
  '되다',
  '같다',
  '이다',
  '해서',
  '하고',
  '하면',
  '했다',
  '한다',
  '합니다',
  '했어요',
  '해요',
  '있어요',
  '없어요',
  '입니다',
  '오전',
  '오후',
  '아침',
  '저녁',
  '점심',
  '정도',
  '부분',
  '때문',
  '관련',
  '대한',
  '위해',
  '통해',
  '경우',
  '알려줘',
  '알려',
  '메모',
  '확인',
  '진짜',
  '아마',
  '먼저',
  '다시',
  '계속',
  '바로',
};

/// 낱말 끝의 조사(긴 것부터 확인)
const _particles = [
  '에서는',
  '으로는',
  '에게서',
  '한테서',
  '까지는',
  '부터는',
  '이라고',
  '라고',
  '에서',
  '으로',
  '에게',
  '한테',
  '까지',
  '부터',
  '처럼',
  '보다',
  '하고',
  '이랑',
  '과는',
  '와는',
  '은',
  '는',
  '이',
  '가',
  '을',
  '를',
  '에',
  '로',
  '와',
  '과',
  '도',
  '만',
  '의',
  '께',
  '랑',
];

/// 동사·형용사로 보이는 끝(태그에서 뺀다)
const _verbEndings = [
  '했다',
  '한다',
  '하다',
  '해요',
  '했어',
  '하기',
  '하자',
  '하면',
  '해서',
  '하고',
  '니다',
  '어요',
  '아요',
  '세요',
  '었다',
  '았다',
  '겠다',
  '는데',
  '지만',
  '려고',
  '도록',
  '라고',
  '면서',
  '거나',
  '듯이',
];

final _wordPattern = RegExp(r'[0-9A-Za-z가-힣]+');
final _hasHangulOrLetter = RegExp(r'[A-Za-z가-힣]');

/// 내용으로 분류와 태그(최대 5개)를 정한다.
LabelSuggestion classifyText(String text) {
  final body = text.trim();
  if (body.isEmpty) return const LabelSuggestion(MemoCategory.other, []);
  final firstLine = body.split('\n').first;
  final lower = body.toLowerCase();

  MemoCategory best = MemoCategory.other;
  var bestScore = 0;
  for (final entry in _categoryWords.entries) {
    var score = 0;
    for (final word in entry.value) {
      final count = _count(lower, word);
      if (count == 0) continue;
      score += count + (firstLine.contains(word) ? 1 : 0);
    }
    if (score > bestScore) {
      best = entry.key;
      bestScore = score;
    }
  }
  // 분류 이름과 같은 태그(예: 회의 메모의 #회의)는 겹치므로 뺀다.
  final tags = [
    for (final t in extractTags(body, max: 6))
      if (t != best.label) t,
  ].take(5).toList();
  return LabelSuggestion(best, tags);
}

int _count(String text, String word) {
  var count = 0;
  var index = text.indexOf(word);
  while (index >= 0) {
    count++;
    index = text.indexOf(word, index + word.length);
  }
  return count;
}

/// 핵심 낱말을 태그로 뽑는다(자주 나오고, 첫 줄에 있는 낱말 우선).
List<String> extractTags(String text, {int max = 5}) {
  final firstLine = text.trim().split('\n').first;
  final scores = <String, int>{};
  final order = <String, int>{};
  var position = 0;
  for (final match in _wordPattern.allMatches(text)) {
    final word = _stem(match.group(0)!);
    if (word == null) continue;
    scores[word] = (scores[word] ?? 0) + (firstLine.contains(word) ? 2 : 1);
    order.putIfAbsent(word, () => position++);
  }
  final words = scores.keys.toList()
    ..sort((a, b) {
      final byScore = scores[b]!.compareTo(scores[a]!);
      return byScore != 0 ? byScore : order[a]!.compareTo(order[b]!);
    });
  return words.take(max).toList();
}

/// 낱말에서 조사를 떼고, 태그로 쓸 수 없으면 null.
String? _stem(String raw) {
  var word = raw.toLowerCase();
  if (!_hasHangulOrLetter.hasMatch(word)) return null; // 숫자만
  for (final p in _particles) {
    if (word.length - p.length >= 2 && word.endsWith(p)) {
      word = word.substring(0, word.length - p.length);
      break;
    }
  }
  if (word.length < 2 || word.length > 12) return null;
  if (_stopwords.contains(word)) return null;
  for (final e in _verbEndings) {
    if (word.endsWith(e)) return null;
  }
  // 시각·날짜 표현(3시, 12일, 5월)은 태그가 아니다.
  if (RegExp(r'^\d+(시|분|일|월|년|개|번|명|원)$').hasMatch(word)) return null;
  if (RegExp(r'^(월|화|수|목|금|토|일)요일$').hasMatch(word)) return null;
  return word;
}

// ------------------------------------------------------------- 하루 요약

// 문장마다 위에서부터 처음 맞는 항목에 넣는다(같은 항목이 두 번 나오면 단서의 세기가 다르다).
const _sectionWords = <(SummarySection, List<String>)>[
  (
    SummarySection.decisions,
    ['결정', '확정', '하기로', '합의', '결론', '승인', '채택', '정했', '정함'],
  ),
  (
    SummarySection.issues,
    [
      '문제',
      '이슈',
      '오류',
      '에러',
      '버그',
      '지연',
      '장애',
      '리스크',
      '우려',
      '걱정',
      '실패',
      '불만',
      '어려움',
      '막힘',
      '안 됨',
      '안됨',
    ],
  ),
  (SummarySection.remember, ['기억', '잊지', '명심', '메모해']),
  (
    SummarySection.todos,
    [
      '해야',
      '할 일',
      '할일',
      '하기',
      '까지',
      '마감',
      '준비',
      '챙기',
      '사야',
      '사기',
      '예약',
      '연락',
      '제출',
      '보내기',
      'todo',
      '[ ]',
    ],
  ),
  (SummarySection.remember, ['중요', '꼭', '주의', '참고']),
  (
    SummarySection.progress,
    [
      '진행',
      '완료',
      '끝냈',
      '마쳤',
      '작업',
      '업무',
      '회의',
      '보고',
      '처리',
      '검토',
      '했다',
      '했음',
      '했어요',
      '진척',
    ],
  ),
];

final _sentenceSplit = RegExp(r'(?<=[.!?。])\s+|\n+');

/// 하루 메모를 항목별로 정리한다. 항목마다 최대 6개, 문장은 120자까지.
Map<SummarySection, List<String>> summarizeMemos(
  List<Memo> memos,
  MemoLabel? Function(String memoId) labelOf,
) {
  final result = {for (final s in SummarySection.values) s: <String>[]};
  if (memos.isEmpty) return result;
  final ordered = [...memos]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  for (final memo in ordered.take(6)) {
    final label = labelOf(memo.id);
    final tag = label == null || label.category == MemoCategory.other
        ? ''
        : '[${label.category.label}] ';
    result[SummarySection.highlights]!.add(_short('$tag${memo.title}'));
  }
  if (ordered.length > 6) {
    result[SummarySection.highlights]!.add('외 ${ordered.length - 6}개 메모');
  }

  final seen = <String>{};
  for (final memo in ordered) {
    final label = labelOf(memo.id);
    final workLike =
        label?.category == MemoCategory.work ||
        label?.category == MemoCategory.meeting;
    final sentences = memo.content
        .split(_sentenceSplit)
        .map((s) => s.trim().replaceFirst(RegExp(r'^[-*•·]\s*'), ''))
        .where((s) => s.length >= 2);
    for (final sentence in sentences) {
      if (!seen.add(sentence)) continue;
      final lower = sentence.toLowerCase();
      SummarySection? section;
      for (final (candidate, words) in _sectionWords) {
        if (words.any(lower.contains)) {
          section = candidate;
          break;
        }
      }
      // 업무·회의 메모의 문장은 단서가 없어도 진행 상황으로 본다(제목 줄은 뺀다).
      if (section == null && workLike && sentence != memo.title) {
        section = SummarySection.progress;
      }
      if (section == null) continue;
      final list = result[section]!;
      if (list.length < 6) list.add(_short(sentence));
    }
  }
  return result;
}

String _short(String text) =>
    text.length > 120 ? '${text.substring(0, 120)}…' : text;
