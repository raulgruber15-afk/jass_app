// Karten, Farben und Werte für den Jass (36 Karten, 6 bis Ass).
//
// Dieser Teil weiss nichts vom Bildschirm. Er wird von der Spiellogik,
// den Computergegnern und später vom WLAN-Spiel gemeinsam benutzt.

/// Welches Kartenbild gezeigt wird. Die Regeln sind bei beiden gleich,
/// nur Namen und Bilder ändern sich.
enum CardDeck { schweizer, franzoesisch }

/// Aktuell gewähltes Blatt (Einstellung auf der Startseite).
CardDeck cardDeck = CardDeck.schweizer;

bool get _swiss => cardDeck == CardDeck.schweizer;

/// Die vier Farben. Intern französisch benannt; im Schweizer Blatt
/// entspricht Kreuz = Eicheln, Herz = Rosen, Pik = Schilten, Karo = Schellen.
enum Suit {
  kreuz('Kreuz', 'Eicheln', '♣'),
  herz('Herz', 'Rosen', '♥'),
  pik('Pik', 'Schilten', '♠'),
  karo('Karo', 'Schellen', '♦');

  const Suit(this.frenchLabel, this.swissLabel, this.symbol);

  final String frenchLabel;
  final String swissLabel;

  /// Name im gewählten Blatt, z. B. «Herz» oder «Rosen».
  String get label => _swiss ? swissLabel : frenchLabel;

  /// Französisches Symbol, z. B. «♥» (für Schweizer Farben gibt es
  /// kein Schriftzeichen; die App zeigt dort ein Bild).
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

  const Rank(this.frenchLabel, this.fileName);

  final String frenchLabel;

  /// Name im gewählten Blatt (Schweizer Blatt: Banner, Under, Ober).
  String get label => !_swiss
      ? frenchLabel
      : switch (this) {
          Rank.ten => 'Banner',
          Rank.jack => 'Under',
          Rank.queen => 'Ober',
          _ => frenchLabel,
        };

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
