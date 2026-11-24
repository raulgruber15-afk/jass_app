import 'dart:math';

import 'bot.dart';
import 'cards.dart';
import 'game_mode.dart';
import 'rules.dart';
import 'schieber.dart';

/// Stufe 3 «Profi»: merkt sich alle gespielten Karten, schliesst daraus,
/// wer welche Farbe nicht mehr hat, und spielt im Kopf viele mögliche
/// Kartenverteilungen bis zum Rundenende durch (Monte-Carlo-Simulation).
/// Gewählt wird die Karte mit dem besten Durchschnitt.
///
/// Schummelt nicht: Sieht nur die eigene Hand und was auf dem Tisch lag.
class ProfiBot implements JassBot {
  ProfiBot({Random? rng, this.budget = 480})
      : _rng = rng ?? Random(),
        _policy = RuleBot(rng ?? Random());

  final Random _rng;

  /// Anzahl durchgespielter Runden pro Entscheidung (mehr = stärker, langsamer).
  final int budget;

  /// So spielen die gedachten Mitspieler in der Simulation.
  final RuleBot _policy;

  // ---------------------------------------------------------------- Trumpf

  @override
  GameMode? chooseMode(PlayerView view, {required bool canSchieben}) {
    final unknown =
        fullDeck.where((c) => !view.hand.contains(c)).toList();
    final perMode = max(12, budget ~/ 8);
    GameMode? best;
    var bestScore = double.negativeInfinity;
    var bestOwn = 0.0;
    for (final m in GameMode.all) {
      // Vorauswahl: offensichtlich schlechte Spielarten nicht durchrechnen.
      if (RuleBot.handValue(view.hand, m) < 20) continue;
      var sumDiff = 0.0;
      var sumOwn = 0.0;
      for (var i = 0; i < perMode; i++) {
        final deck = List.of(unknown)..shuffle(_rng);
        final hands = List.generate(4, (_) => <JassCard>[]);
        hands[view.seat] = List.of(view.hand);
        var k = 0;
        for (var s = 0; s < 4; s++) {
          if (s == view.seat) continue;
          hands[s] = deck.sublist(k, k + 9);
          k += 9;
        }
        final pts = _simulate(
          hands: hands,
          trick: [],
          trickSeats: [],
          toAct: view.chooser,
          mode: m,
          chooser: view.chooser,
          played: [],
          pastWinners: [],
        );
        final me = teamOf(view.seat);
        sumOwn += pts[me];
        sumDiff += pts[me] - pts[1 - me];
      }
      // Multiplikator zählt nicht voll: hohe Faktoren sind auch riskanter.
      final score = sumDiff / perMode;
      if (score > bestScore) {
        bestScore = score;
        best = m;
        bestOwn = sumOwn / perMode;
      }
    }
    best ??= _policy.chooseMode(view, canSchieben: false);
    if (canSchieben && bestOwn < 82) return null;
    return best;
  }

  // ---------------------------------------------------------------- Karten

  @override
  JassCard chooseCard(PlayerView view) {
    final legal = view.legal;
    if (legal.length == 1) return legal.first;
    final mode = view.mode!;
    final me = teamOf(view.seat);

    final constraints = _inferConstraints(view, mode);
    final played = [...view.playedCards];
    final unknown = fullDeck
        .where((c) => !view.hand.contains(c) && !played.contains(c))
        .toList();
    final pastWinners = [for (final t in view.pastTricks) t.winner];

    final samples = max(8, budget ~/ legal.length);
    final totals = List<double>.filled(legal.length, 0);
    for (var i = 0; i < samples; i++) {
      final hands = _sampleHands(view, unknown, constraints);
      for (var j = 0; j < legal.length; j++) {
        final h = [for (final x in hands) List.of(x)];
        final card = legal[j];
        h[view.seat].remove(card);
        final trick = [...view.trick, card];
        final seats = [...view.trickSeats, view.seat];
        final pts = _simulate(
          hands: h,
          trick: trick,
          trickSeats: seats,
          toAct: nextSeat(view.seat),
          mode: mode,
          chooser: view.chooser,
          played: [...played, card],
          pastWinners: pastWinners,
        );
        totals[j] += pts[me] - pts[1 - me];
      }
    }
    var bestIdx = 0;
    for (var j = 1; j < legal.length; j++) {
      if (totals[j] > totals[bestIdx]) bestIdx = j;
    }
    return legal[bestIdx];
  }

