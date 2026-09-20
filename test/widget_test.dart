// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memoma3/main.dart';

void main() {
  testWidgets('App renders main screen and top action bar',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(child: Memoma3App()),
    );

    await tester.pumpAndSettle();

    // 上部アクションバーにUndo/保存/読み込みアイコンが表示される。
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.save), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);

    // オブジェクト件数が表示される。
    expect(find.text('オブジェクト: 0'), findsOneWidget);
  });
}
