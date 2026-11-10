/// 메모 하나. 첫 줄을 제목처럼 보여 준다.
class Memo {
  const Memo({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 목록에 보여 줄 제목: 내용의 첫 줄(최대 40자). 비어 있으면 '새 메모'.
  String get title {
    final firstLine = content
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return '새 메모';
    return firstLine.length > 40 ? '${firstLine.substring(0, 40)}…' : firstLine;
  }

  /// 목록에 보여 줄 미리보기: 제목 다음 내용을 한 줄로(최대 80자).
  String get preview {
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) return '';
    final rest = lines.skip(1).join(' ');
    return rest.length > 80 ? '${rest.substring(0, 80)}…' : rest;
  }

  Memo copyWith({String? content, DateTime? updatedAt}) => Memo(
    id: id,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory Memo.fromRow(Map<String, dynamic> row) => Memo(
    id: row['id'] as String,
    content: row['content'] as String? ?? '',
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );
}
