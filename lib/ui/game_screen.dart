import 'dart:math';

import 'package:flutter/material.dart';

import '../engine/cards.dart';
import '../engine/game_mode.dart';
import '../engine/schieber.dart';
import 'card_widget.dart';
import 'game_controller.dart';
import 'theme.dart';

/// Der Spieltisch: unten die eigenen Karten, oben der Partner,
/// links und rechts die Gegner, in der Mitte der Stich.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.settings,
    required this.level,
    required this.fast,
  });

  final SchieberSettings settings;
  final BotLevel level;
  final bool fast;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameController ctrl;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  void _newGame() {
    ctrl = GameController(
        settings: widget.settings, level: widget.level, fast: widget.fast)
      ..start();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<bool> _confirmLeave() async {
    if (ctrl.game.phase == Phase.gameOver) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Spiel beenden?'),
        content: const Text('Der aktuelle Spielstand geht verloren.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Weiterspielen')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Beenden')),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              colors: [Color(0xFF2A6350), JassColors.felt, JassColors.feltDark],
              stops: [0, 0.6, 1],
              radius: 1.1,
            ),
          ),
          child: SafeArea(
            child: ListenableBuilder(
              listenable: ctrl,
              builder: (context, _) => _buildTable(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final g = ctrl.game;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final handW = min(w / 5.2, 118.0);
      return Stack(
        children: [
          Column(
            children: [
              _ScoreBar(
                ctrl: ctrl,
                onClose: () async {
                  final nav = Navigator.of(context);
                  if (await _confirmLeave()) nav.pop();
                },
              ),
              Expanded(child: _TableArea(ctrl: ctrl)),
              SizedBox(
                height: handW / cardAspect + 22,
                child: _Hand(ctrl: ctrl, cardWidth: handW),
              ),
            ],
          ),
          if (g.phase == Phase.chooseMode && ctrl.humanToAct)
            Positioned(
              left: 8,
              right: 8,
              bottom: handW / cardAspect + 26,
              child: _TrumpChooser(ctrl: ctrl),
            ),
          if (g.phase == Phase.roundOver || g.phase == Phase.gameOver)
            Positioned.fill(
              child: _ResultPanel(
                ctrl: ctrl,
                onNewGame: () => setState(() {
                  ctrl.dispose();
                  _newGame();
                }),
                onMenu: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      );
    });
  }
}

// ------------------------------------------------------------------ Punkte

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.ctrl, required this.onClose});
  final GameController ctrl;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final g = ctrl.game;
    final mode = g.mode;
    const label = TextStyle(color: Colors.white70, fontSize: 12);
    const value = TextStyle(
        color: JassColors.cream, fontSize: 20, fontWeight: FontWeight.bold);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 6),
      color: Colors.black26,
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: 'Spiel beenden',
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Wir', style: label),
            Text('${g.totals[0]}', style: value),
          ]),
          const SizedBox(width: 18),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Gegner', style: label),
            Text('${g.totals[1]}', style: value),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Ziel ${g.settings.targetPoints}',
                style: label, overflow: TextOverflow.ellipsis),
          ),
          if (mode != null) _ModeBadge(mode: mode, multiplier: g.multiplier),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode, required this.multiplier});
  final GameMode mode;
  final int multiplier;

  @override
  Widget build(BuildContext context) {
    final red = mode.isTrump && mode.trumpSuit!.isRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: JassColors.cream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JassColors.gold, width: 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(mode.symbol,
            style: TextStyle(
                fontSize: 20, color: red ? JassColors.red : JassColors.navy)),
        const SizedBox(width: 6),
        Text(
          multiplier > 1 ? '${mode.label} ×$multiplier' : mode.label,
          style: const TextStyle(
              color: JassColors.navy, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------- Tisch

class _TableArea extends StatelessWidget {
  const _TableArea({required this.ctrl});
  final GameController ctrl;

  @override
  Widget build(BuildContext context) {
    final g = ctrl.game;
    return LayoutBuilder(builder: (context, box) {
      final tw = box.maxWidth;
      final th = box.maxHeight;
      final cw = min(min(tw / 4.4, th / 3.4 * cardAspect), 100.0);
      final ch = cw / cardAspect;
      final cx = tw / 2;
      final cy = th / 2 + 6;

      Offset offsetFor(int seat) => switch (seat) {
            0 => Offset(0, ch * 0.33),
            1 => Offset(cw * 0.62, 0),
            2 => Offset(0, -ch * 0.33),
            _ => Offset(-cw * 0.62, 0),
          };

      final winnerIdx = g.phase == Phase.trickComplete && g.trick.length == 4
          ? g.mode!.winningIndex(g.trick)
          : -1;

      return Stack(clipBehavior: Clip.none, children: [
        // Mitspieler
        Positioned(
            top: 4, left: 0, right: 0, child: Center(child: _Seat(ctrl: ctrl, seat: 2))),
        Positioned(left: 4, top: cy - 70, child: _Seat(ctrl: ctrl, seat: 3)),
        Positioned(right: 4, top: cy - 70, child: _Seat(ctrl: ctrl, seat: 1)),

        // Stich
        for (var i = 0; i < g.trick.length; i++)
          Positioned(
            key: ValueKey('trick-${g.trick[i].id}'),
            left: cx - cw / 2 + offsetFor(g.trickSeats[i]).dx,
            top: cy - ch / 2 + offsetFor(g.trickSeats[i]).dy,
            child: _SlideIn(
              from: offsetFor(g.trickSeats[i]) * 2.5,
              child: Container(
                decoration: i == winnerIdx
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(color: JassColors.gold, blurRadius: 14, spreadRadius: 2)
                        ],
                      )
                    : null,
                child: CardImage(card: g.trick[i], width: cw),
              ),
            ),
          ),

        // Meldung
        if (ctrl.banner != null)
          Positioned(
            left: 0,
            right: 0,
            top: cy - ch * 0.95 - 34,
            child: Center(child: _Banner(text: ctrl.banner!)),
          ),

        if (g.phase == Phase.playing && ctrl.humanToAct)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            child: Center(
              child: Text('Du bist dran – tippe auf eine Karte',
                  style: TextStyle(color: JassColors.gold, fontWeight: FontWeight.w600)),
            ),
          ),

        // Eigene Sprechblase (Weis/Stöck)
        if (ctrl.bubbles[0] != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Center(child: _Bubble(text: 'Du: ${ctrl.bubbles[0]}')),
          ),
      ]);
    });
  }
}

