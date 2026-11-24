import 'package:flutter_test/flutter_test.dart';
import 'package:jass/engine/game_mode.dart';
import 'package:jass/engine/schieber.dart';
import 'package:jass/engine/cards.dart';
import 'package:jass/ui/game_controller.dart';

/// Spielt eine Runde im Herumreich-Modus durch und prüft, dass nie
/// jemand die Karten einer anderen Person sieht.
Future<void> playRound(WidgetTester tester, GameController c) async {
  var steps = 0;
  while (c.game.phase != Phase.roundOver && c.game.phase != Phase.gameOver) {
    expect(++steps, lessThan(500));
    if (c.handoverTo != null) {
      c.confirmHandover();
      continue;
    }
    // Sichtbare Hand gehört immer der Person, die zuletzt bestätigt hat,
    // und nur diese darf handeln.
    if (c.viewerToAct) {
      expect(c.handHidden, isFalse);
      expect(c.game.toAct, c.viewer);
      if (c.game.phase == Phase.chooseMode) {
        c.humanChooseMode(const GameMode.trump(Suit.herz));
      } else {
        c.humanPlay(c.game.legalFor(c.viewer).first);
      }
      continue;
    }
    await tester.pump(const Duration(seconds: 2));
  }
}

void main() {
  testWidgets('vier Personen: vor jedem Zug Sichtschutz', (tester) async {
    final c = GameController(
      settings: const SchieberSettings(targetPoints: 100000),
      fast: true,
      seats: const [
        SeatSetup(name: 'Anna', human: true),
        SeatSetup(name: 'Beat', human: true),
        SeatSetup(name: 'Carla', human: true),
        SeatSetup(name: 'Dani', human: true),
      ],
    )..start();
    expect(c.handoverTo, c.game.chooser);
    expect(c.viewerToAct, isFalse);

    var handovers = 0;
    c.addListener(() {
      if (c.handoverTo != null) handovers++;
    });
    await playRound(tester, c);
    expect(c.game.phase, Phase.roundOver);
    // Vor jeder der 36 Karten ein Sichtschutz (der erste vor dem Trumpf ist schon vor dem Zählen da).
    expect(handovers, greaterThanOrEqualTo(36));
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('zwei Personen gegen zwei Computer', (tester) async {
    final c = GameController(
      settings: const SchieberSettings(targetPoints: 100000),
      fast: true,
      seats: const [
        SeatSetup(name: 'Anna', human: true),
        SeatSetup(name: 'Bot1', human: false),
        SeatSetup(name: 'Carla', human: true),
        SeatSetup(name: 'Bot2', human: false),
      ],
    )..start();
    await playRound(tester, c);
    expect(c.game.phase, Phase.roundOver);
    expect(c.teamLabel(0), 'Anna & Carla');
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('allein: kein Sichtschutz', (tester) async {
    final c = GameController(
      settings: const SchieberSettings(targetPoints: 100000),
      fast: true,
    )..start();
    var covered = false;
    c.addListener(() {
      if (c.handoverTo != null || c.handHidden) covered = true;
    });
    await playRound(tester, c);
    expect(covered, isFalse);
    expect(c.teamLabel(0), 'Wir');
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  });
}
