import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sori_note/main.dart';
import 'package:sori_note/models/memo.dart';
import 'package:sori_note/services/auth_service.dart';

import 'fakes.dart';

Memo memo(String id, String content, int minute) => Memo(
  id: id,
  content: content,
  createdAt: DateTime.utc(2026, 11, 1, 9, minute),
  updatedAt: DateTime.utc(2026, 11, 1, 9, minute),
);

/// 가짜 서비스로 앱을 띄운다.
Future<FakeServices> pumpApp(
  WidgetTester tester, {
  AppUser? user = testUser,
  List<Memo> memos = const [],
  Size size = const Size(420, 860),
  DateTime? memoClock,
  void Function(FakeServices fakes)? setUp,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fakes = FakeServices(user: user, memos: memos, memoClock: memoClock);
  setUp?.call(fakes);
  await tester.pumpWidget(SoriNoteApp(services: fakes.services));
  await tester.pumpAndSettle();
  return fakes;
}

/// 아래 탭으로 이동한다(홈·기록·검색·일정·설정).
Future<void> goTab(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(Key('tab-$label')));
  await tester.pumpAndSettle();
}
