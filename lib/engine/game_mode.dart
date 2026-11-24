import 'cards.dart';

/// Art des Spiels: Trumpf in einer Farbe, Obenabe oder Undenufe.
enum ModeType { trump, obenabe, undenufe }

/// Die gewählte Spielart einer Runde («Was isch Trumpf?»).
class GameMode {
  const GameMode.trump(Suit this.trumpSuit) : type = ModeType.trump;
  const GameMode.obenabe() : type = ModeType.obenabe, trumpSuit = null;
  const GameMode.undenufe() : type = ModeType.undenufe, trumpSuit = null;

  final ModeType type;

  /// Nur bei [ModeType.trump] gesetzt.
  final Suit? trumpSuit;

  /// Alle sechs möglichen Spielarten.
  static const List<GameMode> all = [
    GameMode.trump(Suit.herz),
    GameMode.trump(Suit.karo),
    GameMode.trump(Suit.pik),
    GameMode.trump(Suit.kreuz),
    GameMode.obenabe(),
    GameMode.undenufe(),
  ];

  bool get isTrump => type == ModeType.trump;

  bool isTrumpCard(JassCard c) => isTrump && c.suit == trumpSuit;

  String get label => switch (type) {
    ModeType.trump => trumpSuit!.label,
    ModeType.obenabe => 'Obenabe',
    ModeType.undenufe => 'Undenufe',
  };

  String get symbol => switch (type) {
    ModeType.trump => trumpSuit!.symbol,
    ModeType.obenabe => '↓',
    ModeType.undenufe => '↑',
  };

  /// Kartenpunkte einer Karte in dieser Spielart.
  int points(JassCard c) {
    if (isTrumpCard(c)) {
      switch (c.rank) {
        case Rank.jack:
          return 20;
        case Rank.nine:
          return 14;
        default:
          break;
      }
    }
    switch (c.rank) {
      case Rank.ace:
        return type == ModeType.undenufe ? 0 : 11;
      case Rank.six:
        return type == ModeType.undenufe ? 11 : 0;
      case Rank.eight:
        return isTrump ? 0 : 8;
      case Rank.king:
        return 4;
      case Rank.queen:
        return 3;
      case Rank.jack:
        return 2;
      case Rank.ten:
        return 10;
      default:
        return 0;
    }
  }

  /// Stärke einer Karte innerhalb ihrer Farbe (höher = sticht mehr).
  /// Trumpf: Bube, 9, Ass, König, Dame, 10, 8, 7, 6.
  /// Undenufe: 6 ist die höchste Karte.
  int strengthInSuit(JassCard c) {
    if (isTrumpCard(c)) {
      const order = [
        Rank.six,
        Rank.seven,
        Rank.eight,
        Rank.ten,
        Rank.queen,
        Rank.king,
        Rank.ace,
        Rank.nine,
        Rank.jack,
      ];
      return order.indexOf(c.rank);
    }
    if (type == ModeType.undenufe) return 8 - c.rank.index;
    return c.rank.index;
  }

  /// Gewinnt Karte [challenger] gegen die bisher beste Karte [best],
  /// wenn [leadSuit] ausgespielt wurde?
  bool beats(JassCard challenger, JassCard best, Suit leadSuit) {
    final cTrump = isTrumpCard(challenger);
    final bTrump = isTrumpCard(best);
    if (cTrump && !bTrump) return true;
    if (!cTrump && bTrump) return false;
    if (cTrump && bTrump) {
      return strengthInSuit(challenger) > strengthInSuit(best);
    }
    // Beide kein Trumpf: nur die angespielte Farbe kann stechen.
    if (challenger.suit != best.suit) return false;
    return strengthInSuit(challenger) > strengthInSuit(best);
  }

  /// Index (0..n-1) der Karte, die den Stich gewinnt.
  int winningIndex(List<JassCard> trick) {
    var best = 0;
    final lead = trick.first.suit;
    for (var i = 1; i < trick.length; i++) {
      if (beats(trick[i], trick[best], lead)) best = i;
    }
    return best;
  }

  @override
  bool operator ==(Object other) =>
      other is GameMode && other.type == type && other.trumpSuit == trumpSuit;

  @override
  int get hashCode => Object.hash(type, trumpSuit);

  @override
  String toString() => label;
}