class _SlideIn extends StatelessWidget {
  const _SlideIn({required this.from, required this.child});
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) =>
          Transform.translate(offset: from * t, child: Opacity(opacity: 1 - t * 0.5, child: c)),
      child: child,
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({required this.ctrl, required this.seat});
  final GameController ctrl;
  final int seat;

  @override
  Widget build(BuildContext context) {
    final g = ctrl.game;
    final active = g.toAct == seat &&
        (g.phase == Phase.playing || g.phase == Phase.chooseMode);
    final count = g.hands[seat].length;
    final isPartner = seat == 2;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? JassColors.gold : Colors.black38,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '${GameController.names[seat]}${isPartner ? ' (Partner)' : ''}'
          '${g.chooser == seat && g.mode != null ? ' ★' : ''}',
          style: TextStyle(
            color: active ? JassColors.navy : JassColors.cream,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(
        width: 34.0 + max(0, count - 1) * 4.0,
        height: 50,
        child: Stack(children: [
          for (var i = 0; i < count; i++)
            Positioned(left: i * 4.0, child: const CardImage(width: 30)),
        ]),
      ),
      if (ctrl.bubbles[seat] != null) ...[
        const SizedBox(height: 4),
        _Bubble(text: ctrl.bubbles[seat]!),
      ],
    ]);
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(color: JassColors.cream, fontSize: 16)),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: JassColors.cream,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JassColors.gold),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: JassColors.navy, fontSize: 12)),
      );
}

// -------------------------------------------------------------- Eigene Hand

class _Hand extends StatelessWidget {
  const _Hand({required this.ctrl, required this.cardWidth});
  final GameController ctrl;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final g = ctrl.game;
    final hand = _sorted(g.hands[GameController.humanSeat], g.mode);
    final myTurn = g.phase == Phase.playing && ctrl.humanToAct;
    final legal = myTurn ? g.legalFor(GameController.humanSeat).toSet() : <JassCard>{};

    return LayoutBuilder(builder: (context, box) {
      final avail = box.maxWidth - 16;
      final n = hand.length;
      final step = n <= 1
          ? 0.0
          : min(cardWidth + 4, (avail - cardWidth) / (n - 1));
      final total = n == 0 ? 0.0 : cardWidth + step * (n - 1);
      final start = (box.maxWidth - total) / 2;
      return Stack(children: [
        for (var i = 0; i < n; i++)
          AnimatedPositioned(
            key: ValueKey('hand-${hand[i].id}'),
            duration: const Duration(milliseconds: 180),
            left: start + i * step,
            top: myTurn && legal.contains(hand[i]) ? 2 : 18,
            child: GestureDetector(
              onTap: () => ctrl.humanPlay(hand[i]),
              child: CardImage(
                card: hand[i],
                width: cardWidth,
                dimmed: myTurn && !legal.contains(hand[i]),
              ),
            ),
          ),
      ]);
    });
  }

  /// Hand nach Farben sortieren, Trumpf links, innerhalb nach Stärke.
  static List<JassCard> _sorted(List<JassCard> hand, GameMode? mode) {
    const suitOrder = [Suit.herz, Suit.pik, Suit.karo, Suit.kreuz];
    int suitKey(JassCard c) =>
        mode != null && mode.isTrumpCard(c) ? -1 : suitOrder.indexOf(c.suit);
    int rankKey(JassCard c) =>
        mode == null ? c.rank.index : mode.strengthInSuit(c);
    return List.of(hand)
      ..sort((a, b) {
        final s = suitKey(a).compareTo(suitKey(b));
        return s != 0 ? s : rankKey(b).compareTo(rankKey(a));
      });
  }
}

