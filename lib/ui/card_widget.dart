import 'package:flutter/material.dart';

import '../engine/cards.dart';

/// Seitenverhältnis der Kartengrafiken (500 × 809 Pixel).
const double cardAspect = 500 / 809;

/// Zeigt eine Karte (oder die Rückseite, wenn [card] null ist).
class CardImage extends StatelessWidget {
  const CardImage({super.key, this.card, required this.width, this.dimmed = false});

  final JassCard? card;
  final double width;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final name = card?.assetName ?? 'rueckseite';
    final img = Image.asset(
      'assets/cards/$name.png',
      width: width,
      height: width / cardAspect,
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
              colorFilter: const ColorFilter.mode(Colors.black45, BlendMode.srcATop),
              child: img,
            )
          : img,
    );
  }
}
