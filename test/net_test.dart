import 'package:flutter_test/flutter_test.dart';
import 'package:jass/engine/cards.dart';
import 'package:jass/engine/game_mode.dart';
import 'package:jass/engine/schieber.dart';
import 'package:jass/net/net_game.dart';
import 'package:jass/ui/game_controller.dart';

/// Wartet, bis [cond] stimmt (echte Netzwerkverbindung über 127.0.0.1).
Future<void> until(bool Function() cond, {int seconds = 10}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('Zeit abgelaufen');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('QR-Code und eingetippte Adresse werden erkannt', () {
    final code = joinCode(['192.168.1.5', '172.20.10.1'], 47474);
    expect(parseJoinCode(code)!.$1, ['192.168.1.5', '172.20.10.1']);
    expect(parseJoinCode('192.168.1.7')!.$2, jassPort);
    expect(parseJoinCode('10.0.0.2:5000')!.$2, 5000);
    expect(parseJoinCode('hallo'), isNull);
  });

  test('Gastgeber und zwei Mitspieler spielen eine ganze Partie', () async {
    final host = JassHost(hostName: 'Raul', port: 0);
    expect(await host.open(), isTrue);
    final anna = JassGuest(name: 'Anna');
    final beni = JassGuest(name: 'Beni');
    expect(await anna.connect(['127.0.0.1'], host.boundPort), isTrue);
    await until(() => anna.seat != null);
    expect(await beni.connect(['127.0.0.1'], host.boundPort), isTrue);
    await until(() => beni.seat != null);
    expect(anna.seat, 2); // zuerst der Partner-Platz
    expect(beni.seat, 1);
    await until(() => anna.lobbyNames[1] == 'Beni');

    final hostCtrl = host.start(
      settings: const SchieberSettings(targetPoints: 300),
      level: BotLevel.anfaenger,
      fast: true,
    );
    await until(() => anna.ctrl != null && beni.ctrl != null);

    // Niemand sieht fremde Karten: Platzhalter statt echter Karten.
    final annaView = anna.ctrl!.game;
    expect(annaView.hands[2], hostCtrl.game.hands[2]);
    expect(annaView.hands[0].every((c) => c.id == 0), isTrue);
    expect(annaView.hands[0].length, 9);

    // Alle Menschen spielen automatisch die erste erlaubte Karte.
    final players = <int, GameController Function()>{
      0: () => hostCtrl,
      2: () => anna.ctrl!,
      1: () => beni.ctrl!,
    };
    var rounds = 0;
    final end = DateTime.now().add(const Duration(seconds: 120));
    while (hostCtrl.game.phase != Phase.gameOver) {
      if (DateTime.now().isAfter(end)) fail('Partie dauert zu lange');
      final g = hostCtrl.game;
      if (g.phase == Phase.roundOver) {
        rounds++;
        hostCtrl.nextRound();
      } else if (players.containsKey(g.toAct) &&
          (g.phase == Phase.chooseMode || g.phase == Phase.playing)) {
        final c = players[g.toAct]!();
        // Warten, bis das Handy den aktuellen Stand hat.
        if (c.game.toAct == g.toAct &&
            c.game.phase == g.phase &&
            c.game.trick.length == g.trick.length &&
            c.viewerToAct) {
          if (g.phase == Phase.chooseMode) {
            c.humanChooseMode(const GameMode.trump(Suit.herz));
          } else {
            c.humanPlay(c.game.legalFor(c.viewer).first);
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(rounds, greaterThan(0));
    await until(() => anna.ctrl!.game.phase == Phase.gameOver);
    expect(anna.ctrl!.game.totals, hostCtrl.game.totals);

    await anna.close();
    await beni.close();
    await host.close();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'Mitspieler weg: Computer übernimmt, beim Wiederkommen zurück',
    () async {
      final host = JassHost(hostName: 'Raul', port: 0);
      await host.open();
      final anna = JassGuest(name: 'Anna');
      await anna.connect(['127.0.0.1'], host.boundPort);
      await until(() => anna.seat != null);
      final ctrl = host.start(
        settings: const SchieberSettings(),
        level: BotLevel.anfaenger,
        fast: true,
      );
      await until(() => anna.ctrl != null);
      expect(ctrl.seats[2].remote, isTrue);

      await anna.close();
      await until(() => !ctrl.seats[2].human);

      final anna2 = JassGuest(name: 'anna');
      await anna2.connect(['127.0.0.1'], host.boundPort);
      await until(() => anna2.seat == 2 && ctrl.seats[2].remote);
      await until(() => anna2.ctrl != null);

      // Fremde ohne Platz kommen nicht mehr rein.
      final x = JassGuest(name: 'Xaver');
      await x.connect(['127.0.0.1'], host.boundPort);
      await until(() => x.problem != null);
      expect(x.problem, contains('läuft schon'));

      await anna2.close();
      await host.close();
    },
  );
}
