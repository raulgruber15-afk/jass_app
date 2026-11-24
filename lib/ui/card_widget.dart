import 'package:flutter/material.dart';

import '../engine/cards.dart';
import '../engine/game_mode.dart';
import 'theme.dart';

/// Seitenverhältnis der Kartengrafiken des gewählten Blatts
/// (Schweizer Blatt 500 × 780, französisches 500 × 809 Pixel).
double get cardAspect => cardDeck == CardDeck.schweizer ? 500 / 780 : 500 / 809;

/// Ordner der Kartenbilder des gewählten Blatts.
String get cardDir =>
    cardDeck == CardDeck.schweizer ? 'assets/cards_ch' : 'assets/cards';

/// Alle Bildpfade des gewählten Blatts (zum Vorladen).
List<String> get cardAssetPaths => [
  for (final n in [...fullDeck.map((c) => c.assetName), 'rueckseite'])
    '$cardDir/$n.png',
];

/// Zeigt eine Karte (oder die Rückseite, wenn [card] null ist).
class CardImage extends StatelessWidget {
  const CardImage({
    super.key,
    this.card,
    required this.width,
    this.dimmed = false,
  });

  final JassCard? card;
  final double width;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final name = card?.assetName ?? 'rueckseite';
    final height = width / cardAspect;
    Widget img = Image.asset(
      '$cardDir/$name.png',
      width: width,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: card?.label ?? 'Karte verdeckt',
    );
    // Die Bildkarten des Schweizer Blatts haben keine Ecke mit Wert.
    // Damit man sie im aufgefächerten Blatt erkennt: kleines U / O / K.
    final c = card;
    if (cardDeck == CardDeck.schweizer &&
        c != null &&
        (c.rank == Rank.jack || c.rank == Rank.queen || c.rank == Rank.king)) {
      final letter = switch (c.rank) {
        Rank.jack => 'U',
        Rank.queen => 'O',
        _ => 'K',
      };
      img = Stack(
        children: [
          img,
          Positioned(
            left: width * 0.07,
            top: height * 0.045,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.035,
                vertical: width * 0.005,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(width * 0.04),
                border: Border.all(color: Colors.black54, width: 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    letter,
                    style: TextStyle(
                      fontSize: width * 0.15,
                      height: 1.05,
                      fontWeight: FontWeight.bold,
                      color: c.suit.isRed ? JassColors.red : Colors.black,
                    ),
                  ),
                  Image.asset(
                    'assets/suits_ch/${c.suit.name}.png',
                    width: width * 0.13,
                    height: width * 0.13,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.06),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(1, 2)),
        ],
      ),
      child: dimmed
          ? ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black45,
                BlendMode.srcATop,
              ),
              child: img,
            )
          : img,
    );
  }
}

/// Zeichen für eine Spielart: Schweizer Farbsymbol als Bild,
/// französisches als Schriftzeichen, Obenabe/Undenufe als Pfeil.
class ModeSymbol extends StatelessWidget {
  const ModeSymbol(this.mode, {super.key, this.size = 18, this.color});

  final GameMode mode;
  final double size;

  /// Farbe für Schriftzeichen; ohne Angabe rot/dunkelblau je nach Farbe.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final suit = mode.trumpSuit;
    if (suit != null && cardDeck == CardDeck.schweizer) {
      return Image.asset(
        'assets/suits_ch/${suit.name}.png',
        width: size * 1.15,
        height: size * 1.15,
      );
    }
    return Text(
      mode.symbol,
      style: TextStyle(
        fontSize: size,
        height: 1,
        color:
            color ??
            (suit != null && suit.isRed ? JassColors.red : JassColors.navy),
      ),
    );
  }
}
