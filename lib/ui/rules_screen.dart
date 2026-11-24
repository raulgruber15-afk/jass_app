import 'package:flutter/material.dart';

import 'theme.dart';

/// Kurze Spielregeln und Hinweise zur App.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const h = TextStyle(
      color: JassColors.gold,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    );
    const p = TextStyle(color: JassColors.cream, fontSize: 15, height: 1.4);
    Widget section(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: h),
          const SizedBox(height: 6),
          Text(body, style: p),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Regeln & Info'),
        backgroundColor: JassColors.feltDark,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          section(
            'Schieber',
            'Du spielst mit Sepp (oben) gegen Vreni und Ruedi. Wer Trumpf bestimmt, '
                'kann zum Partner schieben. Gespielt wird im Gegenuhrzeigersinn. '
                'Ziel ist das eingestellte Punkteziel.',
          ),
          section(
            'Karten zugeben',
            'Die angespielte Farbe muss angegeben werden. Trumpf darf man immer spielen. '
                'Der Trumpf-Under bzw. Trumpf-Bube (Puur) muss nie angegeben werden. Untertrumpfen ist '
                'verboten, ausser man hat nur noch Trumpf. Erlaubte Karten sind '
                'hervorgehoben, die anderen abgedunkelt.',
          ),
          section(
            'Punkte',
            'Trumpf: Puur (Under/Bube) 20, Nell (9) 14, Ass 11, König 4, '
                'Ober/Dame 3, Banner/10 zählt 10. '
                'Nebenfarben: Ass 11, König 4, Ober/Dame 3, Under/Bube 2, '
                'Banner/10 zählt 10. '
                'Obenabe und Undenufe: 8 zählt 8 (Undenufe: 6 zählt 11, Ass 0). '
                'Letzter Stich +5, Match (alle Stiche) 257.',
          ),
          section(
            'Weis und Stöck',
            'Folgen ab drei Karten (20, 50, 100 …) und vier Gleiche (Puure 200, '
                'Neuner 150, sonst 100) werden automatisch gewiesen. Nur das Team '
                'mit dem höchsten Weis zählt. Stöck (König und Ober/Dame im Trumpf) '
                'gibt 20 Punkte.',
          ),
          section(
            'Gegner',
            'Anfänger spielt zufällige erlaubte Karten. Stammtisch spielt nach '
                'Faustregeln (Trumpf ziehen, Böcke spielen, Partner schmieren). '
                'Profi merkt sich alle gespielten Karten, erkennt, wer welche Farbe '
                'nicht mehr hat, und rechnet vor jedem Zug Hunderte mögliche '
                'Spielverläufe durch. Kein Gegner sieht deine Karten.',
          ),
          section(
            'Karten',
            'Auf der Startseite wählst du Schweizer Blatt (Eicheln, Schellen, '
                'Rosen, Schilten) oder französisches Blatt (Kreuz, Karo, Herz, '
                'Pik). Die Regeln sind gleich. Schweizer Blatt: Openclipart, '
                'mariotomo, gemeinfrei.',
          ),
          section(
            'Offline',
            'Das Spiel braucht kein Internet und sammelt keine Daten.',
          ),
        ],
      ),
    );
  }
}