  /// Welche Farben haben die anderen sicher nicht mehr?
  /// voids[seat] enthält Farben, die der Sitz nicht hat.
  /// noTrumpExceptPuur: Sitz hat höchstens noch den Trumpf-Buben.
  _Constraints _inferConstraints(PlayerView view, GameMode mode) {
    final c = _Constraints();
    void scan(List<JassCard> cards, List<int> seats) {
      if (cards.isEmpty) return;
      final lead = cards.first.suit;
      for (var i = 1; i < cards.length; i++) {
        final card = cards[i];
        final seat = seats[i];
        if (card.suit == lead) continue;
        if (mode.isTrump && lead == mode.trumpSuit) {
          c.noTrumpExceptPuur.add(seat);
        } else if (!mode.isTrumpCard(card)) {
          c.voids[seat].add(lead);
        }
      }
    }

    for (final t in view.pastTricks) {
      scan(t.cards, t.seats);
    }
    scan(view.trick, view.trickSeats);
    return c;
  }

  bool _allowed(_Constraints c, int seat, JassCard card, GameMode mode) {
    if (c.voids[seat].contains(card.suit)) return false;
    if (c.noTrumpExceptPuur.contains(seat) &&
        mode.isTrumpCard(card) &&
        card.rank != Rank.jack) {
      return false;
    }
    return true;
  }

  /// Unbekannte Karten zufällig, aber passend zu dem, was man weiss,
  /// auf die anderen drei Sitze verteilen.
  List<List<JassCard>> _sampleHands(
      PlayerView view, List<JassCard> unknown, _Constraints c) {
    final mode = view.mode!;
    final others = [for (var s = 0; s < 4; s++) if (s != view.seat) s];
    for (var attempt = 0; attempt < 30; attempt++) {
      final hands = List.generate(4, (_) => <JassCard>[]);
      hands[view.seat] = List.of(view.hand);
      final need = List.of(view.handSizes);
      final cards = List.of(unknown)..shuffle(_rng);
      // Karten mit wenig möglichen Besitzern zuerst verteilen.
      cards.sort((a, b) {
        int n(JassCard x) =>
            others.where((s) => _allowed(c, s, x, mode)).length;
        return n(a).compareTo(n(b));
      });
      var ok = true;
      for (final card in cards) {
        final options = others
            .where((s) => hands[s].length < need[s] && _allowed(c, s, card, mode))
            .toList();
        if (options.isEmpty) {
          ok = false;
          break;
        }
        // Gewichtet nach freien Plätzen.
        final free = options.map((s) => need[s] - hands[s].length).toList();
        var r = _rng.nextInt(free.reduce((a, b) => a + b));
        var pick = options.last;
        for (var i = 0; i < options.length; i++) {
          r -= free[i];
          if (r < 0) {
            pick = options[i];
            break;
          }
        }
        hands[pick].add(card);
      }
      if (ok) return hands;
    }
    // Notfall: ohne Einschränkungen verteilen.
    final hands = List.generate(4, (_) => <JassCard>[]);
    hands[view.seat] = List.of(view.hand);
    final cards = List.of(unknown)..shuffle(_rng);
    var k = 0;
    for (final s in others) {
      hands[s] = cards.sublist(k, k + view.handSizes[s]);
      k += view.handSizes[s];
    }
    return hands;
  }

  /// Spielt die Runde ab dem gegebenen Stand zu Ende (alle Sitze nach
  /// Faustregeln) und gibt die ab jetzt gewonnenen Punkte je Team zurück.
  List<int> _simulate({
    required List<List<JassCard>> hands,
    required List<JassCard> trick,
    required List<int> trickSeats,
    required int toAct,
    required GameMode mode,
    required int chooser,
    required List<JassCard> played,
    required List<int> pastWinners,
  }) {
    final pts = [0, 0];
    final winners = List.of(pastWinners);
    var seat = toAct;
    final t = List.of(trick);
    final ts = List.of(trickSeats);
    final seen = List.of(played);
    while (winners.length < 9) {
      if (t.length == 4) {
        final w = ts[mode.winningIndex(t)];
        var p = t.fold<int>(0, (s, c) => s + mode.points(c));
        winners.add(w);
        if (winners.length == 9) p += 5;
        pts[teamOf(w)] += p;
        t.clear();
        ts.clear();
        seat = w;
        continue;
      }
      final hand = hands[seat];
      final legal = legalCards(hand, t, mode);
      final card = legal.length == 1
          ? legal.first
          : _policy.chooseCard(PlayerView(
              seat: seat,
              hand: hand,
              trick: t,
              trickSeats: ts,
              mode: mode,
              chooser: chooser,
              geschoben: false,
              playedCards: seen,
              legal: legal,
              handSizes: const [9, 9, 9, 9],
            ));
      hand.remove(card);
      t.add(card);
      ts.add(seat);
      seen.add(card);
      seat = nextSeat(seat);
    }
    // Match: alle neun Stiche für ein Team.
    for (final team in [0, 1]) {
      if (winners.every((w) => teamOf(w) == team)) pts[team] += 100;
    }
    return pts;
  }
}

class _Constraints {
  final List<Set<Suit>> voids = List.generate(4, (_) => <Suit>{});
  final Set<int> noTrumpExceptPuur = {};
}
