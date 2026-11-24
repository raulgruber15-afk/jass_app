import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/bot.dart';
import '../engine/cards.dart';
import '../engine/game_mode.dart';
import '../engine/profi_bot.dart';
import '../engine/schieber.dart';

enum BotLevel { anfaenger, stammtisch, profi }

/// Wer an einem Platz sitzt.
class SeatSetup {
  const SeatSetup({
    required this.name,
    required this.human,
    this.remote = false,
  });
  final String name;
  final bool human;

  /// Mensch an einem anderen Handy (Spiel über WLAN/Hotspot).
  final bool remote;
}

/// Standard: Du gegen drei Computergegner.
const List<SeatSetup> defaultSeats = [
  SeatSetup(name: 'Du', human: true),
  SeatSetup(name: 'Vreni', human: false),
  SeatSetup(name: 'Sepp', human: false),
  SeatSetup(name: 'Ruedi', human: false),
];

/// Verbindet die Spiellogik mit dem Bildschirm: lässt die Computergegner
/// mit kleinen Pausen spielen, regelt das Weitergeben des Handys und
/// meldet Änderungen an die Oberfläche.
///
/// Sitze 0 bis 3 im Gegenuhrzeigersinn, 0 und 2 sind ein Team.
class GameController extends ChangeNotifier {
  GameController({
    required SchieberSettings settings,
    this.level = BotLevel.stammtisch,
    this.fast = false,
    List<SeatSetup> seats = defaultSeats,
    SchieberGame? resumeFrom,
    this.onSave,
    this.sendAction,
    this.onBroadcast,
  }) : game = resumeFrom ?? SchieberGame(settings: settings),
       seats = List.of(seats) {
    for (var s = 0; s < 4; s++) {
      bots[s] = seats[s].human ? null : _makeBot();
    }
    viewer = seats.indexWhere((s) => s.human && !s.remote);
    handHidden = isMultiplayer;
    if (viewer < 0) viewer = 0;
  }

  JassBot _makeBot() => switch (level) {
    BotLevel.anfaenger => RandomBot(),
    BotLevel.stammtisch => RuleBot(),
    BotLevel.profi => ProfiBot(),
  };

  SchieberGame game;
  final List<SeatSetup> seats;

  /// Nur beim Mitspieler-Handy im WLAN-Spiel: Züge gehen an den Gastgeber,
  /// statt sie selbst auszuführen. Der Spielstand kommt vom Gastgeber.
  final void Function(Map<String, dynamic> action)? sendAction;

  /// Nur beim Gastgeber im WLAN-Spiel: nach jeder Änderung aufgerufen,
  /// damit der Stand an alle Handys geht.
  final void Function()? onBroadcast;

  /// Mitspieler-Handy (spielt nicht selbst, zeigt nur, was kommt).
  bool get isClient => sendAction != null;

  /// Spiel über mehrere Handys (Gastgeber oder Mitspieler).
  bool get isNetwork => isClient || seats.any((s) => s.remote);
  final List<JassBot?> bots = [null, null, null, null];
  final bool fast;
  final BotLevel level;

  /// Wird nach jeder Änderung mit dem ganzen Spielstand aufgerufen
  /// (null = Spiel ist fertig, gespeicherten Stand löschen).
  final void Function(Map<String, dynamic>? snapshot)? onSave;

  /// Spielstand inkl. Sitzen und Gegner-Stufe, zum Speichern.
  Map<String, dynamic> snapshot() => {
    'game': game.toJson(),
    'level': level.index,
    'fast': fast,
    'seats': [
      for (final s in seats) {'name': s.name, 'human': s.human},
    ],
  };

