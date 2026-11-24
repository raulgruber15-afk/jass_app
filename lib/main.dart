import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/schieber.dart';
import 'ui/card_widget.dart';
import 'ui/game_controller.dart';
import 'ui/game_screen.dart';
import 'ui/rules_screen.dart';
import 'ui/theme.dart';
import 'engine/cards.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const JassApp());
}

class JassApp extends StatelessWidget {
  const JassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jass',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int target = 2500;
  bool multipliers = true;
  BotLevel level = BotLevel.stammtisch;
  bool fast = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kartenbilder vorladen, damit beim ersten Austeilen nichts flackert.
    for (final c in [...fullDeck.map((c) => c.assetName), 'rueckseite']) {
      precacheImage(AssetImage('assets/cards/$c.png'), context);
    }
  }

  void _play() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen(
        settings: SchieberSettings(targetPoints: target, useMultipliers: multipliers),
        level: level,
        fast: fast,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(color: JassColors.cream, fontSize: 15);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF2A6350), JassColors.felt, JassColors.feltDark],
            stops: [0, 0.6, 1],
            radius: 1.1,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 8),
                    const Text('Jass',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: JassColors.cream,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                    const Text('Schieber gegen den Computer',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: JassColors.gold, fontSize: 16)),
                    const SizedBox(height: 28),
                    FilledButton(onPressed: _play, child: const Text('Spielen')),
                    const SizedBox(height: 28),
                    const Text('Punkteziel', style: labelStyle),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1000, label: Text('1000')),
                        ButtonSegment(value: 1500, label: Text('1500')),
                        ButtonSegment(value: 2500, label: Text('2500')),
                      ],
                      selected: {target},
                      onSelectionChanged: (s) => setState(() => target = s.first),
                    ),
                    const SizedBox(height: 16),
                    const Text('Gegner', style: labelStyle),
                    const SizedBox(height: 6),
                    SegmentedButton<BotLevel>(
                      segments: const [
                        ButtonSegment(value: BotLevel.anfaenger, label: Text('Anfänger')),
                        ButtonSegment(value: BotLevel.stammtisch, label: Text('Stammtisch')),
                      ],
                      selected: {level},
                      onSelectionChanged: (s) => setState(() => level = s.first),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mit Multiplikatoren', style: labelStyle),
                      subtitle: const Text(
                          'Herz/Karo ×1, Pik/Kreuz ×2, Obenabe/Undenufe ×3',
                          style: TextStyle(color: Colors.white60, fontSize: 12)),
                      value: multipliers,
                      onChanged: (v) => setState(() => multipliers = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Schnelles Tempo', style: labelStyle),
                      value: fast,
                      onChanged: (v) => setState(() => fast = v),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RulesScreen())),
                      child: const Text('Regeln & Info',
                          style: TextStyle(color: JassColors.gold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    const cards = [
      JassCard(Suit.karo, Rank.nine),
      JassCard(Suit.herz, Rank.jack),
      JassCard(Suit.pik, Rank.ace),
    ];
    return SizedBox(
      height: 120,
      child: Stack(alignment: Alignment.bottomCenter, children: [
        for (var i = 0; i < 3; i++)
          Transform.rotate(
            angle: (i - 1) * 0.22,
            alignment: Alignment.bottomCenter,
            child: Transform.translate(
              offset: Offset((i - 1) * 30.0, 0),
              child: CardImage(card: cards[i], width: 66),
            ),
          ),
      ]),
    );
  }
}
