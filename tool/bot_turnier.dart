// ignore_for_file: avoid_print
// Bot-Turnier: misst, ob eine KI-Stufe stärker ist.
// Aufruf: dart run tool/bot_turnier.dart [anzahl_runden]
// Jede Kartenverteilung wird zweimal gespielt, mit vertauschten Teams.
import 'dart:math';

import 'package:jass/engine/bot.dart';
import 'package:jass/engine/profi_bot.dart';
import 'package:jass/engine/schieber.dart';

void main(List<String> args) {
  final rounds = args.isEmpty ? 100 : int.parse(args.first);
  var profi = 0, rule = 0;
  final sw = Stopwatch()..start();
  var decisions = 0;
  for (var i = 0; i < rounds; i++) {
    for (final profiTeam in [0, 1]) {
      final g = SchieberGame(
          settings: const SchieberSettings(targetPoints: 1 << 30, useMultipliers: false),
          random: Random(i));
      g.start();
      final bots = List<JassBot>.generate(4,
          (s) => teamOf(s) == profiTeam ? ProfiBot(rng: Random(i * 7 + s), budget: int.parse(const String.fromEnvironment("B", defaultValue: "480"))) : RuleBot(Random(i * 7 + s)));
      while (g.phase != Phase.roundOver && g.phase != Phase.gameOver) {
        switch (g.phase) {
          case Phase.chooseMode:
            final m = bots[g.toAct].chooseMode(g.viewFor(g.toAct), canSchieben: g.canSchieben);
            m == null ? g.schieben() : g.chooseMode(m);
          case Phase.playing:
            if (bots[g.toAct] is ProfiBot) decisions++;
            g.playCard(g.toAct, bots[g.toAct].chooseCard(g.viewFor(g.toAct)));
          case Phase.trickComplete:
            g.collectTrick();
          default:
        }
      }
      profi += g.totals[profiTeam];
      rule += g.totals[1 - profiTeam];
    }
  }
  print('Profi: $profi  Stammtisch: $rule  Verhältnis: ${(profi / rule).toStringAsFixed(3)}');
  print('Zeit: ${sw.elapsedMilliseconds} ms, ~${(sw.elapsedMilliseconds / max(1, decisions)).toStringAsFixed(1)} ms pro Profi-Zug (inkl. Rest)');
}
