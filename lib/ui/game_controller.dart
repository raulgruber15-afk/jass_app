import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/bot.dart';
import '../engine/cards.dart';
import '../engine/game_mode.dart';
import '../engine/schieber.dart';

enum BotLevel { anfaenger, stammtisch }

/// Verbindet die Spiellogik mit dem Bildschirm: lässt die Computergegner
/// mit kleinen Pausen spielen und meldet Änderungen an die Oberfläche.
class GameController extends ChangeNotifier {
  GameController({
    required SchieberSettings settings,
    BotLevel level = BotLevel.stammtisch,
    this.fast = false,
  }) : game = SchieberGame(settings: settings) {
    for (var s = 1; s < 4; s++) {
      bots[s] = level == BotLevel.anfaenger ? RandomBot() : RuleBot();
    }
  }

  /// Sitz der Person am Gerät (unten).
  static const int humanSeat = 0;

  static const List<String> names = ['Du', 'Vreni', 'Sepp', 'Ruedi'];

  final SchieberGame game;
  final List<JassBot?> bots = [null, null, null, null];
  final bool fast;

  Timer? _timer;
  bool _disposed = false;

  /// Kurze Meldung über dem Tisch («Sepp schiebt», «Trumpf: Herz» …).
  String? banner;
  Timer? _bannerTimer;

  /// Sprechblasen bei den Sitzen (z. B. Weis im ersten Stich).
  final Map<int, String> bubbles = {};

  Duration get _botDelay => Duration(milliseconds: fast ? 350 : 750);
  Duration get _trickDelay => Duration(milliseconds: fast ? 700 : 1400);

  bool get humanToAct => game.toAct == humanSeat;

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
    final who = game.chooser == humanSeat
        ? 'Du bestimmst Trumpf'
        : '${names[game.chooser]} bestimmt Trumpf';
    _showBanner(who);
  }

  // ------------------------------------------------------- Aktionen Mensch

  void humanSchieben() {
    if (!humanToAct || !game.canSchieben) return;
    game.schieben();
    _showBanner('Du schiebst zu ${names[partnerOf(humanSeat)]}');
    _changed();
  }

  void humanChooseMode(GameMode m) {
    if (!humanToAct || game.phase != Phase.chooseMode) return;
    _applyMode(humanSeat, m);
  }

  void humanPlay(JassCard card) {
    if (!humanToAct || game.phase != Phase.playing) return;
    if (!game.legalFor(humanSeat).contains(card)) return;
    _play(humanSeat, card);
  }

  // ------------------------------------------------------------- Ablauf

  void _applyMode(int seat, GameMode m) {
    game.chooseMode(m);
    final mult = game.multiplier > 1 ? ' (×${game.multiplier})' : '';
    final who = seat == humanSeat ? 'Du machst' : '${names[seat]} macht';
    _showBanner('$who ${m.label}$mult');
    for (final a in game.announcements) {
      bubbles[a.seat] = a.weise.map((w) => w.label).join(', ');
    }
    _changed();
  }

  void _play(int seat, JassCard card) {
    final hadStoeck = game.stoeckAnnounced;
    game.playCard(seat, card);
    if (!hadStoeck && game.stoeckAnnounced) {
      bubbles[seat] = 'Stöck!';
    }
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    switch (game.phase) {
      case Phase.chooseMode:
        if (!humanToAct) _timer = Timer(_botDelay * 1.5, _botChoose);
      case Phase.playing:
        if (!humanToAct) _timer = Timer(_botDelay, _botPlay);
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
      _showBanner('${names[seat]} schiebt');
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
        _showBanner(team == teamOf(humanSeat)
            ? 'Ihr zählt $pts Weispunkte'
            : 'Gegner zählen $pts Weispunkte');
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
