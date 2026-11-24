import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/rating.dart';
import 'engine/schieber.dart';
import 'ui/card_widget.dart';
import 'ui/game_controller.dart';
import 'ui/game_screen.dart';
import 'ui/net_screens.dart';
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

  /// false = allein gegen den Computer, true = mit Freunden.
  bool together = false;

  /// Mit Freunden: false = ein Handy herumreichen, true = jedes eigene Handy.
  bool network = false;

  /// Eigener Name im Spiel über mehrere Handys.
  final myName = TextEditingController();
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

  /// Bilanz gegen den Computer je Stufe: [gewonnen, verloren].
  Map<String, List<int>> stats = {};

  /// Jass-Wertung allein gegen den Computer.
  SoloRating rating = const SoloRating();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Storage.loadSettings();
    final g = await Storage.loadGame();
    final st = await Storage.loadStats();
    final rt = await Storage.loadSoloRating();
    if (!mounted) return;
    setState(() {
      stats = st;
      rating = rt;
      if (s != null) {
        target = s['target'] as int? ?? target;
        multipliers = s['multipliers'] as bool? ?? multipliers;
        fast = s['fast'] as bool? ?? fast;
        final deck = s['deck'] as String?;
        if (schweizerBlattFreigegeben) {
          cardDeck = CardDeck.values.firstWhere(
            (d) => d.name == deck,
            orElse: () => cardDeck,
          );
        }
        final lv = s['level'] as String?;
        level = BotLevel.values.firstWhere(
          (l) => l.name == lv,
          orElse: () => level,
        );
        together = s['together'] as bool? ?? together;
        network = !kIsWeb && (s['network'] as bool? ?? network);
        myName.text = s['myName'] as String? ?? '';
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
    'deck': cardDeck.name,
    'level': level.name,
    'together': together,
    'network': network,
    'myName': myName.text,
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

  String _statsLine() {
    final l = stats[level.name];
    final bilanz = l == null
        ? 'Noch keine Partie gegen diese Stufe gespielt.'
        : 'Deine Bilanz: ${l[0]} gewonnen, ${l[1]} verloren';
    if (rating.games == 0) return bilanz;
    final wert =
        'Jass-Wertung ${rating.value}'
        '${rating.provisional ? ' (vorläufig)' : ''}'
        '${rating.best != null ? ' · Bestwert ${rating.best}' : ''}';
    return '$wert\n$bilanz';
  }

  Future<void> _open(GameScreen screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    final g = await Storage.loadGame();
    final st = await Storage.loadStats();
    final rt = await Storage.loadSoloRating();
    if (mounted) {
      setState(() {
        saved = g;
        stats = st;
        rating = rt;
      });
    }
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
    myName.dispose();
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
    _precache();
  }

  void _precache() {
    for (final path in cardAssetPaths) {
      precacheImage(AssetImage(path), context);
    }
  }

  void _setDeck(CardDeck d) {
    setState(() => cardDeck = d);
    _precache();
    _saveSettings();
  }

  String get _myName {
    final n = myName.text.trim();
    return n.isEmpty ? 'Gast' : n;
  }

  void _host() {
    _saveSettings();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostLobbyScreen(
          name: _myName,
          settings: SchieberSettings(
            targetPoints: target,
            useMultipliers: multipliers,
          ),
          level: level,
          fast: fast,
        ),
      ),
    );
  }

  void _join() {
    _saveSettings();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => JoinScreen(name: _myName)));
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
                    _Logo(key: ValueKey(cardDeck)),
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
                    if (together && !kIsWeb) ...[
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Ein Handy'),
                            icon: Icon(Icons.phone_android),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Jeder sein Handy'),
                            icon: Icon(Icons.wifi),
                          ),
                        ],
                        selected: {network},
                        onSelectionChanged: (s) =>
                            setState(() => network = s.first),
                      ),
                    ],
                    if (together && network && !kIsWeb) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Alle Handys im gleichen WLAN oder im Hotspot eines Handys. '
                        'Ein Handy eröffnet das Spiel und zeigt einen QR-Code, die '
                        'anderen treten bei. Freie Plätze übernimmt der Computer. '
                        'Internet braucht es nicht.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: myName,
                        maxLength: 14,
                        style: const TextStyle(color: JassColors.cream),
                        decoration: const InputDecoration(
                          labelText: 'Dein Name',
                          labelStyle: TextStyle(color: Colors.white70),
                          counterText: '',
                          isDense: true,
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white38),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: JassColors.gold),
                          ),
                        ),
                      ),
                    ] else if (together) ...[
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
                    if (together && network && !kIsWeb) ...[
                      FilledButton.icon(
                        onPressed: _host,
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Spiel eröffnen'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _join,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: JassColors.cream,
                          side: const BorderSide(color: JassColors.cream),
                        ),
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Beitreten'),
                      ),
                    ] else if (saved != null) ...[
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
                    if (schweizerBlattFreigegeben) ...[
                      const Text('Karten', style: labelStyle),
                      const SizedBox(height: 6),
                      SegmentedButton<CardDeck>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: CardDeck.schweizer,
                            label: Text('Schweizer'),
                          ),
                          ButtonSegment(
                            value: CardDeck.franzoesisch,
                            label: Text('Französisch'),
                          ),
                        ],
                        selected: {cardDeck},
                        onSelectionChanged: (s) => _setDeck(s.first),
                      ),
                      const SizedBox(height: 16),
                    ],
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
                    if (!together)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _statsLine(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Mit Multiplikatoren',
                        style: labelStyle,
                      ),
                      subtitle: Text(
                        '${Suit.herz.label}/${Suit.karo.label} ×1, '
                        '${Suit.pik.label}/${Suit.kreuz.label} ×2, '
                        'Obenabe/Undenufe ×3',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
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
  const _Logo({super.key});

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
