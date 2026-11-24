import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jass/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Startseite: Spiel über mehrere Handys eröffnen', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(const JassApp());
    await t.pumpAndSettle();
    await t.tap(find.text('Mit Freunden'));
    await t.pumpAndSettle();
    await t.tap(find.text('Jeder sein Handy'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Raul');
    expect(find.text('Spiel eröffnen'), findsOneWidget);
    expect(find.text('Beitreten'), findsOneWidget);

    await t.runAsync(() async {
      await t.tap(find.text('Spiel eröffnen'));
      await t.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Ohne Mitspieler starten'), findsOneWidget);
    expect(find.text('Raul'), findsWidgets);
    expect(find.text('frei – Computer'), findsNWidgets(3));
  });
}
