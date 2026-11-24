import 'dart:math';

import 'cards.dart';
import 'game_mode.dart';
import 'schieber.dart';

/// Schnittstelle für alle, die an einem Sitz Entscheidungen treffen.
/// Computergegner jetzt, später auch WLAN-Mitspieler.
abstract class JassBot {
  /// Spielart wählen. Gibt null zurück, um zu schieben (nur wenn erlaubt).
  GameMode? chooseMode(PlayerView view, {required bool canSchieben});

  /// Eine der erlaubten Karten ([PlayerView.legal]) wählen.
  JassCard chooseCard(PlayerView view);
}

/// Stufe 1 «Anfänger»: spielt eine zufällige erlaubte Karte.
class RandomBot implements JassBot {
  RandomBot([Random? rng]) : _rng = rng ?? Random();
  final Random _rng;

  @override
  GameMode? chooseMode(PlayerView view, {required bool canSchieben}) {
    // Farbe mit den meisten Karten wird Trumpf.
    final counts = {
      for (final s in Suit.values) s: view.hand.where((c) => c.suit == s).length
    };
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return GameMode.trump(best.key);
  }

  @override
  JassCard chooseCard(PlayerView view) =>
      view.legal[_rng.nextInt(view.legal.length)];
}

/// Stufe 2 «Stammtisch»: spielt nach Faustregeln wie ein Mensch.
/// Sieht nur die eigenen Karten und was schon gespielt wurde.
class RuleBot implements JassBot {
  RuleBot([Random? rng]) : _rng = rng ?? Random();
  final Random _rng;

  // ---------------------------------------------------------------- Trumpf

  /// Grobe Schätzung, wie gut eine Hand für eine Spielart ist.
  static double handValue(List<JassCard> hand, GameMode mode) {
    var v = 0.0;
    if (mode.isTrump) {
      final t = mode.trumpSuit!;
      final trumps = hand.where((c) => c.suit == t).toList();
      final hasJ = trumps.any((c) => c.rank == Rank.jack);
      final has9 = trumps.any((c) => c.rank == Rank.nine);
      if (hasJ) v += 26;
      if (has9) v += hasJ ? 16 : 11;
      if (trumps.any((c) => c.rank == Rank.ace)) v += 8;
      v += trumps.length * 7;
      if (trumps.length <= 2) v -= 20;
      for (final s in Suit.values.where((s) => s != t)) {
        final cs = hand.where((c) => c.suit == s).toList();
        if (cs.any((c) => c.rank == Rank.ace)) {
          v += 9;
          if (cs.any((c) => c.rank == Rank.king)) v += 4;
        }
        if (cs.isEmpty) v += 4; // kann früh stechen
      }
    } else {
      final up = mode.type == ModeType.obenabe;
      final top = up ? Rank.ace : Rank.six;
      final second = up ? Rank.king : Rank.seven;
      final third = up ? Rank.queen : Rank.eight;
      for (final s in Suit.values) {
        final cs = hand.where((c) => c.suit == s).toList();
        final hasTop = cs.any((c) => c.rank == top);
        final has2 = cs.any((c) => c.rank == second);
        final has3 = cs.any((c) => c.rank == third);
        if (hasTop) {
          v += 15;
          if (has2) v += 9;
          if (has2 && has3) v += 6;
          v += (cs.length - 1) * 2.5;
        } else if (has2 && cs.length >= 2) {
          v += 3;
        } else {
          v -= cs.length * 1.5;
        }
      }
    }
    return v;
  }

  @override
  GameMode? chooseMode(PlayerView view, {required bool canSchieben}) {
    GameMode? best;
    var bestValue = double.negativeInfinity;
    for (final m in GameMode.all) {
      final v = handValue(view.hand, m) + _rng.nextDouble();
      if (v > bestValue) {
        bestValue = v;
        best = m;
      }
    }
    if (canSchieben && bestValue < 62) return null;
    return best;
  }

  // ---------------------------------------------------------------- Karten

  @override
  JassCard chooseCard(PlayerView view) {
    final legal = view.legal;
    if (legal.length == 1) return legal.first;
    final mode = view.mode!;
    if (view.trick.isEmpty) return _lead(view, mode);
    return _follow(view, mode);
  }

  /// Ist [c] die höchste noch nicht gespielte Karte ihrer Farbe («Bock»)?
  bool _isBock(JassCard c, PlayerView view, GameMode mode) {
    final gone = {...view.playedCards, ...view.hand};
    for (final r in Rank.values) {
      final other = JassCard(c.suit, r);
      if (other == c || gone.contains(other)) continue;
      if (mode.strengthInSuit(other) > mode.strengthInSuit(c)) return false;
    }
    return true;
  }

  int _trumpsOutstanding(PlayerView view, GameMode mode) {
    if (!mode.isTrump) return 0;
    final known = {...view.playedCards, ...view.hand};
    return Rank.values
        .where((r) => !known.contains(JassCard(mode.trumpSuit!, r)))
        .length;
  }

  JassCard _lowest(List<JassCard> cards, GameMode mode) {
    return cards.reduce((a, b) {
      final pa = mode.points(a) * 10 + mode.strengthInSuit(a) +
          (mode.isTrumpCard(a) ? 50 : 0);
      final pb = mode.points(b) * 10 + mode.strengthInSuit(b) +
          (mode.isTrumpCard(b) ? 50 : 0);
      return pa <= pb ? a : b;
    });
  }