  /// Gespeichertes Spiel wiederherstellen.
  static GameController restore(
    Map<String, dynamic> snap, {
    void Function(Map<String, dynamic>?)? onSave,
  }) {
    final game = SchieberSave.fromJson(
      Map<String, dynamic>.from(snap['game'] as Map),
    );
    return GameController(
      settings: game.settings,
      level: BotLevel.values[snap['level'] as int],
      fast: snap['fast'] as bool,
      seats: [
        for (final s in snap['seats'] as List)
          SeatSetup(
            name: (s as Map)['name'] as String,
            human: s['human'] as bool,
          ),
      ],
      resumeFrom: game,
      onSave: onSave,
    );
  }

  /// Gespeichertes Spiel fortsetzen (statt neu austeilen).
  void resume() => _changed();

  /// Aus wessen Sicht der Tisch gerade gezeigt wird (dessen Karten unten).
  late int viewer;

  /// Sichtschutz: Das Handy muss an diese Person weitergegeben werden.
  int? handoverTo;

  /// Mehrere Personen: Karten unten verdeckt zeigen, sobald jemand gespielt
  /// hat, damit beim Weitergeben niemand fremde Karten sieht.
  bool handHidden = true;

  Timer? _timer;
  bool _disposed = false;

  /// Kurze Meldung über dem Tisch («Sepp schiebt», «Trumpf: Herz» …).
  String? banner;
  Timer? _bannerTimer;

  /// Sprechblasen bei den Sitzen (z. B. Weis im ersten Stich).
  final Map<int, String> bubbles = {};

  Duration get _botDelay => Duration(milliseconds: fast ? 350 : 750);
  Duration get _trickDelay => Duration(milliseconds: fast ? 700 : 1400);

  int get humanCount => seats.where((s) => s.human && !s.remote).length;

  /// Mehrere Personen an diesem einen Handy (Herumreichen).
  bool get isMultiplayer => humanCount > 1;
  bool isHuman(int seat) => seats[seat].human;

  /// Mensch, der an diesem Handy spielt.
  bool isLocal(int seat) => seats[seat].human && !seats[seat].remote;
  String nameOf(int seat) => seats[seat].name;

  /// Darf die Person, die gerade aufs Handy schaut, handeln?
  bool get viewerToAct =>
      handoverTo == null &&
      !(isMultiplayer && handHidden) &&
      (game.phase == Phase.chooseMode || game.phase == Phase.playing) &&
      game.toAct == viewer &&
      isLocal(viewer);

  /// «Du» bei nur einer Person, sonst der Name.
  String _subject(int seat) =>
      (!isMultiplayer && !isNetwork && isLocal(seat)) ? 'Du' : nameOf(seat);

  /// Name eines Teams aus Sicht der Person am Handy.
  String teamLabel(int team) {
    if (!isMultiplayer) return team == viewer % 2 ? 'Wir' : 'Gegner';
    return '${nameOf(team)} & ${nameOf(team + 2)}';
  }

  void start() {
    game.start();
    _announceChooser();
    _changed();
  }

  void nextRound() {
    if (isClient) return; // Nur der Gastgeber teilt neu aus.
    game.nextRound();
    bubbles.clear();
    _announceChooser();
    _changed();
  }

  void _announceChooser() {
    final c = game.chooser;
    _showBanner(
      _subject(c) == 'Du'
          ? 'Du bestimmst Trumpf'
          : '${nameOf(c)} bestimmt Trumpf',
    );
  }

  // ------------------------------------------------------- Weitergeben

  /// Person hat das Handy bekommen und tippt auf «Karten zeigen».
  void confirmHandover() {
    final to = handoverTo;
    if (to == null) return;
    viewer = to;
    handoverTo = null;
    handHidden = false;
    _changed();
  }

  /// Muss das Handy vor dem nächsten Zug weitergegeben werden?
  void _checkHandover() {
    final phase = game.phase;
    if (phase != Phase.chooseMode && phase != Phase.playing) return;
    final seat = game.toAct;
    if (!isLocal(seat)) return;
    if (!isMultiplayer) {
      viewer = seat;
      handHidden = false;
    } else if (handHidden || seat != viewer) {
      handoverTo = seat;
    }
  }

