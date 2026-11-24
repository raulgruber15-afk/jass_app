// Karten, Farben und Werte für den Jass (französisches Blatt, 6 bis Ass).
//
// Dieser Teil weiss nichts vom Bildschirm. Er wird von der Spiellogik,
// den Computergegnern und später vom WLAN-Spiel gemeinsam benutzt.

/// Die vier Farben des französischen Blatts.
enum Suit {
  kreuz('Kreuz', '♣'),
  herz('Herz', '♥'),
  pik('Pik', '♠'),
  karo('Karo', '♦');

  const Suit(this.label, this.symbol);

  /// Name auf Deutsch, z. B. «Herz».
  final String label;

  /// Symbol, z. B. «♥».
  final String symbol;

  bool get isRed => this == Suit.herz || this == Suit.karo;
}

/// Die neun Kartenwerte. Die Reihenfolge entspricht der «natürlichen»
/// Reihenfolge (6 tief, Ass hoch), wie sie bei Obenabe und für Weis gilt.
enum Rank {
  six('6', '6'),
  seven('7', '7'),
  eight('8', '8'),
  nine('9', '9'),
  ten('10', '10'),
  jack('Bube', 'bube'),
  queen('Dame', 'dame'),
  king('König', 'koenig'),
  ace('Ass', 'ass');

  const Rank(this.label, this.fileName);

  final String label;

  /// Teil des Dateinamens der Kartengrafik, z. B. «koenig».
  final String fileName;
}

/// Eine einzelne Jasskarte.
class JassCard implements Comparable<JassCard> {
  const JassCard(this.suit, this.rank);

  final Suit suit;
  final Rank rank;

  /// Eindeutige Nummer 0 bis 35 (praktisch zum Speichern und Übertragen).
  int get id => suit.index * 9 + rank.index;

  static JassCard fromId(int id) =>
      JassCard(Suit.values[id ~/ 9], Rank.values[id % 9]);

  /// Name der Grafikdatei ohne Endung, z. B. «herz_bube».
  String get assetName => '${suit.name}_${rank.fileName}';

  /// Lesbarer Name, z. B. «Herz Bube».
  String get label => '${suit.label} ${rank.label}';

  @override
  bool operator ==(Object other) =>
      other is JassCard && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => id;

  @override
  int compareTo(JassCard other) => id.compareTo(other.id);

  @override
  String toString() => '${suit.symbol}${rank.label}';
}

/// Alle 36 Karten in fester Reihenfolge.
final List<JassCard> fullDeck = List<JassCard>.unmodifiable([
  for (final s in Suit.values)
    for (final r in Rank.values) JassCard(s, r),
]);
