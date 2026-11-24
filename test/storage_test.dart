import 'package:flutter_test/flutter_test.dart';
import 'package:jass/ui/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Statistik zählt Siege und Niederlagen je Stufe', () async {
    SharedPreferences.setMockInitialValues({});
    await Storage.recordResult('profi', won: true);
    await Storage.recordResult('profi', won: false);
    await Storage.recordResult('profi', won: true);
    await Storage.recordResult('anfaenger', won: true);
    final s = await Storage.loadStats();
    expect(s['profi'], [2, 1]);
    expect(s['anfaenger'], [1, 0]);
    expect(s['stammtisch'], isNull);
  });

  test('Kaputter Spielstand wird verworfen statt abzustürzen', () async {
    SharedPreferences.setMockInitialValues({'laufendes_spiel_v1': '{kaputt'});
    expect(await Storage.loadGame(), isNull);
  });
}