  // ------------------------------------------------------- Aktionen Mensch

  void humanSchieben() {
    if (!viewerToAct || !game.canSchieben) return;
    if (isClient) return sendAction!({'a': 'schieben'});
    final from = game.toAct;
    game.schieben();
    if (isMultiplayer) handHidden = true;
    final who = _subject(from) == 'Du'
        ? 'Du schiebst'
        : '${nameOf(from)} schiebt';
    _showBanner('$who zu ${nameOf(partnerOf(from))}');
    _changed();
  }

  void humanChooseMode(GameMode m) {
    if (!viewerToAct || game.phase != Phase.chooseMode) return;
    if (isClient) return sendAction!({'a': 'mode', 'm': modeToJson(m)});
    _applyMode(game.toAct, m);
  }

  void humanPlay(JassCard card) {
    if (!viewerToAct || game.phase != Phase.playing) return;
    if (!game.legalFor(viewer).contains(card)) return;
    if (isClient) return sendAction!({'a': 'play', 'c': card.id});
    _play(viewer, card);
  }

  // ------------------------------------------------------------- Ablauf

  void _applyMode(int seat, GameMode m) {
    if (isHuman(seat) && isMultiplayer) handHidden = true;
    game.chooseMode(m);
    final mult = game.multiplier > 1 ? ' (×${game.multiplier})' : '';
    final who = _subject(seat) == 'Du' ? 'Du machst' : '${nameOf(seat)} macht';
    _showBanner('$who ${m.label}$mult');
    for (final a in game.announcements) {
      bubbles[a.seat] = a.weise.map((w) => w.label).join(', ');
    }
    _changed();
  }

  void _play(int seat, JassCard card) {
    if (isHuman(seat) && isMultiplayer) handHidden = true;
    final hadStoeck = game.stoeckAnnounced;
    game.playCard(seat, card);
    if (!hadStoeck && game.stoeckAnnounced) {
      bubbles[seat] = 'Stöck!';
    }
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    _checkHandover();
    notifyListeners();
    onBroadcast?.call();
    if (isClient) return;
    _scheduleNext();
    final save = onSave;
    if (save != null) {
      save(game.phase == Phase.gameOver ? null : snapshot());
    }
  }

  void _scheduleNext() {
    _timer?.cancel();
    switch (game.phase) {
      case Phase.chooseMode:
        if (bots[game.toAct] != null) {
          _timer = Timer(_botDelay * 1.5, _botChoose);
        }
      case Phase.playing:
        if (bots[game.toAct] != null) _timer = Timer(_botDelay, _botPlay);
      case Phase.trickComplete:
        _timer = Timer(_trickDelay, _collect);
      case Phase.roundOver:
      case Phase.gameOver:
        break;
    }
  }

  void _botChoose() {
    final seat = game.toAct;
    final m = bots[seat]!.chooseMode(
      game.viewFor(seat),
      canSchieben: game.canSchieben,
    );
    if (m == null) {
      game.schieben();
      _showBanner('${nameOf(seat)} schiebt');
      _changed();
    } else {
      _applyMode(seat, m);
    }
  }

  void _botPlay() {
    final seat = game.toAct;
    _play(seat, bots[seat]!.chooseCard(game.viewFor(seat)));
  }

  void _collect() {
    final wasFirst = game.tricks.isEmpty;
    game.collectTrick();
    if (wasFirst) {
      // Weis-Blasen nach dem ersten Stich ausblenden, Ergebnis melden.
      bubbles.removeWhere((_, v) => v != 'Stöck!');
      final team = game.weisWinnerTeam;
      if (team != null) {
        final pts = game.roundWeis[team];
        _showBanner(
          !isMultiplayer && !isNetwork
              ? (team == viewer % 2
                    ? 'Ihr zählt $pts Weispunkte'
                    : 'Gegner zählen $pts Weispunkte')
              : '${teamLabel(team)}: $pts Weispunkte',
        );
      }
    } else {
      bubbles.clear();
    }
    _changed();
  }

