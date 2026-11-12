/// 메모 분류(카테고리)
enum MemoCategory {
  work('업무'),
  personal('개인'),
  idea('아이디어'),
  meeting('회의'),
  schedule('일정'),
  todo('쇼핑·할 일'),
  other('기타');

  const MemoCategory(this.label);

  final String label;

  static MemoCategory? byName(String? name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// 메모의 자동 분류 결과와 사용자가 고친 내용. 메모 원문과 따로 보관한다.
class MemoLabel {
  const MemoLabel({
    required this.memoId,
    required this.category,
    required this.tags,
    required this.contentHash,
    this.categoryByUser = false,
    this.tagsByUser = false,
  });

  final String memoId;
  final MemoCategory category;
  final List<String> tags;

  /// 분류할 때의 메모 내용 지문. 내용이 바뀌었을 때만 다시 분류한다.
  final String contentHash;

  /// 사용자가 직접 고쳤으면 자동 분류가 덮어쓰지 않는다.
  final bool categoryByUser;
  final bool tagsByUser;

  MemoLabel copyWith({
    MemoCategory? category,
    List<String>? tags,
    String? contentHash,
    bool? categoryByUser,
    bool? tagsByUser,
  }) => MemoLabel(
    memoId: memoId,
    category: category ?? this.category,
    tags: tags ?? this.tags,
    contentHash: contentHash ?? this.contentHash,
    categoryByUser: categoryByUser ?? this.categoryByUser,
    tagsByUser: tagsByUser ?? this.tagsByUser,
  );

  Map<String, Object> toJson() => {
    'memoId': memoId,
    'category': category.name,
    'tags': tags,
    'hash': contentHash,
    'categoryByUser': categoryByUser,
    'tagsByUser': tagsByUser,
  };

  factory MemoLabel.fromJson(Map<String, dynamic> json) => MemoLabel(
    memoId: json['memoId'] as String,
    category:
        MemoCategory.byName(json['category'] as String?) ?? MemoCategory.other,
    tags: [for (final t in json['tags'] as List? ?? const []) t as String],
    contentHash: json['hash'] as String? ?? '',
    categoryByUser: json['categoryByUser'] as bool? ?? false,
    tagsByUser: json['tagsByUser'] as bool? ?? false,
  );
}

/// 내용 지문(같은 글이면 같은 값). 비교용이며 보안 용도가 아니다.
String contentHash(String text) {
  // FNV-1a 32비트
  var hash = 0x811c9dc5;
  for (final unit in text.trim().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return '${text.trim().length}:${hash.toRadixString(16)}';
}