  JassCard _lead(PlayerView view, GameMode mode) {
    final legal = view.legal;
    final myTeamChose = teamOf(view.chooser) == teamOf(view.seat);

    if (mode.isTrump) {
      final trumps = legal.where(mode.isTrumpCard).toList();
      // Trumpf ziehen, wenn wir Trumpf gemacht haben und noch Trümpfe draussen sind.
      if (myTeamChose && trumps.isNotEmpty && _trumpsOutstanding(view, mode) > 0) {
        final bockTrump = trumps.where((c) => _isBock(c, view, mode)).toList();
        if (bockTrump.isNotEmpty) return bockTrump.first;
        if (trumps.length >= 3) return _lowest(trumps, mode);
      }
      // Böcke in Nebenfarben spielen, solange die Gegner wenig Trumpf haben.
      final bocks = legal
          .where((c) => !mode.isTrumpCard(c) && _isBock(c, view, mode))
          .toList();
      if (bocks.isNotEmpty &&
          (myTeamChose || _trumpsOutstanding(view, mode) <= 1)) {
        return bocks.first;
      }
      final nonTrump = legal.where((c) => !mode.isTrumpCard(c)).toList();
      if (nonTrump.isNotEmpty) return _lowest(nonTrump, mode);
      return _lowest(legal, mode);
    }

    // Obenabe / Undenufe: Böcke abholen, sonst eine kleine Karte.
    final bocks = legal.where((c) => _isBock(c, view, mode)).toList();
    if (bocks.isNotEmpty) {
      bocks.sort((a, b) => mode.points(b).compareTo(mode.points(a)));
      return bocks.first;
    }
    // Aus der längsten Farbe klein anspielen.
    final bySuit = <Suit, List<JassCard>>{};
    for (final c in legal) {
      bySuit.putIfAbsent(c.suit, () => []).add(c);
    }
    final longest =
        bySuit.values.reduce((a, b) => a.length >= b.length ? a : b);
    return _lowest(longest, mode);
  }

  JassCard _follow(PlayerView view, GameMode mode) {
    final legal = view.legal;
    final trick = view.trick;
    final lead = trick.first.suit;
    final winIdx = mode.winningIndex(trick);
    final winningCard = trick[winIdx];
    final winningSeat = view.trickSeats[winIdx];
    final partnerWins = teamOf(winningSeat) == teamOf(view.seat);
    final isLast = trick.length == 3;
    final trickPoints = trick.fold<int>(0, (s, c) => s + mode.points(c));

    final winners =
        legal.where((c) => mode.beats(c, winningCard, lead)).toList();

    if (partnerWins) {
      final safe = isLast ||
          (mode.isTrumpCard(winningCard) &&
              _isBock(winningCard, view, mode)) ||
          (!mode.isTrumpCard(winningCard) &&
              _isBock(winningCard, view, mode) &&
              _trumpsOutstanding(view, mode) == 0);
      if (safe) return _schmieren(legal, mode);
      // Partner liegt vorne, aber unsicher: lieber nichts Wertvolles opfern.
      return _lowest(legal, mode);
    }

    if (winners.isNotEmpty) {
      // Billigste Karte nehmen, die den Stich holt.
      final nonTrumpWinners =
          winners.where((c) => !mode.isTrumpCard(c)).toList();
      if (nonTrumpWinners.isNotEmpty) {
        if (isLast || _isBock(_strongest(nonTrumpWinners, mode), view, mode)) {
          return isLast
              ? _cheapestWinner(nonTrumpWinners, mode)
              : _strongest(nonTrumpWinners, mode);
        }
      }
      final trumpWinners = winners.where(mode.isTrumpCard).toList();
      final worthStechen = trickPoints >= 10 || isLast && trickPoints > 0;
      if (trumpWinners.isNotEmpty && worthStechen) {
        // Puur und Nell nur einsetzen, wenn es sich wirklich lohnt.
        final cheap = trumpWinners
            .where((c) => c.rank != Rank.jack && c.rank != Rank.nine)
            .toList();
        if (cheap.isNotEmpty) return _cheapestWinner(cheap, mode);
        if (trickPoints >= 15) return _cheapestWinner(trumpWinners, mode);
      }
      if (nonTrumpWinners.isNotEmpty && trickPoints >= 10) {
        return _cheapestWinner(nonTrumpWinners, mode);
      }
    }
    // Stich verloren: möglichst wenig Punkte abgeben.
    final nonTrump = legal.where((c) => !mode.isTrumpCard(c)).toList();
    return _lowest(nonTrump.isNotEmpty ? nonTrump : legal, mode);
  }

  JassCard _strongest(List<JassCard> cards, GameMode mode) => cards
      .reduce((a, b) => mode.strengthInSuit(a) >= mode.strengthInSuit(b) ? a : b);

  JassCard _cheapestWinner(List<JassCard> cards, GameMode mode) =>
      cards.reduce((a, b) {
        final ka = mode.points(a) * 10 + mode.strengthInSuit(a);
        final kb = mode.points(b) * 10 + mode.strengthInSuit(b);
        return ka <= kb ? a : b;
      });

  /// Dem Partner Punkte zuspielen, ohne Puur oder Nell herzugeben.
  JassCard _schmieren(List<JassCard> legal, GameMode mode) {
    final candidates = legal
        .where((c) =>
            !(mode.isTrumpCard(c) && (c.rank == Rank.jack || c.rank == Rank.nine)))
        .toList();
    final pool = candidates.isNotEmpty ? candidates : legal;
    return pool.reduce((a, b) {
      // Ein Ass in Obenabe/Trumpf ist oft selbst ein Bock: 10er bevorzugen.
      int score(JassCard c) =>
          mode.points(c) * 2 - (mode.isTrumpCard(c) ? 15 : 0) -
          (c.rank == Rank.ace && mode.type != ModeType.undenufe ? 8 : 0);
      return score(a) >= score(b) ? a : b;
    });
  }
}
