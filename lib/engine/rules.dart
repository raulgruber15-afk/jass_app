import 'cards.dart';
import 'game_mode.dart';

/// Welche Karten darf man aus [hand] spielen, wenn [trick] schon liegt?
///
/// Regeln (Schieber, offizielle Regeln):
/// * Farbe muss angegeben werden, wenn möglich.
/// * Trumpf darf man immer spielen, auch wenn man die Farbe hätte («stechen»).
/// * Wird Trumpf ausgespielt, muss man Trumpf angeben. Ausnahme: Ist der
///   Trumpf-Bube («Puur») der einzige Trumpf, muss man ihn nicht spielen.
/// * Untertrumpfen ist verboten: Hat schon jemand mit Trumpf gestochen, darf
///   man keinen tieferen Trumpf dazulegen, ausser man hat nur noch Trümpfe.
List<JassCard> legalCards(
    List<JassCard> hand, List<JassCard> trick, GameMode mode) {
  if (trick.isEmpty || hand.length <= 1) return List.of(hand);
  final lead = trick.first.suit;
  final sameSuit = hand.where((c) => c.suit == lead).toList();

  if (!mode.isTrump) {
    return sameSuit.isNotEmpty ? sameSuit : List.of(hand);
  }

  final trump = mode.trumpSuit!;
  final trumps = hand.where((c) => c.suit == trump).toList();

  if (lead == trump) {
    final onlyPuur = trumps.length == 1 && trumps.first.rank == Rank.jack;
    if (trumps.isEmpty || onlyPuur) return List.of(hand);
    return trumps;
  }

  // Andere Farbe wurde ausgespielt.
  var allowed = sameSuit.isNotEmpty ? [...sameSuit, ...trumps] : List.of(hand);

  // Untertrumpfen verhindern.
  final trumpsInTrick = trick.where((c) => c.suit == trump).toList();
  if (trumpsInTrick.isNotEmpty) {
    final highest = trumpsInTrick
        .map(mode.strengthInSuit)
        .reduce((a, b) => a > b ? a : b);
    final onlyTrumpsInHand = trumps.length == hand.length;
    if (!onlyTrumpsInHand) {
      final filtered = allowed
          .where((c) => c.suit != trump || mode.strengthInSuit(c) > highest)
          .toList();
      if (filtered.isNotEmpty) allowed = filtered;
    }
  }
  return allowed;
}

/// Ein Weis (Kartenfolge oder vier Gleiche) mit seinen Punkten.
class Weis {
  Weis(this.cards, this.points, {required this.isSequence});

  final List<JassCard> cards;
  final int points;
  final bool isSequence;

  String get label {
    if (!isSequence) {
      return 'Vier ${_plural(cards.first.rank)}';
    }
    const names = {
      3: 'Dreiblatt',
      4: 'Vierblatt',
      5: 'Fünfblatt',
      6: 'Sechsblatt',
      7: 'Siebenblatt',
      8: 'Achtblatt',
      9: 'Neunblatt',
    };
    return '${names[cards.length]} ${cards.first.suit.label}';
  }

  static String _plural(Rank r) => switch (r) {
        Rank.jack => 'Buben',
        Rank.nine => 'Neuner',
        Rank.ten => 'Zehner',
        Rank.queen => 'Damen',
        Rank.king => 'Könige',
        Rank.ace => 'Asse',
        _ => r.label,
      };

  @override
  String toString() => '$label ($points)';
}

const _sequencePoints = {3: 20, 4: 50, 5: 100, 6: 150, 7: 200, 8: 250, 9: 300};

/// Alle Weise in einer Hand (9 Karten).
///
/// Kartenfolgen zählen ab drei Karten derselben Farbe in natürlicher
/// Reihenfolge (6-7-8-9-10-Bube-Dame-König-Ass). Vier Gleiche zählen bei
/// Buben (200), Neunern (150) sowie 10, Dame, König, Ass (je 100).
List<Weis> findWeis(List<JassCard> hand) {
  final result = <Weis>[];
  for (final s in Suit.values) {
    final ranks = hand.where((c) => c.suit == s).map((c) => c.rank.index).toSet();
    var i = 0;
    while (i < 9) {
      if (!ranks.contains(i)) {
        i++;
        continue;
      }
      var j = i;
      while (j + 1 < 9 && ranks.contains(j + 1)) {
        j++;
      }
      final len = j - i + 1;
      if (len >= 3) {
        result.add(Weis(
          [for (var k = i; k <= j; k++) JassCard(s, Rank.values[k])],
          _sequencePoints[len]!,
          isSequence: true,
        ));
      }
      i = j + 1;
    }
  }
  const fourPoints = {
    Rank.jack: 200,
    Rank.nine: 150,
    Rank.ten: 100,
    Rank.queen: 100,
    Rank.king: 100,
    Rank.ace: 100,
  };
  for (final entry in fourPoints.entries) {
    final same = hand.where((c) => c.rank == entry.key).toList();
    if (same.length == 4) {
      result.add(Weis(same, entry.value, isSequence: false));
    }
  }
  return result;
}

/// Vergleichswert eines Weis: Wer den höchsten Weis hat, dessen Team
/// darf alle seine Weise zählen. Bei gleichem Wert gilt: mehr Karten,
/// dann höhere Karte (bei Undenufe die tiefere), dann Trumpf-Farbe.
/// Ist dann immer noch alles gleich, gewinnt, wer früher am Zug ist.
List<int> weisRank(Weis w, GameMode mode) {
  final topIndex = mode.type == ModeType.undenufe
      ? 8 - w.cards.map((c) => c.rank.index).reduce((a, b) => a < b ? a : b)
      : w.cards.map((c) => c.rank.index).reduce((a, b) => a > b ? a : b);
  final isTrump = w.isSequence && mode.isTrumpCard(w.cards.first) ? 1 : 0;
  return [w.points, w.cards.length, topIndex, isTrump];
}

int compareWeis(Weis a, Weis b, GameMode mode) {
  final ra = weisRank(a, mode);
  final rb = weisRank(b, mode);
  for (var i = 0; i < ra.length; i++) {
    if (ra[i] != rb[i]) return ra[i].compareTo(rb[i]);
  }
  return 0;
}

/// Hat die Hand «Stöck» (König und Dame im Trumpf)?
bool hasStoeck(List<JassCard> hand, GameMode mode) {
  if (!mode.isTrump) return false;
  final t = mode.trumpSuit!;
  return hand.contains(JassCard(t, Rank.king)) &&
      hand.contains(JassCard(t, Rank.queen));
}