// ------------------------------------------------------------- Trumpfwahl

class _TrumpChooser extends StatelessWidget {
  const _TrumpChooser({required this.ctrl});
  final GameController ctrl;

  @override
  Widget build(BuildContext context) {
    final g = ctrl.game;
    return Material(
      color: JassColors.feltDark.withValues(alpha: 0.96),
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            g.geschoben ? 'Geschoben! Du musst wählen.' : 'Was isch Trumpf?',
            style: const TextStyle(
                color: JassColors.cream, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.1,
            children: [
              for (final m in GameMode.all) _modeButton(g, m),
            ],
          ),
          if (g.canSchieben) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: ctrl.humanSchieben,
                style: OutlinedButton.styleFrom(
                  foregroundColor: JassColors.cream,
                  side: const BorderSide(color: JassColors.gold),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Schieben (Sepp wählt)', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _modeButton(SchieberGame g, GameMode m) {
    final red = m.isTrump && m.trumpSuit!.isRed;
    final mult = g.settings.multiplierFor(m);
    return Material(
      color: JassColors.cream,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ctrl.humanChooseMode(m),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${m.symbol} ${m.label}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: red ? JassColors.red : JassColors.navy)),
            if (mult > 1)
              Text('zählt ×$mult',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------- Abrechnung

class _ResultPanel extends StatelessWidget {
  const _ResultPanel(
      {required this.ctrl, required this.onNewGame, required this.onMenu});
  final GameController ctrl;
  final VoidCallback onNewGame;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final g = ctrl.game;
    final r = g.lastResult;
    final over = g.phase == Phase.gameOver;
    final won = g.winnerTeam == 0;

    Widget row(String label, int a, int b, {bool bold = false}) {
      final st = TextStyle(
          color: JassColors.navy,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontSize: bold ? 17 : 15);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: st)),
          SizedBox(width: 70, child: Text('$a', style: st, textAlign: TextAlign.right)),
          SizedBox(width: 70, child: Text('$b', style: st, textAlign: TextAlign.right)),
        ]),
      );
    }

    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: JassColors.cream,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: JassColors.gold, width: 3),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            over ? (won ? 'Gewonnen!' : 'Verloren') : 'Runde ${g.roundNumber}',
            style: const TextStyle(
                color: JassColors.navy, fontSize: 26, fontWeight: FontWeight.bold),
          ),
          if (r != null) ...[
            const SizedBox(height: 4),
            Text(
              '${r.mode.symbol} ${r.mode.label}'
              '${r.multiplier > 1 ? ' (zählt ×${r.multiplier})' : ''}',
              style: const TextStyle(color: JassColors.navy),
            ),
            if (r.matchTeam != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  r.matchTeam == 0 ? 'Match! Alle Stiche für euch.' : 'Match für die Gegner.',
                  style: const TextStyle(
                      color: JassColors.red, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            const SizedBox(height: 12),
            Row(children: const [
              Expanded(child: SizedBox()),
              SizedBox(width: 70, child: Text('Wir', textAlign: TextAlign.right, style: TextStyle(color: Colors.black54))),
              SizedBox(width: 70, child: Text('Gegner', textAlign: TextAlign.right, style: TextStyle(color: Colors.black54))),
            ]),
            row('Stiche', r.cardPoints[0] * r.multiplier, r.cardPoints[1] * r.multiplier),
            if (r.weisPoints.any((p) => p > 0)) row('Weis', r.weisPoints[0], r.weisPoints[1]),
            if (r.stoeckPoints.any((p) => p > 0)) row('Stöck', r.stoeckPoints[0], r.stoeckPoints[1]),
            const Divider(color: JassColors.gold),
            row('Diese Runde', r.scoreFor(0), r.scoreFor(1), bold: true),
            row('Total', g.totals[0], g.totals[1], bold: true),
          ],
          const SizedBox(height: 18),
          if (!over)
            FilledButton(onPressed: ctrl.nextRound, child: const Text('Nächste Runde'))
          else
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(
                onPressed: onMenu,
                child: const Text('Menü', style: TextStyle(color: JassColors.navy)),
              ),
              const SizedBox(width: 12),
              FilledButton(onPressed: onNewGame, child: const Text('Neues Spiel')),
            ]),
        ]),
      ),
    );
  }
}
