import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jass/engine/bot.dart';
import 'package:jass/engine/cards.dart';
import 'package:jass/engine/game_mode.dart';
import 'package:jass/engine/profi_bot.dart';
import 'package:jass/engine/rules.dart';
import 'package:jass/engine/schieber.dart';

JassCard c(Suit s, Rank r) => JassCard(s, r);

void main() {
  group('Kartenpunkte', () {
    test('jede Spielart hat 152 Kartenpunkte', () {
      for (final m in GameMode.all) {
        final sum = fullDeck.fold<int>(0, (s, x) => s + m.points(x));
        expect(sum, 152, reason: m.label);
      }
    });

    test('Puur 20, Nell 14 im Trumpf', () {
      const m = GameMode.trump(Suit.herz);
      expect(m.points(c(Suit.herz, Rank.jack)), 20);
      expect(m.points(c(Suit.herz, Rank.nine)), 14);
      expect(m.points(c(Suit.pik, Rank.jack)), 2);
      expect(m.points(c(Suit.pik, Rank.eight)), 0);
    });

    test('Undenufe: 6 zählt 11, Ass 0, 8 zählt 8', () {
      const m = GameMode.undenufe();
      expect(m.points(c(Suit.pik, Rank.six)), 11);
      expect(m.points(c(Suit.pik, Rank.ace)), 0);
      expect(m.points(c(Suit.pik, Rank.eight)), 8);
    });
  });

  group('Stich', () {
    test('Puur schlägt Nell schlägt Ass im Trumpf', () {
      const m = GameMode.trump(Suit.karo);
      final t = [
        c(Suit.karo, Rank.ace),
        c(Suit.karo, Rank.nine),
        c(Suit.karo, Rank.jack),
        c(Suit.karo, Rank.king),
      ];
      expect(m.winningIndex(t), 2);
    });

    test('kleiner Trumpf sticht Ass einer anderen Farbe', () {
      const m = GameMode.trump(Suit.karo);
      final t = [
        c(Suit.pik, Rank.ace),
        c(Suit.karo, Rank.six),
        c(Suit.pik, Rank.king),
        c(Suit.herz, Rank.ace),
      ];
      expect(m.winningIndex(t), 1);
    });

    test('nicht angegebene Farbe gewinnt nie', () {
      const m = GameMode.obenabe();
      final t = [
        c(Suit.pik, Rank.six),
        c(Suit.herz, Rank.ace),
        c(Suit.pik, Rank.seven),
        c(Suit.kreuz, Rank.ace),
      ];
      expect(m.winningIndex(t), 2);
    });

    test('Undenufe: tiefste Karte gewinnt', () {
      const m = GameMode.undenufe();
      final t = [
        c(Suit.pik, Rank.ten),
        c(Suit.pik, Rank.six),
        c(Suit.pik, Rank.ace),
        c(Suit.pik, Rank.seven),
      ];
      expect(m.winningIndex(t), 1);
    });
  });

  group('Erlaubte Karten', () {
    const m = GameMode.trump(Suit.herz);

    test('Farbe angeben oder stechen', () {
      final hand = [
        c(Suit.pik, Rank.seven),
        c(Suit.herz, Rank.six),
        c(Suit.kreuz, Rank.ace),
      ];
      final legal = legalCards(hand, [c(Suit.pik, Rank.king)], m);
      expect(legal.toSet(),
          {c(Suit.pik, Rank.seven), c(Suit.herz, Rank.six)});
    });

    test('Farbe nicht vorhanden: alles erlaubt', () {
      final hand = [c(Suit.karo, Rank.seven), c(Suit.kreuz, Rank.ace)];
      expect(legalCards(hand, [c(Suit.pik, Rank.king)], m).length, 2);
    });

    test('Trumpf ausgespielt: Trumpf angeben', () {
      final hand = [c(Suit.herz, Rank.seven), c(Suit.kreuz, Rank.ace)];
      expect(legalCards(hand, [c(Suit.herz, Rank.king)], m),
          [c(Suit.herz, Rank.seven)]);
    });

    test('Puur muss nicht angegeben werden', () {
      final hand = [c(Suit.herz, Rank.jack), c(Suit.kreuz, Rank.ace)];
      expect(legalCards(hand, [c(Suit.herz, Rank.king)], m).length, 2);
    });

    test('Untertrumpfen verboten', () {
      final hand = [
        c(Suit.herz, Rank.six),
        c(Suit.herz, Rank.ace),
        c(Suit.kreuz, Rank.seven),
      ];
      final trick = [c(Suit.pik, Rank.ace), c(Suit.herz, Rank.ten)];
      expect(legalCards(hand, trick, m).toSet(),
          {c(Suit.herz, Rank.ace), c(Suit.kreuz, Rank.seven)});
    });

    test('Untertrumpfen erlaubt, wenn nur noch Trümpfe', () {
      final hand = [c(Suit.herz, Rank.six), c(Suit.herz, Rank.seven)];
      final trick = [c(Suit.pik, Rank.ace), c(Suit.herz, Rank.ten)];
      expect(legalCards(hand, trick, m).length, 2);
    });
  });

  group('Weis', () {
    test('Dreiblatt und Vierblatt', () {
      final hand = [
        c(Suit.herz, Rank.six),
        c(Suit.herz, Rank.seven),
        c(Suit.herz, Rank.eight),
        c(Suit.pik, Rank.ten),
        c(Suit.pik, Rank.jack),
        c(Suit.pik, Rank.queen),
        c(Suit.pik, Rank.king),
        c(Suit.kreuz, Rank.ace),
        c(Suit.karo, Rank.ace),
      ];
      final w = findWeis(hand);
      expect(w.map((x) => x.points).toList()..sort(), [20, 50]);
    });

    test('vier Buben 200, vier Neuner 150, vier Sechser nichts', () {
      final hand = [
        for (final s in Suit.values) c(s, Rank.jack),
        for (final s in Suit.values) c(s, Rank.six),
        c(Suit.herz, Rank.ace),
      ];
      final w = findWeis(hand);
      expect(w.length, 1);
      expect(w.first.points, 200);
    });

    test('bei gleichen Punkten zählt die höhere Folge', () {
      const m = GameMode.trump(Suit.kreuz);
      final low = Weis([
        c(Suit.pik, Rank.six),
        c(Suit.pik, Rank.seven),
        c(Suit.pik, Rank.eight)
      ], 20, isSequence: true);
      final high = Weis([
        c(Suit.herz, Rank.queen),
        c(Suit.herz, Rank.king),
        c(Suit.herz, Rank.ace)
      ], 20, isSequence: true);
      expect(compareWeis(high, low, m), greaterThan(0));
    });
  });

  group('Ganzes Spiel', () {
    test('jede Runde ergibt 157 Punkte (ohne Weis/Stöck/Match)', () {
      final rng = Random(7);
      for (var game = 0; game < 200; game++) {
        final g = SchieberGame(
          settings: const SchieberSettings(useMultipliers: false, targetPoints: 100000),
          random: rng,
        );
        g.start();
        final bots = List.generate(4, (_) => RuleBot(rng));
        _playRound(g, bots);
        final r = g.lastResult!;
        final cards = r.cardPoints[0] + r.cardPoints[1];
        expect(cards, r.matchTeam == null ? 157 : 257);
      }
    });

    test('Spiel endet, sobald ein Team das Ziel erreicht', () {
      final rng = Random(3);
      final g = SchieberGame(
          settings: const SchieberSettings(targetPoints: 1000), random: rng);
      g.start();
      final bots = List.generate(4, (i) => i.isEven ? RuleBot(rng) : RandomBot(rng));
      var rounds = 0;
      while (g.phase != Phase.gameOver) {
        if (g.phase == Phase.roundOver) g.nextRound();
        _playRound(g, bots);
        rounds++;
        expect(rounds, lessThan(60));
      }
      expect(g.winnerTeam, isNotNull);
      expect(g.totals[g.winnerTeam!], greaterThanOrEqualTo(1000));
    });

    test('Stammtisch-Bot schlägt Zufalls-Bot deutlich', () {
      final rng = Random(11);
      var ruleTeam = 0;
      var randomTeam = 0;
      for (var i = 0; i < 300; i++) {
        final g = SchieberGame(
            settings: const SchieberSettings(targetPoints: 1 << 30), random: rng);
        g.start();
        final bots = List.generate(4, (s) => s.isEven ? RuleBot(rng) : RandomBot(rng));
        _playRound(g, bots);
        ruleTeam += g.totals[0];
        randomTeam += g.totals[1];
      }
      expect(ruleTeam, greaterThan(randomTeam * 1.3));
    });

    test('Profi schlägt Stammtisch (gleiche Karten, Teams vertauscht)', () {
      var profi = 0;
      var rule = 0;
      for (var i = 0; i < 12; i++) {
        for (final pt in [0, 1]) {
          final g = SchieberGame(
              settings: const SchieberSettings(targetPoints: 1 << 30, useMultipliers: false),
              random: Random(100 + i));
          g.start();
          final bots = List<JassBot>.generate(4, (s) => teamOf(s) == pt
              ? ProfiBot(rng: Random(s), budget: 150)
              : RuleBot(Random(s)));
          _playRound(g, bots);
          profi += g.totals[pt];
          rule += g.totals[1 - pt];
        }
      }
      expect(profi, greaterThan(rule));
    });

    test('Stöck wird gezählt', () {
      final g = SchieberGame(
          settings: const SchieberSettings(useMultipliers: false, targetPoints: 100000));
      final deck = List.of(fullDeck);
      // Sitz 0 bekommt alle Herz (inkl. König und Dame).
      final hands = [
        deck.where((x) => x.suit == Suit.herz).toList(),
        deck.where((x) => x.suit == Suit.pik).toList(),
        deck.where((x) => x.suit == Suit.kreuz).toList(),
        deck.where((x) => x.suit == Suit.karo).toList(),
      ];
      g.startWithHands(hands);
      g.chooseMode(const GameMode.trump(Suit.herz));
      expect(g.stoeckSeat, 0);
      final bots = List.generate(4, (_) => RuleBot(Random(1)));
      _playRound(g, bots);
      final r = g.lastResult!;
      expect(r.stoeckPoints[0], 20);
      expect(r.matchTeam, 0);
      // Neunblatt Herz (300) für Team 0, plus Neunblatt der anderen, aber
      // nur das Team mit dem höchsten Weis zählt: alle gleich lang, Herz
      // ist Trumpf, also Team 0.
      expect(r.weisPoints[0], 300 + 300); // Sitz 0 und Sitz 2 (Kreuz)
      expect(r.weisPoints[1], 0);
    });
  });
}

void _playRound(SchieberGame g, List<JassBot> bots) {
  while (g.phase != Phase.roundOver && g.phase != Phase.gameOver) {
    switch (g.phase) {
      case Phase.chooseMode:
        final seat = g.toAct;
        final m = bots[seat].chooseMode(g.viewFor(seat), canSchieben: g.canSchieben);
        if (m == null) {
          g.schieben();
        } else {
          g.chooseMode(m);
        }
      case Phase.playing:
        final seat = g.toAct;
        g.playCard(seat, bots[seat].chooseCard(g.viewFor(seat)));
      case Phase.trickComplete:
        g.collectTrick();
      default:
        break;
    }
  }
}
