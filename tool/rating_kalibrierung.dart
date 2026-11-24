// ignore_for_file: avoid_print
// Misst die Stärke der Computerstufen auf der Skala der Jass-Wertung.
//
// Aufruf: dart run tool/rating_kalibrierung.dart [partien_je_paarung] [ziel]
//
// Gespielt werden ganze Partien (Standard: bis 2500, mit Multiplikatoren).
// Jede Kartenfolge (Seed) wird zweimal gespielt, mit vertauschten Teams.
// Ausgabe: mittlere «Striche»-Differenz je Paarung, daraus die Stärke mu
// relativ zu «Stammtisch» (= 0) und die Streuung (Glücksanteil).
import 'dart:math';

import 'package:jass/engine/bot.dart';
import 'package:jass/engine/profi_bot.dart';
import 'package:jass/engine/rating.dart';
import 'package:jass/engine/schieber.dart';

JassBot make(String kind, int seed) => switch (kind) {
  'A' => RandomBot(Random(seed)),
  'S' => RuleBot(Random(seed)),
  _ => ProfiBot(rng: Random(seed)),
};

/// Spielt eine Partie; Team 0 = [team0] (Sitze 0 und 2), Team 1 = [team1].
/// Rückgabe: Striche aus Sicht von Team 0.
double playGame(List<String> team0, List<String> team1, int seed, int target) {
  final g = SchieberGame(
    settings: SchieberSettings(targetPoints: target),
    random: Random(seed),
  );
  final bots = [
    make(team0[0], seed * 11 + 0),
    make(team1[0], seed * 11 + 1),
    make(team0[1], seed * 11 + 2),
    make(team1[1], seed * 11 + 3),
  ];
  g.start();
  while (g.phase != Phase.gameOver) {
    switch (g.phase) {
      case Phase.chooseMode:
        final m = bots[g.toAct].chooseMode(
          g.viewFor(g.toAct),
          canSchieben: g.canSchieben,
        );
        m == null ? g.schieben() : g.chooseMode(m);
      case Phase.playing:
        g.playCard(g.toAct, bots[g.toAct].chooseCard(g.viewFor(g.toAct)));
      case Phase.trickComplete:
        g.collectTrick();
      case Phase.roundOver:
        g.nextRound();
      default:
    }
  }
  return JassRating.marginFromPoints(
    g.totals[0],
    g.totals[1],
    target,
    won: g.winnerTeam == 0,
  );
}

void main(List<String> args) {
  final n = args.isNotEmpty ? int.parse(args[0]) : 40;
  final target = args.length > 1 ? int.parse(args[1]) : 2500;
  // Paarungen wie in der App: Person + Partner gleicher Stufe gegen zwei Computer.
  // Ersatz für die Person ist ein Computer einer anderen Stufe.
  const pairings = [
    (['A', 'A'], ['S', 'S']),
    (['P', 'P'], ['S', 'S']),
    (['A', 'S'], ['S', 'S']),
    (['P', 'S'], ['S', 'S']),
    (['S', 'A'], ['A', 'A']),
    (['S', 'P'], ['P', 'P']),
  ];
  final sw = Stopwatch()..start();
  for (final (a, b) in pairings) {
    final ms = <double>[];
    var wins = 0;
    for (var i = 0; i < n; i++) {
      final m1 = playGame(a, b, i, target);
      final m2 = -playGame(b, a, i, target);
      ms.addAll([m1, m2]);
      wins += (m1 > 0 ? 1 : 0) + (m2 > 0 ? 1 : 0);
    }
    final mean = ms.reduce((x, y) => x + y) / ms.length;
    final sd = sqrt(
      ms.map((x) => (x - mean) * (x - mean)).reduce((x, y) => x + y) /
          (ms.length - 1),
    );
    print(
      '${a.join('+')} gegen ${b.join('+')}: Striche ${mean.toStringAsFixed(2)} '
      '± ${(sd / sqrt(ms.length)).toStringAsFixed(2)}, Streuung ${sd.toStringAsFixed(2)}, '
      'Siege ${(100 * wins / ms.length).toStringAsFixed(0)} %, '
      'Stärkedifferenz (Summe) ${(mean / JassRating.gain).toStringAsFixed(2)}  '
      '[${sw.elapsed.inSeconds} s]',
    );
  }
}
