import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/bot.dart';
import '../engine/cards.dart';
import '../engine/game_mode.dart';
import '../engine/schieber.dart';

enum BotLevel { anfaenger, stammtisch }

/// Wer an einem Platz sitzt.
class SeatSetup {
  const SeatSetup({required this.name, required this.human});
  final String name;
  final bool human;
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
    BotLevel level = BotLevel.stammtisch,
    this.fast = false,
    List<SeatSetup> seats = defaultSeats,
  })  : game = SchieberGame(settings: settings),
        seats = List.unmodifiable(seats) {
    for (var s = 0; s < 4; s++) {
      bots[s] = seats[s].human
          ? null
          : (level == BotLevel.anfaenger ? RandomBot() : RuleBot());
    }
    viewer = seats.indexWhere((s) => s.human);
    handHidden = isMultiplayer;
    if (viewer < 0) viewer = 0;
  }

  final SchieberGame game;
  final List<SeatSetup> seats;
  final List<JassBot?> bots = [null, null, null, null];
  final bool fast;

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

  int get humanCount => seats.where((s) => s.human).length;
  bool get isMultiplayer => humanCount > 1;
  bool isHuman(int seat) => seats[seat].human;
  String nameOf(int seat) => seats[seat].name;

  /// Darf die Person, die gerade aufs Handy schaut, handeln?
  bool get viewerToAct =>
      handoverTo == null &&
      !(isMultiplayer && handHidden) &&
      (game.phase == Phase.chooseMode || game.phase == Phase.playing) &&
      game.toAct == viewer &&
      isHuman(viewer);

  /// «Du» bei nur einer Person, sonst der Name.
  String _subject(int seat) =>
      (!isMultiplayer && isHuman(seat)) ? 'Du' : nameOf(seat);

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
    game.nextRound();
    bubbles.clear();
    _announceChooser();
    _changed();
  }

  void _announceChooser() {
    final c = game.chooser;
    _showBanner(!isMultiplayer && isHuman(c)
        ? 'Du bestimmst Trumpf'
        : '${nameOf(c)} bestimmt Trumpf');
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
    if (!isHuman(seat)) return;
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
    final from = game.toAct;
    game.schieben();
    if (isMultiplayer) handHidden = true;
    final who = isMultiplayer ? '${nameOf(from)} schiebt' : 'Du schiebst';
    _showBanner('$who zu ${nameOf(partnerOf(from))}');
    _changed();
  }

  void humanChooseMode(GameMode m) {
    if (!viewerToAct || game.phase != Phase.chooseMode) return;
    _applyMode(game.toAct, m);
  }

  void humanPlay(JassCard card) {
    if (!viewerToAct || game.phase != Phase.playing) return;
    if (!game.legalFor(viewer).contains(card)) return;
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
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    switch (game.phase) {
      case Phase.chooseMode:
        if (!isHuman(game.toAct)) _timer = Timer(_botDelay * 1.5, _botChoose);
      case Phase.playing:
        if (!isHuman(game.toAct)) _timer = Timer(_botDelay, _botPlay);
      case Phase.trickComplete:
        _timer = Timer(_trickDelay, _collect);
      case Phase.roundOver:
      case Phase.gameOver:
        break;
    }
  }

  void _botChoose() {
    final seat = game.toAct;
    final m = bots[seat]!.chooseMode(game.viewFor(seat), canSchieben: game.canSchieben);
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
        _showBanner(!isMultiplayer
            ? (team == viewer % 2
                ? 'Ihr zählt $pts Weispunkte'
                : 'Gegner zählen $pts Weispunkte')
            : '${teamLabel(team)}: $pts Weispunkte');
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
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }
}
