import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/schieber.dart';
import 'ui/card_widget.dart';
import 'ui/game_controller.dart';
import 'ui/game_screen.dart';
import 'ui/rules_screen.dart';
import 'ui/storage.dart';
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

  /// false = allein gegen den Computer, true = mehrere Personen am Handy.
  bool together = false;
  final names = [
    TextEditingController(text: 'Anna'),
    TextEditingController(text: 'Vreni'),
    TextEditingController(text: 'Sepp'),
    TextEditingController(text: 'Ruedi'),
  ];
  final humans = [true, false, true, false];

  static const seatLabels = ['Unten', 'Rechts', 'Gegenüber', 'Links'];

  /// Angefangenes Spiel, falls vorhanden.
  Map<String, dynamic>? saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Storage.loadSettings();
    final g = await Storage.loadGame();
    if (!mounted) return;
    setState(() {
      if (s != null) {
        target = s['target'] as int? ?? target;
        multipliers = s['multipliers'] as bool? ?? multipliers;
        fast = s['fast'] as bool? ?? fast;
        final lv = s['level'] as String?;
        level = BotLevel.values.firstWhere(
          (l) => l.name == lv,
          orElse: () => level,
        );
        together = s['together'] as bool? ?? together;
        final n = s['names'] as List?;
        final h = s['humans'] as List?;
        for (var i = 0; i < 4; i++) {
          if (n != null && i < n.length) names[i].text = n[i] as String;
          if (h != null && i < h.length) humans[i] = h[i] as bool;
        }
      }
      saved = g;
    });
  }

  void _saveSettings() => Storage.saveSettings({
    'target': target,
    'multipliers': multipliers,
    'fast': fast,
    'level': level.name,
    'together': together,
    'names': [for (final c in names) c.text],
    'humans': humans,
  });

  /// «Runde 4 · 312 : 287» für den Weiterspielen-Knopf.
  String? _savedInfo() {
    try {
      final g = saved!['game'] as Map<String, dynamic>;
      final t = g['totals'] as List;
      final round = (g['history'] as List).length + 1;
      return 'Runde $round · Wir ${t[0]} : ${t[1]} Gegner';
    } catch (_) {
      return null;
    }
  }

  Future<void> _open(GameScreen screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    final g = await Storage.loadGame();
    if (mounted) setState(() => saved = g);
  }

  void _resume() => _open(
    GameScreen(
      settings: const SchieberSettings(),
      level: level,
      fast: fast,
      resume: saved,
    ),
  );

  @override
  void dispose() {
    for (final c in names) {
      c.dispose();
    }
    super.dispose();
  }

  List<SeatSetup> _seats() {
    if (!together) return defaultSeats;
    const fallback = ['Spieler 1', 'Spieler 2', 'Spieler 3', 'Spieler 4'];
    return [
      for (var i = 0; i < 4; i++)
        SeatSetup(
          name: names[i].text.trim().isEmpty
              ? fallback[i]
              : names[i].text.trim(),
          human: i == 0 || humans[i],
        ),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kartenbilder vorladen, damit beim ersten Austeilen nichts flackert.
    for (final c in [...fullDeck.map((c) => c.assetName), 'rueckseite']) {
      precacheImage(AssetImage('assets/cards/$c.png'), context);
    }
  }

  void _play() {
    _saveSettings();
    _open(
      GameScreen(
        settings: SchieberSettings(
          targetPoints: target,
          useMultipliers: multipliers,
        ),
        level: level,
        fast: fast,
        seats: _seats(),
      ),
    );
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
                    const Text(
                      'Jass',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: JassColors.cream,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const Text(
                      'Schieber – allein oder mit Freunden',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: JassColors.gold, fontSize: 16),
                    ),
                    const SizedBox(height: 28),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Allein'),
                          icon: Icon(Icons.person),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Mit Freunden'),
                          icon: Icon(Icons.groups),
                        ),
                      ],
                      selected: {together},
                      onSelectionChanged: (s) =>
                          setState(() => together = s.first),
                    ),
                    if (together) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Ein Handy für alle: Es wird vor jedem Zug weitergegeben. '
                        'Unten und Gegenüber spielen zusammen, Rechts und Links ebenfalls. '
                        'Leere Plätze übernimmt der Computer.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < 4; i++) _seatRow(i),
                    ],
                    const SizedBox(height: 20),
                    if (saved != null) ...[
                      FilledButton.icon(
                        onPressed: _resume,
                        icon: const Icon(Icons.play_arrow),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Weiterspielen'),
                              if (_savedInfo() != null)
                                Text(
                                  _savedInfo()!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _play,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: JassColors.cream,
                          side: const BorderSide(color: JassColors.cream),
                        ),
                        child: const Text('Neues Spiel'),
                      ),
                    ] else
                      FilledButton(
                        onPressed: _play,
                        child: const Text('Spielen'),
                      ),
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
                      onSelectionChanged: (s) =>
                          setState(() => target = s.first),
                    ),
                    const SizedBox(height: 16),
                    const Text('Gegner', style: labelStyle),
                    const SizedBox(height: 6),
                    SegmentedButton<BotLevel>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: BotLevel.anfaenger,
                          label: Text('Anfänger'),
                        ),
                        ButtonSegment(
                          value: BotLevel.stammtisch,
                          label: Text('Stammtisch'),
                        ),
                        ButtonSegment(
                          value: BotLevel.profi,
                          label: Text('Profi'),
                        ),
                      ],
                      selected: {level},
                      onSelectionChanged: (s) =>
                          setState(() => level = s.first),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Mit Multiplikatoren',
                        style: labelStyle,
                      ),
                      subtitle: const Text(
                        'Herz/Karo ×1, Pik/Kreuz ×2, Obenabe/Undenufe ×3',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
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
                        MaterialPageRoute(builder: (_) => const RulesScreen()),
                      ),
                      child: const Text(
                        'Regeln & Info',
                        style: TextStyle(color: JassColors.gold),
                      ),
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

extension on _HomeScreenState {
  Widget _seatRow(int i) {
    final isHuman = i == 0 || humans[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              _HomeScreenState.seatLabels[i],
              style: const TextStyle(color: JassColors.gold, fontSize: 13),
            ),
          ),
          Expanded(
            child: TextField(
              controller: names[i],
              enabled: isHuman,
              maxLength: 12,
              style: const TextStyle(color: JassColors.cream),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText: isHuman ? 'Name' : 'Computer',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: i == 0
                ? const Text(
                    'Mensch',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  )
                : SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.person),
                        tooltip: 'Mensch',
                      ),
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.smart_toy),
                        tooltip: 'Computer',
                      ),
                    ],
                    selected: {isHuman},
                    onSelectionChanged: (s) =>
                        // ignore: invalid_use_of_protected_member
                        setState(() => humans[i] = s.first),
                  ),
          ),
        ],
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
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.rotate(
              angle: (i - 1) * 0.22,
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: Offset((i - 1) * 30.0, 0),
                child: CardImage(card: cards[i], width: 66),
              ),
            ),
        ],
      ),
    );
  }
}
