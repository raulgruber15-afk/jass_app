import 'package:flutter/material.dart';

import '../engine/cards.dart';
import '../engine/game_mode.dart';
import 'theme.dart';

/// Seitenverhältnis der Kartengrafiken des gewählten Blatts
/// (Schweizer Blatt 500 × 781, französisches 500 × 809 Pixel).
double get cardAspect => cardDeck == CardDeck.schweizer ? 500 / 781 : 500 / 809;

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
    final img = Image.asset(
      '$cardDir/$name.png',
      width: width,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: card?.label ?? 'Karte verdeckt',
    );
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