  void _showBanner(String text) {
    banner = text;
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(milliseconds: 2200), () {
      banner = null;
      if (!_disposed) {
        notifyListeners();
        onBroadcast?.call();
      }
    });
  }

  // ------------------------------------------------ Spiel über mehrere Handys

  /// Gastgeber: Was das Handy am Platz [seat] sehen darf. Die Karten der
  /// anderen werden durch Platzhalter ersetzt (nur die Anzahl stimmt).
  Map<String, dynamic> stateFor(int seat) {
    final j = game.toJson();
    j['hands'] = [
      for (var s = 0; s < 4; s++)
        s == seat
            ? [for (final c in game.hands[s]) c.id]
            : List<int>.filled(game.hands[s].length, 0),
    ];
    return {
      'game': j,
      'banner': banner,
      'bubbles': {for (final e in bubbles.entries) '${e.key}': e.value},
      'seats': [
        for (final s in seats) {'name': s.name, 'human': s.human},
      ],
    };
  }

  /// Mitspieler: neuen Stand vom Gastgeber übernehmen.
  void applyRemoteState(Map<String, dynamic> st) {
    if (_disposed) return;
    game = SchieberSave.fromJson(Map<String, dynamic>.from(st['game'] as Map));
    banner = st['banner'] as String?;
    bubbles
      ..clear()
      ..addAll({
        for (final e in Map<String, dynamic>.from(st['bubbles'] as Map).entries)
          int.parse(e.key): e.value as String,
      });
    final names = st['seats'] as List;
    for (var s = 0; s < 4; s++) {
      final x = Map<String, dynamic>.from(names[s] as Map);
      final human = x['human'] as bool;
      seats[s] = SeatSetup(
        name: x['name'] as String,
        human: human,
        remote: s != viewer && human,
      );
    }
    notifyListeners();
  }

  /// Gastgeber: Zug von einem anderen Handy ausführen (wird geprüft).
  void remoteAction(int seat, Map<String, dynamic> a) {
    if (_disposed || !seats[seat].remote || game.toAct != seat) return;
    switch (a['a']) {
      case 'schieben':
        if (game.phase != Phase.chooseMode || !game.canSchieben) return;
        game.schieben();
        _showBanner('${nameOf(seat)} schiebt zu ${nameOf(partnerOf(seat))}');
        _changed();
      case 'mode':
        if (game.phase != Phase.chooseMode) return;
        final m = modeFromJson(Map<String, dynamic>.from(a['m'] as Map));
        _applyMode(seat, m);
      case 'play':
        if (game.phase != Phase.playing) return;
        final card = JassCard.fromId(a['c'] as int);
        if (!game.legalFor(seat).contains(card)) return;
        _play(seat, card);
    }
  }

  /// Gastgeber: Mitspieler weg, der Computer übernimmt den Platz.
  void seatToBot(int seat) {
    if (!seats[seat].remote) return;
    seats[seat] = SeatSetup(name: seats[seat].name, human: false);
    bots[seat] = _makeBot();
    _showBanner('${nameOf(seat)} ist weg, der Computer spielt weiter');
    _changed();
  }

  /// Gastgeber: Mitspieler ist wieder da und übernimmt seinen Platz.
  void seatToRemote(int seat) {
    seats[seat] = SeatSetup(name: seats[seat].name, human: true, remote: true);
    bots[seat] = null;
    _showBanner('${nameOf(seat)} ist wieder dabei');
    _changed();
  }

  /// Gastgeber: neue Partie mit denselben Leuten.
  void restart() {
    if (isClient) return;
    game = SchieberGame(settings: game.settings);
    bubbles.clear();
    start();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }
}
